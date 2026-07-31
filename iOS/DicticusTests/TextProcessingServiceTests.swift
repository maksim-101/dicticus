import XCTest
@testable import Dicticus

/// TextProcessingService integration tests — cross-platform parity (macOS + iOS).
///
/// Coverage:
///   - Pipeline order (dictionary → ITN) — testPipelineOrder, testGermanPipeline.
///   - D-23 / CLEAN-01 cleanup wiring — testCleanupPath, testPlainModeSkipsCleanup.
///   - D-13 blocks-until-cleaned — testBlocksUntilCleaned.
///   - Provider !isLoaded short-circuit — testCleanupSkippedWhenProviderNotLoaded.
///   - Phase 20.08 R7 dialect gate ordering — testDialectGateRunsBeforeLevenshteinAndDemotes.
///   - Phase 25-02 plain-mode JSONL parity (#if DEBUG_RECORDER).
///   - Phase 25.1-01 lang_used + emission_counter (#if DEBUG_RECORDER).
///   - Phase 27-02 dictionary_replacements end-to-end (#if DEBUG_RECORDER).
///
/// Per feedback_cleanup_cross_platform_parity memory: this file is byte-
/// identical to iOS/DicticusTests/TextProcessingServiceTests.swift.
@MainActor
final class TextProcessingServiceTests: XCTestCase {

    /// Minimal mock conforming to the existing `CleanupProvider` protocol.
    ///
    /// Phase 38 Plan 01 (CTXFMT-01, approved scope extension): `cleanup`
    /// gained a `context:` parameter on the protocol; `lastContext` records
    /// it so tests can spy on what the pipeline actually threaded through.
    final class MockCleanupProvider: CleanupProvider {
        var isLoaded: Bool = true
        private(set) var callCount = 0
        private(set) var lastLanguage: String = ""
        private(set) var lastInput: String = ""
        private(set) var lastContext: DictationContext = .default
        var returnValue: String = "cleaned output"
        var artificialDelayMs: UInt64 = 0

        func cleanup(text: String, language: String, dictionaryContext: [String: String]?, context: DictationContext = .default) async -> String {
            callCount += 1
            lastLanguage = language
            lastInput = text
            lastContext = context
            if artificialDelayMs > 0 {
                try? await Task.sleep(nanoseconds: artificialDelayMs * 1_000_000)
            }
            return returnValue
        }
    }

    var service: TextProcessingService!
    var dictionaryService: DictionaryService!
    /// Isolated history so the pipeline's Step-4 save() never writes to the real
    /// App Group database. Without this, every test run polluted (and the
    /// HistoryServiceTests clearAll wiped) the user's live transcription history.
    var testHistory: HistoryService!

    override func setUp() {
        super.setUp()
        // Use a fresh dictionary service for isolation
        UserDefaults.standard.removeObject(forKey: DictionaryService.dictionaryKey)
        dictionaryService = DictionaryService.shared
        dictionaryService.removeAll()
        let historyContainer = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("TPSTests-\(UUID().uuidString)", isDirectory: true)
        testHistory = HistoryService.makeForTesting(containerURLProvider: { historyContainer })
        service = TextProcessingService(dictionaryService: dictionaryService, cleanupService: nil, historyService: testHistory)
    }

    override func tearDown() {
        testHistory = nil
        super.tearDown()
    }

    // MARK: - Pipeline order (dictionary → ITN)

    func testPipelineOrder() async {
        // 1. Set up dictionary: "bird" -> "one hundred"
        dictionaryService.setReplacement(for: "bird", with: "one hundred")

        let input = "I have a bird"
        // Expected: "I have a bird" -> "I have a one hundred" (Dictionary) -> "I have a 100" (ITN)
        let output = await service.process(text: input, language: "en", mode: .plain)

        XCTAssertEqual(output, "I have a 100")
    }

    func testGermanPipeline() async {
        dictionaryService.setReplacement(for: "Apfel", with: "einhundert")

        let input = "Ich habe einen Apfel"
        // Expected: "Ich habe einen Apfel" -> "Ich habe einen einhundert" -> "Ich habe einen 100"
        let output = await service.process(text: input, language: "de", mode: .plain)

        XCTAssertEqual(output, "Ich habe einen 100")
    }

    // MARK: - D-23 / CLEAN-01: Cleanup path is wired

    func testCleanupPath() async {
        let mock = MockCleanupProvider()
        mock.returnValue = "Hallo Welt, das ist ein Test."
        let service = TextProcessingService(cleanupService: mock, historyService: testHistory)

        let output = await service.process(
            text: "hallo welt das ist ein test",
            language: "de",
            mode: .aiCleanup
        )

        XCTAssertEqual(mock.callCount, 1, "Cleanup mock must be invoked once in .aiCleanup mode")
        XCTAssertEqual(mock.lastLanguage, "de")
        XCTAssertEqual(output, "Hallo Welt, das ist ein Test.")
    }

    // MARK: - Plain mode bypasses cleanup

    func testPlainModeSkipsCleanup() async {
        let mock = MockCleanupProvider()
        let service = TextProcessingService(cleanupService: mock, historyService: testHistory)

        let output = await service.process(
            text: "hallo welt",
            language: "de",
            mode: .plain
        )

        XCTAssertEqual(mock.callCount, 0, "Cleanup mock must NOT run in .plain mode")
        // Dictionary + ITN passes still run, but with no cleanup the text survives
        // in recognizable form.
        XCTAssertTrue(output.contains("welt") || output.contains("Welt"),
                      "Plain output should preserve the input text")
    }

    // MARK: - D-13: Blocks until cleaned (no raw-then-replace)

    func testBlocksUntilCleaned() async {
        let mock = MockCleanupProvider()
        mock.artificialDelayMs = 250
        // "Hello world." is gate-compatible with input "hello world":
        // all content words ≥4 chars ("hello", "world") survive lowercased in
        // the output tokens, so gateContentWords returns llmOutput unchanged.
        mock.returnValue = "Hello world."
        let service = TextProcessingService(cleanupService: mock, historyService: testHistory)

        let start = Date()
        let output = await service.process(
            text: "hello world",
            language: "en",
            mode: .aiCleanup
        )
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(output, "Hello world.",
                       "process() must return the cleaned value, not the raw input")
        XCTAssertGreaterThanOrEqual(elapsed, 0.2,
                                    "process() must block until cleanup completes (D-13)")
    }

    // MARK: - Cleanup skipped when provider reports !isLoaded

    func testCleanupSkippedWhenProviderNotLoaded() async {
        let mock = MockCleanupProvider()
        mock.isLoaded = false
        let service = TextProcessingService(cleanupService: mock, historyService: testHistory)

        _ = await service.process(text: "hello", language: "en", mode: .aiCleanup)

        XCTAssertEqual(mock.callCount, 0,
                       "Cleanup must be skipped when provider.isLoaded == false")
    }

    // MARK: - D-08/MLANG-03: non-de/en language routes to rules-only (Phase 42-02)

    func testCleanupSkippedForNonDeEnLanguage() async {
        let mock = MockCleanupProvider()
        mock.returnValue = "should never be used"
        let service = TextProcessingService(cleanupService: mock, historyService: testHistory)

        let ruleOnlyService = TextProcessingService(cleanupService: nil, historyService: testHistory)
        let ruleOnlyOutput = await ruleOnlyService.process(text: "bonjour le monde", language: "other", mode: .aiCleanup)

        let output = await service.process(text: "bonjour le monde", language: "other", mode: .aiCleanup)

        XCTAssertEqual(mock.callCount, 0,
                       "Cleanup mock must NOT run when language is \"other\" (non-de/en)")
        XCTAssertEqual(output, ruleOnlyOutput,
                       "A non-de/en language must return the deterministic rules-only output, identical to the no-cleanup-provider baseline")
    }

    func testCleanupStillRunsForDeEnLanguage() async {
        let mock = MockCleanupProvider()
        mock.returnValue = "Hallo Welt."
        let service = TextProcessingService(cleanupService: mock, historyService: testHistory)

        _ = await service.process(text: "hallo welt", language: "de", mode: .aiCleanup)

        XCTAssertEqual(mock.callCount, 1,
                       "Cleanup mock must still run for language == \"de\" (no regression)")
    }

    // MARK: - Phase 20.08 R7: dialect gate stacks before Levenshtein

    /// Phase 20.08 R7: dialect gate runs BEFORE Levenshtein gate.
    /// Mock LLM returns Swiss-ified output — final processedText must NOT
    /// contain Swiss dialect tokens (gate demoted to rules-cleaned baseline),
    /// proving the dialect gate fires BEFORE the structural Levenshtein gate.
    ///
    /// Word-boundary check: substring "uf " is also inside "auf ", so
    /// dialect-token presence is verified via the same tokenizer the gate
    /// uses (`tokenizeForDialectGate`), not raw substring `.contains`.
    func testDialectGateRunsBeforeLevenshteinAndDemotes() async {
        let mock = MockCleanupProvider()
        mock.returnValue = "uf de andere Siite"
        let service = TextProcessingService(cleanupService: mock, historyService: testHistory)

        let output = await service.process(
            text: "auf der anderen seite",
            language: "de",
            mode: .aiCleanup
        )

        let outputTokens = Set(CleanupService.tokenizeForDialectGate(output))
        XCTAssertFalse(outputTokens.contains("uf"),
            "Phase 20.08 R7: dialect gate must demote — output must not contain Swiss form 'uf' as a word token")
        XCTAssertFalse(outputTokens.contains("siite"),
            "Phase 20.08 R7: dialect gate must demote — output must not contain Swiss form 'siite' as a word token")
    }

    // MARK: - Phase 25-02: plain-mode DEBUG_RECORDER write-path parity

    #if DEBUG_RECORDER
    /// Phase 25-02: plain-mode dictation cycles emit a JSONL record in the
    /// same daily file as aiCleanup cycles, distinguishable by the `mode`
    /// field. LLM-section keys (`llm_prompt`, `llm_raw`, `post_gate`) are
    /// nil/absent. Also verifies that aiCleanup records continue to emit
    /// with non-nil LLM fields — the no-regression invariant for the
    /// existing AI write path.
    ///
    /// NOTE: this test appends to the user's REAL DebugRecordings file at
    /// ~/Library/Application Support/Dicticus/DebugRecordings/ — it is
    /// only compiled when the `DEBUG_RECORDER` flag is set (the Debug-
    /// Recorder scheme), never in the public release. Each run uses a
    /// unique probe substring so reruns do not produce false positives
    /// from prior runs' lines.
    func testPlainModeWritesDebugRecord() async throws {
        let svc = TextProcessingService(cleanupService: nil, historyService: testHistory)
        let probe = "phase25-02-plain-probe-\(UUID().uuidString.prefix(8))"

        _ = await svc.process(text: probe, language: "en", mode: .plain, confidence: 1.0)

        // Allow the DebugRecorder actor a tick to flush its append.
        try await Task.sleep(nanoseconds: 100_000_000)

        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Dicticus/DebugRecordings", isDirectory: true)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        let fileURL = dir.appendingPathComponent("cleanup-\(f.string(from: Date())).jsonl")

        let lines = try String(contentsOf: fileURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        let match = lines.first { $0.contains(probe) }
        let plainLine = try XCTUnwrap(match,
            "expected plain-mode record containing '\(probe)' in \(fileURL.path)")
        XCTAssertTrue(plainLine.contains("\"mode\":\"plain\""),
            "Phase 25-02: plain-mode record must carry mode=plain — got: \(plainLine)")
        XCTAssertTrue(plainLine.contains("\"llm_prompt\":null") || !plainLine.contains("llm_prompt"),
            "Phase 25-02: llm_prompt must be null/absent in plain-mode record")
        XCTAssertTrue(plainLine.contains("\"llm_raw\":null") || !plainLine.contains("llm_raw"),
            "Phase 25-02: llm_raw must be null/absent in plain-mode record")
        XCTAssertTrue(plainLine.contains("\"post_gate\":null") || !plainLine.contains("post_gate"),
            "Phase 25-02: post_gate must be null/absent in plain-mode record")
    }

    /// Phase 25-02: no-regression invariant — aiCleanup records continue
    /// to emit with `mode == "aiCleanup"` and non-nil LLM fields after
    /// the plain-mode parity work. Uses a mock cleanup provider so the
    /// test does not depend on a loaded LLM. (CleanupService.lastDebugTrace
    /// is only populated by the real CleanupService; a pure mock leaves
    /// `cleanupTrace == nil`, which makes `llm_prompt`/`llm_raw` resolve
    /// to nil — so this test asserts only the `mode` discriminator, which
    /// is the field Plan 25-04 actually uses to split plain vs AI streams.)
    func testAICleanupModeWritesDebugRecordWithModeAICleanup() async throws {
        let mock = MockCleanupProvider()
        mock.returnValue = "Polished output for phase25-02-ai-probe"
        let svc = TextProcessingService(cleanupService: mock, historyService: testHistory)
        let probe = "phase25-02-ai-probe-\(UUID().uuidString.prefix(8))"

        _ = await svc.process(text: probe, language: "en", mode: .aiCleanup, confidence: 1.0)

        try await Task.sleep(nanoseconds: 100_000_000)

        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Dicticus/DebugRecordings", isDirectory: true)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        let fileURL = dir.appendingPathComponent("cleanup-\(f.string(from: Date())).jsonl")

        let lines = try String(contentsOf: fileURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        let match = lines.first { $0.contains(probe) }
        let aiLine = try XCTUnwrap(match,
            "expected aiCleanup-mode record containing '\(probe)' in \(fileURL.path)")
        XCTAssertTrue(aiLine.contains("\"mode\":\"aiCleanup\""),
            "Phase 25-02 no-regression: aiCleanup record must carry mode=aiCleanup — got: \(aiLine)")
    }

    // MARK: - Phase 25.1-01: telemetry parity (lang_used + emission_counter)
    //
    // Closes the 25-04 SUMMARY's two telemetry gaps:
    //   Gap 1 (lang_used null in 100% of records) — was a schema-name mismatch;
    //          this test asserts the new alias is populated whenever `lang` is.
    //   Gap 2 (plain-mode emission near-zero, ambiguous cause) — this test asserts
    //          two sequential invocations produce records with counter delta == 1,
    //          which means future capture windows can prove dual-emission fires by
    //          checking counter monotonicity across all records in a file.
    //
    // Pattern follows Phase 25-02 (UUID probe + today's-JSONL scan).

    func testPhase251_LangUsedMirrorsLang() async throws {
        let probe = "phase251-lang-probe-\(UUID().uuidString.prefix(8))"
        let svc = TextProcessingService(cleanupService: nil, historyService: testHistory)

        _ = await svc.process(text: probe, language: "de", mode: .plain, confidence: 1.0)

        try await Task.sleep(nanoseconds: 150_000_000)  // 150ms — DebugRecorder actor flush

        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Dicticus/DebugRecordings", isDirectory: true)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        let fileURL = dir.appendingPathComponent("cleanup-\(f.string(from: Date())).jsonl")

        let lines = try String(contentsOf: fileURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        let match = lines.first { $0.contains(probe) }
        let line = try XCTUnwrap(match, "Probe record missing from today's JSONL at \(fileURL.path)")
        guard let data = line.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return XCTFail("Failed to parse probe JSONL line as JSON")
        }
        XCTAssertEqual(obj["lang"] as? String, "de",
            "Phase 25.1-01: lang field must equal the language passed to process()")
        XCTAssertEqual(obj["lang_used"] as? String, "de",
            "Phase 25.1-01: lang_used must mirror lang (closes 25-04 §Gap 1)")
    }

    func testPhase251_EmissionCounterMonotonicAcrossModes() async throws {
        let probeA = "phase251-emit-plain-\(UUID().uuidString.prefix(8))"
        let probeB = "phase251-emit-ai-\(UUID().uuidString.prefix(8))"
        let mock = MockCleanupProvider()
        mock.returnValue = "ai output \(probeB)"
        let svc = TextProcessingService(cleanupService: mock, historyService: testHistory)

        _ = await svc.process(text: probeA, language: "en", mode: .plain, confidence: 1.0)
        _ = await svc.process(text: probeB, language: "en", mode: .aiCleanup, confidence: 1.0)

        try await Task.sleep(nanoseconds: 200_000_000)  // 200ms — both actor flushes

        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Dicticus/DebugRecordings", isDirectory: true)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        let fileURL = dir.appendingPathComponent("cleanup-\(f.string(from: Date())).jsonl")

        let lines = try String(contentsOf: fileURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        let lineA = lines.first { $0.contains(probeA) }
        let lineB = lines.first { $0.contains(probeB) }
        let a = try XCTUnwrap(lineA, "Plain-mode probe record missing from JSONL")
        let b = try XCTUnwrap(lineB, "AI-mode probe record missing from JSONL")
        guard let dataA = a.data(using: .utf8), let dataB = b.data(using: .utf8),
              let oa = (try? JSONSerialization.jsonObject(with: dataA)) as? [String: Any],
              let ob = (try? JSONSerialization.jsonObject(with: dataB)) as? [String: Any] else {
            return XCTFail("Failed to parse probe JSONL lines as JSON")
        }
        guard let ca = oa["emission_counter"] as? Int, let cb = ob["emission_counter"] as? Int else {
            return XCTFail("emission_counter missing or wrong type in one or both records (closes 25-04 §Gap 2)")
        }
        XCTAssertEqual(cb - ca, 1,
            "Phase 25.1-01: two sequential process() invocations must produce emission_counter delta == 1 (closes 25-04 §Gap 2)")
    }
    #endif
}

#if DEBUG_RECORDER
/// Phase 27-02: end-to-end integration test proving that an exact-match
/// dictionary replacement during a real pipeline run propagates into the
/// emitted DebugCleanupRecord's `dictionary_replacements` field. Closes
/// the OBS-DICT-01 wiring contract.
///
/// Asserts via DebugRecorder.shared.lastRecordForTests (test-only actor
/// accessor populated from record(_:)) so the test does not depend on
/// JSONL file I/O.
///
/// Cross-platform parity (feedback_cleanup_cross_platform_parity): byte-
/// identical between macOS and iOS test targets.
@MainActor
final class TextProcessingServiceRecorderTests: XCTestCase {

    /// Isolated history so the pipeline's Step-4 save() never writes to the real
    /// App Group database (same rationale as TextProcessingServiceTests above).
    var testHistory: HistoryService!

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: DictionaryService.dictionaryKey)
        DictionaryService.shared.removeAll()
        let historyContainer = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("TPSRecorderTests-\(UUID().uuidString)", isDirectory: true)
        testHistory = HistoryService.makeForTesting(containerURLProvider: { historyContainer })
    }

    override func tearDown() {
        testHistory = nil
        super.tearDown()
    }

    func testRecorderEmitsDictionaryReplacements() async {
        // Seed a deterministic exact-match dictionary entry.
        let dict = DictionaryService.shared
        dict.removeAll()
        dict.setReplacement(for: "Dicticos", with: "Dicticus")

        // Run the pipeline (plain mode — no LLM needed).
        let service = TextProcessingService(dictionaryService: dict, cleanupService: nil, historyService: testHistory)
        _ = await service.process(text: "Dicticos is great", language: "en", mode: .plain)

        // Allow the DebugRecorder actor a tick to record(_:).
        try? await Task.sleep(nanoseconds: 150_000_000)

        let lastRecord = await DebugRecorder.shared.lastRecordForTests
        XCTAssertNotNil(lastRecord, "Phase 27-02: DebugRecorder.lastRecordForTests must be populated after process()")
        XCTAssertEqual(lastRecord?.dictionary_replacements.count, 1,
            "Phase 27-02: exactly one Replacement expected for the seeded exact-match dictionary entry")
        XCTAssertEqual(lastRecord?.dictionary_replacements[0].key, "Dicticos")
        XCTAssertEqual(lastRecord?.dictionary_replacements[0].from, "Dicticos")
        XCTAssertEqual(lastRecord?.dictionary_replacements[0].to, "Dicticus")
        XCTAssertTrue(lastRecord?.dictionary_blocked.isEmpty ?? false,
            "Phase 27-02: no BlockedMatch expected for a clean exact-match input")
    }
}
#endif
