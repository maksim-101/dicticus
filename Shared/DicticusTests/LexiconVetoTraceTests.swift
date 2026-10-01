import XCTest
@testable import Dicticus

/// Quick task 260930-s1e (audit 2026-09-30 A §5): Guard A's real-word veto used to
/// leave no trace, so a suppressed near-match vanished from the debug log. It is now
/// reported in `applyWithTrace(...).vetoed` and, in recorder builds, `lexicon_vetoed`.
/// `blocked` keeps its ratio-cap-only meaning.
@MainActor
final class LexiconVetoTraceTests: XCTestCase {

    var dictionaryService: DictionaryService!
    var testHistory: HistoryService!

    override func setUp() {
        super.setUp()
        dictionaryService = DictionaryService.shared
        dictionaryService.removeAll()
        let historyContainer = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("LVTTests-\(UUID().uuidString)", isDirectory: true)
        testHistory = HistoryService.makeForTesting(containerURLProvider: { historyContainer })
    }

    override func tearDown() {
        dictionaryService.removeAll()
        dictionaryService = nil
        testHistory = nil
        super.tearDown()
    }

    private func makeDict(_ pairs: [(String, String)]) {
        for (key, replacement) in pairs {
            dictionaryService.setReplacement(for: key, with: replacement)
        }
    }

    func testSafeguardVetoIsTraced() {
        makeDict([("SalGuard", "Cellguard")])
        let input = "I checked this safeguard today."
        let trace = dictionaryService.applyWithTrace(to: input)
        XCTAssertEqual(trace.text, input)
        XCTAssertEqual(trace.replacements.count, 0)
        XCTAssertEqual(trace.blocked.count, 0)
        XCTAssertEqual(trace.vetoed.count, 1)
        XCTAssertEqual(trace.vetoed.first?.key, "SalGuard")
        XCTAssertEqual(trace.vetoed.first?.from, "safeguard")
        XCTAssertEqual(trace.vetoed.first?.to, "Cellguard")
        XCTAssertEqual(trace.vetoed.first?.ratio ?? -1, 2.0 / 9.0, accuracy: 0.001)
    }

    func testTackleVetoTracedAboveRatioCap() {
        makeDict([("Tavile", "Tavily")])
        let input = "We need to tackle this problem."
        let trace = dictionaryService.applyWithTrace(to: input)
        XCTAssertEqual(trace.text, input)
        XCTAssertEqual(trace.blocked.count, 0)
        XCTAssertEqual(trace.vetoed.count, 1)
        XCTAssertEqual(trace.vetoed.first?.key, "Tavile")
        XCTAssertEqual(trace.vetoed.first?.from, "tackle")
        XCTAssertEqual(trace.vetoed.first?.to, "Tavily")
        XCTAssertEqual(trace.vetoed.first?.ratio ?? -1, 2.0 / 6.0, accuracy: 0.001)
    }

    func testGermanParkettVetoTracedAtCapBoundary() {
        makeDict([("Parakeet", "Parakeet")])
        let input = "Das Parkett im Wohnzimmer ist neu."
        let trace = dictionaryService.applyWithTrace(to: input)
        XCTAssertEqual(trace.text, input)
        XCTAssertEqual(trace.vetoed.count, 1)
        XCTAssertEqual(trace.vetoed.first?.key, "Parakeet")
        XCTAssertEqual(trace.vetoed.first?.from, "Parkett")
        XCTAssertEqual(trace.vetoed.first?.to, "Parakeet")
        XCTAssertEqual(trace.vetoed.first?.ratio ?? -1, 0.25, accuracy: 0.001)
    }

    func testNoEntryWithoutNearMatch() {
        makeDict([("SalGuard", "Cellguard")])
        XCTAssertEqual(dictionaryService.applyWithTrace(to: "The weather forecast looks reasonable tomorrow.").vetoed.count, 0)

        dictionaryService.removeAll()
        makeDict([("Signal", "Signal")])
        XCTAssertEqual(dictionaryService.applyWithTrace(to: "Open the Signal app.").vetoed.count, 0)
    }

    func testSafeguardVetoReachesDebugRecord() async {
        makeDict([("SalGuard", "Cellguard")])
        let matcher = BrandMatcher(canonicals: [], enLexicon: [], deLexicon: [])
        let service = TextProcessingService(
            dictionaryService: dictionaryService,
            cleanupService: nil,
            historyService: testHistory,
            brandMatcher: matcher
        )
        matcher.liveDictionaryCanonicalProvider = nil

        let input = "I checked this safeguard today."
        let output = await service.process(text: input, language: "en", mode: .plain)
        XCTAssertEqual(output, input)

        #if DEBUG_RECORDER
        try? await Task.sleep(nanoseconds: 150_000_000)
        let record = await DebugRecorder.shared.lastRecordForTests
        XCTAssertEqual(record?.lexicon_vetoed?.count, 1)
        XCTAssertEqual(record?.lexicon_vetoed?.first?.key, "SalGuard")
        XCTAssertEqual(record?.lexicon_vetoed?.first?.from, "safeguard")
        XCTAssertEqual(record?.lexicon_vetoed?.first?.to, "Cellguard")
        XCTAssertEqual(record?.lexicon_vetoed?.first?.ratio ?? -1, 0.222, accuracy: 0.001)
        #endif
    }
}

#if DEBUG_RECORDER
/// Record-schema contract for `lexicon_vetoed`. Never calls process() or
/// DebugRecorder.record(), so it cannot write to the DebugRecordings corpus.
@MainActor
final class LexiconVetoRecordCodableTests: XCTestCase {

    private func makeRecord(lexiconVetoed: [DebugCleanupRecord.DictionaryBlockedEntry]?, passArgument: Bool) -> DebugCleanupRecord {
        let steps = DebugCleanupRecord.Steps(
            raw: DebugCleanupRecord.StepEntry(text: "", ms: 0),
            post_dict: DebugCleanupRecord.StepEntry(text: "", ms: 0),
            post_itn: DebugCleanupRecord.StepEntry(text: "", ms: 0),
            post_swiss: DebugCleanupRecord.StepEntry(text: "", ms: 0),
            post_rules: DebugCleanupRecord.StepEntry(text: "", ms: 0),
            llm_prompt: nil,
            llm_raw: nil,
            post_gate: nil,
            post_swiss_num: DebugCleanupRecord.StepEntry(text: "", ms: 0)
        )
        let model = DebugCleanupRecord.ModelInfo(name: "test", sha256_prefix: nil)
        let sampler = DebugCleanupRecord.SamplerInfo(temp: 0.1, top_k: 1, top_p: 1.0, max_tokens: 1, seed: nil)
        let anomaly = DebugCleanupRecord.Anomaly(degenerate_collapse: false, very_short_output: false)
        if !passArgument {
            return DebugCleanupRecord(
                ts: "2026-09-30T12:00:00.000Z", session_id: "s", lang: "en", lang_used: "en", mode: "plain",
                model: model, sampler: sampler, steps: steps,
                dictionary_context_keys: [], dictionary_replacements: [], dictionary_blocked: [],
                anomaly: anomaly, emission_counter: 0
            )
        }
        return DebugCleanupRecord(
            ts: "2026-09-30T12:00:00.000Z", session_id: "s", lang: "en", lang_used: "en", mode: "plain",
            model: model, sampler: sampler, steps: steps,
            dictionary_context_keys: [], dictionary_replacements: [], dictionary_blocked: [],
            anomaly: anomaly, emission_counter: 0,
            lexicon_vetoed: lexiconVetoed
        )
    }

    func testRecordBuiltWithoutArgumentDecodesToNil() throws {
        let data = try JSONEncoder().encode(makeRecord(lexiconVetoed: nil, passArgument: false))
        XCTAssertNil(try JSONDecoder().decode(DebugCleanupRecord.self, from: data).lexicon_vetoed)
    }

    func testEmptyArrayEncodesAsLiteral() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(makeRecord(lexiconVetoed: [], passArgument: true))
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"lexicon_vetoed\":[]"), "got: \(json)")
    }

    func testEntryRoundTrips() throws {
        let entry = DebugCleanupRecord.DictionaryBlockedEntry(key: "SalGuard", from: "safeguard", to: "Cellguard", ratio: 0.222)
        let data = try JSONEncoder().encode(makeRecord(lexiconVetoed: [entry], passArgument: true))
        let back = try JSONDecoder().decode(DebugCleanupRecord.self, from: data)
        XCTAssertEqual(back.lexicon_vetoed?.count, 1)
        XCTAssertEqual(back.lexicon_vetoed?.first?.key, "SalGuard")
        XCTAssertEqual(back.lexicon_vetoed?.first?.from, "safeguard")
        XCTAssertEqual(back.lexicon_vetoed?.first?.to, "Cellguard")
        XCTAssertEqual(back.lexicon_vetoed?.first?.ratio ?? -1, 0.222, accuracy: 0.001)
    }

    func testLegacyJSONWithoutKeyDecodesToNil() throws {
        let json = """
        {
          "ts": "2026-05-20T12:00:00.000Z",
          "session_id": "legacy-session",
          "lang": "en",
          "lang_used": "en",
          "mode": "plain",
          "model": { "name": "test", "sha256_prefix": null },
          "sampler": { "temp": 0.1, "top_k": 1, "top_p": 1.0, "max_tokens": 1, "seed": null },
          "steps": {
            "raw": { "text": "", "ms": 0 },
            "post_dict": { "text": "", "ms": 0 },
            "post_itn": { "text": "", "ms": 0 },
            "post_swiss": { "text": "", "ms": 0 },
            "post_rules": { "text": "", "ms": 0 },
            "llm_prompt": null,
            "llm_raw": null,
            "post_gate": null,
            "post_swiss_num": { "text": "", "ms": 0 }
          },
          "dictionary_context_keys": [],
          "anomaly": { "degenerate_collapse": false, "very_short_output": false },
          "emission_counter": 0
        }
        """.data(using: .utf8)!
        XCTAssertNil(try JSONDecoder().decode(DebugCleanupRecord.self, from: json).lexicon_vetoed)
    }
}
#endif
