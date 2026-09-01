import XCTest
@testable import Dicticus

/// Quick task 260901-fs1: proves `steps.finalStage` (JSON key `"final"`)
/// captures a REAL post-gate mutation (Step 3a.6 `applyFinalCapitalization`)
/// rather than duplicating `post_gate`. Fixture reproduces the incident's own
/// shape ("in. Clawed directory." vs. the logged "in. clawed directory." —
/// see `.planning/todos/pending/debug-log-missing-final-stage.md`): the LLM
/// output leaks an incomplete `<think>` block, the Step 3a edit-level guard
/// fails closed and reverts `processedText` to the un-capitalized
/// rules-cleaned baseline, and Step 3a.6 then capitalizes the sentence-
/// initial letter that follows. `post_gate` records the pre-capitalization
/// text; `finalStage` must record the post-capitalization text —
/// byte-identical to what `process()` actually returns (and the caller
/// pastes).
///
/// Modeled directly on `BrandRewriteTraceTests.swift` (same file, same
/// directory, same idioms). Two assertions per that file's stated caveat:
///   - Test 1 (UNCONDITIONAL): the pipeline output itself is capitalized —
///     the firing-path guard. Without it, the DEBUG_RECORDER assertions
///     below could pass vacuously (memory `feedback_gate_blind_to_firing_path`).
///   - Test 2 (`#if DEBUG_RECORDER`): `record.steps.finalStage` differs from
///     `record.steps.post_gate` and matches the actual return value.
///
/// Cross-platform parity (feedback_cleanup_cross_platform_parity): this file
/// lives in `Shared/DicticusTests`, compiled into both macOS and iOS test
/// targets — no per-platform duplicate needed.
@MainActor
final class DebugRecorderFinalStageTests: XCTestCase {

    var dictionaryService: DictionaryService!
    var testHistory: HistoryService!

    override func setUp() {
        super.setUp()
        dictionaryService = DictionaryService.shared
        dictionaryService.removeAll()
        let historyContainer = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("FinalStageTests-\(UUID().uuidString)", isDirectory: true)
        testHistory = HistoryService.makeForTesting(containerURLProvider: { historyContainer })
    }

    override func tearDown() {
        dictionaryService = nil
        testHistory = nil
        super.tearDown()
    }

    /// A `CleanupProvider` that always returns an incomplete `<think>` block
    /// (no closing tag) — forces `CleanupService.stripReasoningBlock` to
    /// report `leaked == true`, which fails the Step 3a edit-level guard
    /// closed: `processedText` reverts wholesale to the rules-cleaned
    /// (pre-LLM, pre-capitalization) baseline. This is the same fail-closed
    /// path a real reasoning-leak hits in production (T-44-25) — not a
    /// synthetic shortcut around the gate.
    private final class LeakingCleanupProvider: CleanupProvider {
        let isLoaded = true
        func cleanup(text: String, language: String, dictionaryContext: [String: String]?, context: DictationContext) async -> String {
            "<think>" + text
        }
    }

    func testFinalStageCapturesPostCapitalizationMutation() async {
        // Hermetic matcher (not `.shared`) — narrow canonical/lexicon list
        // keeps the fixture's "clawed"/"directory" words from being
        // fuzzy-rewritten by BrandMatcher, independent of the live
        // dictionary or bundled brand lexicon.
        let matcher = BrandMatcher(
            canonicals: ["Dicticus"],
            enLexicon: ["hello", "world", "clawed", "directory", "is", "open"],
            deLexicon: []
        )
        let service = TextProcessingService(
            dictionaryService: dictionaryService,
            cleanupService: LeakingCleanupProvider(),
            historyService: testHistory,
            brandMatcher: matcher
        )
        matcher.liveDictionaryCanonicalProvider = nil

        let output = await service.process(
            text: "hello world. clawed directory is open.",
            language: "en",
            mode: .aiCleanup
        )

        // Test 1 (unconditional, every configuration): the firing-path guard —
        // capitalization actually reached the returned/pasted text.
        XCTAssertEqual(output, "Hello world. Clawed directory is open.",
            "expected Step 3a.6 to capitalize the post-gate-reverted baseline — got: \(output)")

        #if DEBUG_RECORDER
        // Test 2: the record's `final` stage is the post-capitalization
        // text, distinct from the pre-capitalization `post_gate` text.
        try? await Task.sleep(nanoseconds: 150_000_000)
        let record = await DebugRecorder.shared.lastRecordForTests
        XCTAssertEqual(record?.steps.post_gate?.verdict, "rejected",
            "fixture must exercise the fail-closed gate-revert path (reasoningLeak)")
        XCTAssertEqual(record?.steps.post_gate?.text, "hello world. clawed directory is open.",
            "post_gate must record the PRE-capitalization gate-reverted baseline")
        XCTAssertEqual(record?.steps.finalStage?.text, "Hello world. Clawed directory is open.",
            "final must record the POST-capitalization text")
        XCTAssertNotEqual(record?.steps.finalStage?.text, record?.steps.post_gate?.text,
            "non-vacuity: final must differ from post_gate in this fixture, not duplicate it")
        XCTAssertEqual(record?.steps.finalStage?.text, output,
            "final must be byte-identical to the text process() actually returned (and the caller pastes)")
        #endif
    }
}
