import XCTest
@testable import Dicticus

/// Phase 44 Plan 11: end-to-end pipeline tests for the edit-level fidelity
/// guard's WIRING and ORDERING at `TextProcessingService` Step 3a.
///
/// These are pipeline-level, not unit-level: they exercise
/// `TextProcessingService`'s real Step 3 -> 3b chain (including
/// `NumberRevert` and `applyFinalCapitalization`), with the LLM call stubbed
/// via `PipelineMockCleanupProvider`. `EditGuard`'s own classify/rebuild
/// logic is already unit-tested by `EditGuardTests.swift` (44-10) against
/// all 73 fixtures — this file's job is proving the WIRING (reasoning-leak
/// discard -> prefilterLLMOutput -> EditGuard.apply -> NumberRevert, in that
/// pinned order) and the D-11 forensics, which unit tests cannot.
///
/// Cross-platform parity (feedback_cleanup_cross_platform_parity): byte-
/// identical with iOS/DicticusTests/EditGuardPipelineTests.swift.
@MainActor
final class EditGuardPipelineTests: XCTestCase {

    /// Minimal mock conforming to `CleanupProvider`, mirroring
    /// `TextProcessingServiceTests.MockCleanupProvider` — that mock is
    /// private to the macOS/iOS-specific test target, so this file (which
    /// lives in `Shared/DicticusTests`, compiled into both) declares its own.
    ///
    /// `echo == true` makes `cleanup(text:...)` return its own `text`
    /// argument unchanged — used to compute what `rulesCleanedText` (the
    /// Step 2c snapshot) resolves to for a given raw input, WITHOUT reaching
    /// into `DebugRecorder` internals: candidate == baseline means the guard
    /// sees zero diff edits and rebuilds to the baseline exactly, so
    /// `process(...)` with `echo == true` IS the rules-cleaned baseline.
    final class PipelineMockCleanupProvider: CleanupProvider {
        var isLoaded: Bool = true
        var returnValue: String = ""
        var echo: Bool = false
        private(set) var lastContext: DictationContext = .default

        func cleanup(text: String, language: String, dictionaryContext: [String: String]?, context: DictationContext = .default) async -> String {
            lastContext = context
            return echo ? text : returnValue
        }
    }

    var dictionaryService: DictionaryService!
    /// Isolated history so Step 4's save() never writes to the real App
    /// Group database (same rationale as TextProcessingServiceTests).
    var testHistory: HistoryService!
    /// The user's real `useSwissGerman` preference (default ON per
    /// `feedback_swiss_german_default`), saved/restored around each test so
    /// Step 3b's Swiss number reformatting (comma/period thousands
    /// separator) never contaminates these tests' digit-VALUE assertions —
    /// this file forces the toggle OFF for the duration of the test.
    var savedUseSwissGerman: Bool = false

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: DictionaryService.dictionaryKey)
        dictionaryService = DictionaryService.shared
        dictionaryService.removeAll()
        let historyContainer = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("EGPTests-\(UUID().uuidString)", isDirectory: true)
        testHistory = HistoryService.makeForTesting(containerURLProvider: { historyContainer })
        savedUseSwissGerman = DicticusDefaults.suite.bool(forKey: "useSwissGerman")
        DicticusDefaults.suite.set(false, forKey: "useSwissGerman")
    }

    override func tearDown() {
        DicticusDefaults.suite.set(savedUseSwissGerman, forKey: "useSwissGerman")
        testHistory = nil
        super.tearDown()
    }

    /// Computes what `TextProcessingService`'s Step 2c snapshot
    /// (`rulesCleanedText`) resolves to for `text`/`language`, by running the
    /// real pipeline with an echoing LLM stub (see `PipelineMockCleanupProvider`).
    private func rulesCleanedBaseline(for text: String, language: String) async -> String {
        let passthrough = PipelineMockCleanupProvider()
        passthrough.echo = true
        let svc = TextProcessingService(
            dictionaryService: dictionaryService, cleanupService: passthrough, historyService: testHistory
        )
        return await svc.process(text: text, language: language, mode: .aiCleanup)
    }

    // MARK: - testStep3aOrdering

    /// The guard runs AFTER `prefilterLLMOutput` and BEFORE `NumberRevert`.
    /// `10` -> `zehn`: the guard ACCEPTS the form change (`numberFormChange`,
    /// same numeric VALUE) and `NumberRevert` then reverts the FORM back to
    /// `10`. Final output is `10`.
    ///
    /// SCRATCH-VERIFIED (per this task's acceptance criteria): temporarily
    /// deleted the Step 3a.5 `NumberRevert.apply` call in
    /// `TextProcessingService.swift` (leaving the guard's own accepted
    /// `numberFormChange` output as final) and re-ran this test. Real
    /// captured output:
    ///   `XCTAssertTrue failed - final output "Ich habe zehn Punkte." must
    ///   contain the digit form "10"`
    ///   `XCTAssertFalse failed - final output "Ich habe zehn Punkte." must
    ///   NOT contain the word form "zehn" — NumberRevert must have reverted it`
    /// i.e. with the guard alone (no Step 3a.5 downstream), an accepted
    /// same-value form change is legitimate guard output but is never
    /// normalized back to digit form — "zehn" survives unchanged all the way
    /// to the pasteboard, exactly the double-layer failure D-03's ownership
    /// split (guard = VALUE, NumberRevert = FORM) exists to prevent. The
    /// deleted call was restored immediately after capturing this failure;
    /// see 44-11-SUMMARY.md for the full experiment log.
    func testStep3aOrdering() async {
        let mock = PipelineMockCleanupProvider()
        mock.returnValue = "Ich habe zehn Punkte."
        let service = TextProcessingService(
            dictionaryService: dictionaryService, cleanupService: mock, historyService: testHistory
        )

        let output = await service.process(text: "Ich habe 10 Punkte", language: "de", mode: .aiCleanup)

        XCTAssertTrue(output.contains("10"), "final output \"\(output)\" must contain the digit form \"10\"")
        XCTAssertFalse(output.localizedCaseInsensitiveContains("zehn"),
            "final output \"\(output)\" must NOT contain the word form \"zehn\" — NumberRevert must have reverted it")
    }

    // MARK: - testDigitValueChangeNeverReachesOutput

    /// `10,011 ms` -> `10,111 ms`: a VALUE change (not a form change) must
    /// never reach the output. This is the falsified-measurement regression
    /// (D-03) — the pre-Phase-44 gate's `tokenizeForDialectGate` split
    /// `"10,011"` into `["10","011"]`, both under the 4-char floor, making
    /// digit corruption structurally invisible to it.
    func testDigitValueChangeNeverReachesOutput() async {
        let mock = PipelineMockCleanupProvider()
        mock.returnValue = "The latency was 10,111 milliseconds under load."
        let service = TextProcessingService(
            dictionaryService: dictionaryService, cleanupService: mock, historyService: testHistory
        )

        let output = await service.process(
            text: "The latency was 10,011 milliseconds under load.", language: "en", mode: .aiCleanup
        )

        XCTAssertTrue(output.contains("10,011"), "final output \"\(output)\" must contain the true value 10,011")
        XCTAssertFalse(output.contains("10,111"), "final output \"\(output)\" must NOT contain the corrupted value 10,111")
    }

    // MARK: - testReasoningLeakDiscardsWholeOutput

    /// An LLM output carrying a bare, unclosed `<think>` block must never
    /// reach the paste — `stripReasoningBlock`'s `leaked == true` fail-closed
    /// path discards the WHOLE output and Step 3a falls back to the
    /// rules-cleaned baseline, verified here at the pipeline level (not just
    /// `CleanupService.cleanup()`'s own internal strip).
    func testReasoningLeakDiscardsWholeOutput() async {
        let rawText = "Hallo Welt, das funktioniert."
        let expectedBaseline = await rulesCleanedBaseline(for: rawText, language: "de")

        let mock = PipelineMockCleanupProvider()
        mock.returnValue = "<think>let me reconsider how to phrase this"  // bare, never closed
        let service = TextProcessingService(
            dictionaryService: dictionaryService, cleanupService: mock, historyService: testHistory
        )
        let output = await service.process(text: rawText, language: "de", mode: .aiCleanup)

        XCTAssertEqual(output, expectedBaseline,
            "a <think> preamble that survives stripReasoningBlock must discard the whole output and fall back to the rules-cleaned baseline")

        #if DEBUG_RECORDER
        try? await Task.sleep(nanoseconds: 150_000_000)
        let record = await DebugRecorder.shared.lastRecordForTests
        XCTAssertEqual(record?.steps.post_gate?.fail_closed_reason, "reasoningLeak",
            "GateEntry.fail_closed_reason must record \"reasoningLeak\"")
        #endif
    }

    // MARK: - testInjectionReplyDiscardsWholeOutput

    /// The 2026-07-05 chatbot-reply record shape: a dictated German
    /// imperative ("give me more hashtags") answered by the LLM in
    /// assistant voice instead of edited. `prefilterLLMOutput`'s
    /// imperative-input/assistant-voice-output pairing (D-05/D-07) must
    /// discard the WHOLE reply, before the edit guard ever classifies a
    /// single token.
    func testInjectionReplyDiscardsWholeOutput() async {
        let rawText = "Gib mir noch ein paar Hashtags."
        let expectedBaseline = await rulesCleanedBaseline(for: rawText, language: "de")

        let mock = PipelineMockCleanupProvider()
        mock.returnValue = "Ich verstehe, dass du weitere Hashtags brauchst. Bitte gib mir mehr Kontext dazu."
        let service = TextProcessingService(
            dictionaryService: dictionaryService, cleanupService: mock, historyService: testHistory
        )
        let output = await service.process(text: rawText, language: "de", mode: .aiCleanup)

        XCTAssertEqual(output, expectedBaseline,
            "an imperative-input/assistant-voice-output injection reply must discard the whole output and fall back to the rules-cleaned baseline")

        #if DEBUG_RECORDER
        try? await Task.sleep(nanoseconds: 150_000_000)
        let record = await DebugRecorder.shared.lastRecordForTests
        XCTAssertEqual(record?.steps.post_gate?.fail_closed_reason, "prefilter",
            "GateEntry.fail_closed_reason must record \"prefilter\"")
        #endif
    }

    // MARK: - testGermanWordOrderRepairSurvivesTheWholePipeline

    /// The phase's core value proposition, asserted at the pipeline level:
    /// a broken V2-in-a-weil-clause repaired to correct German verb-final
    /// word order must reach the end of Step 3b intact. This exact shape is
    /// `gate=rejected` in production today (pre-Phase-44 gate stack).
    func testGermanWordOrderRepairSurvivesTheWholePipeline() async {
        let mock = PipelineMockCleanupProvider()
        mock.returnValue = "Weil die Fragen ja gleich sofort ausgewertet werden."
        let service = TextProcessingService(
            dictionaryService: dictionaryService, cleanupService: mock, historyService: testHistory
        )

        let output = await service.process(
            text: "Weil die Fragen werden ja gleich sofort ausgewertet.", language: "de", mode: .aiCleanup
        )

        XCTAssertTrue(output.contains("ausgewertet werden"),
            "the German verb-final word-order repair must reach the end of the pipeline intact — got: \(output)")
    }

    // MARK: - testGateEntryCarriesClassifiedEdits

    #if DEBUG_RECORDER
    /// Under DEBUG_RECORDER, a record with at least one accepted and one
    /// rejected edit produces a `GateEntry` whose `edits` array carries both,
    /// with correct `accept_class`/`reject_class`, and whose
    /// `accepted_by_class`/`rejected_by_class` histograms sum consistently
    /// with the classified edits. This is D-11's forensics contract — the
    /// data 44-12's replay and 44-13's surviving-yield-by-class scoring
    /// depend on.
    func testGateEntryCarriesClassifiedEdits() async {
        let rawText = "Ich habe 10 Punkte und du wohnst dort."
        let mock = PipelineMockCleanupProvider()
        // "10" -> "zehn": same-value form change, ACCEPT (numberFormChange).
        // "du" -> "ich": pronoun person change, REJECT (pronounPersonChange).
        mock.returnValue = "Ich habe zehn Punkte und ich wohne dort."
        let service = TextProcessingService(
            dictionaryService: dictionaryService, cleanupService: mock, historyService: testHistory
        )
        _ = await service.process(text: rawText, language: "de", mode: .aiCleanup)

        try? await Task.sleep(nanoseconds: 150_000_000)
        let record = await DebugRecorder.shared.lastRecordForTests
        guard let gateEntry = record?.steps.post_gate else {
            return XCTFail("expected a post_gate GateEntry")
        }
        guard let edits = gateEntry.edits else {
            return XCTFail("expected GateEntry.edits to be populated")
        }

        XCTAssertTrue(edits.contains { $0.accepted && $0.accept_class == "numberFormChange" },
            "expected an accepted numberFormChange edit (10 -> zehn) — got: \(edits)")
        XCTAssertTrue(edits.contains { !$0.accepted && $0.reject_class == "pronounPersonChange" },
            "expected a rejected pronounPersonChange edit (du -> ich) — got: \(edits)")

        let acceptedByClass = gateEntry.accepted_by_class ?? [:]
        let rejectedByClass = gateEntry.rejected_by_class ?? [:]
        let acceptedClassifiedCount = edits.filter { $0.accepted && $0.accept_class != nil }.count
        let rejectedClassifiedCount = edits.filter { !$0.accepted && $0.reject_class != nil }.count
        XCTAssertEqual(acceptedByClass.values.reduce(0, +), acceptedClassifiedCount,
            "accepted_by_class must sum to the number of accepted, classified edits")
        XCTAssertEqual(rejectedByClass.values.reduce(0, +), rejectedClassifiedCount,
            "rejected_by_class must sum to the number of rejected, classified edits")
        XCTAssertEqual(acceptedByClass["numberFormChange"], 1)
        XCTAssertGreaterThanOrEqual(rejectedByClass["pronounPersonChange"] ?? 0, 1)
    }

    // MARK: - testHistoricalGateEntriesStillDecode

    /// >= 50 real records from the 44-01 corpus snapshot decode through the
    /// Plan-11-extended `GateEntry` with zero failures — proves the new
    /// `edits`/`fail_closed_reason`/`accepted_by_class`/`rejected_by_class`
    /// fields are genuinely backward-compatible (Optional, not merely
    /// declared so) against JSONL written before they existed.
    func testHistoricalGateEntriesStillDecode() throws {
        let corpusURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // DicticusTests
            .deletingLastPathComponent() // Shared
            .deletingLastPathComponent() // repo root
            .appendingPathComponent(".planning/phases/44-cleanup-fidelity-guard/corpus-snapshot/cleanup-2026-07-11.jsonl")

        let contents = try String(contentsOf: corpusURL, encoding: .utf8)
        let lines = contents.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        XCTAssertGreaterThanOrEqual(lines.count, 50,
            "corpus snapshot at \(corpusURL.path) must carry >= 50 records to satisfy this test's own acceptance bar")

        let decoder = JSONDecoder()
        var decodeFailures: [(Int, Error)] = []
        for (i, line) in lines.enumerated() {
            guard let data = line.data(using: .utf8) else {
                decodeFailures.append((i, NSError(domain: "test", code: 0)))
                continue
            }
            do {
                _ = try decoder.decode(DebugCleanupRecord.self, from: data)
            } catch {
                decodeFailures.append((i, error))
            }
        }

        XCTAssertTrue(decodeFailures.isEmpty,
            "expected zero decode failures across \(lines.count) historical records — got \(decodeFailures.count): " +
            decodeFailures.prefix(3).map { "line \($0.0): \($0.1)" }.joined(separator: "; "))
    }
    #endif
}
