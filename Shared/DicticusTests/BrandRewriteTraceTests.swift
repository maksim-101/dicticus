import XCTest
@testable import Dicticus

/// Quick task 260805-qme: proves the WIRING between `BrandMatcher`'s Step 1b
/// rewrite and the debug JSONL — not the matcher in isolation
/// (`applyReportingRewrites` already has its own tests in
/// `BrandMatcherTests.swift`). Modeled directly on `EditGuardPipelineTests`
/// (same file, same directory, same idioms).
///
/// Two assertions, per the task's stated caveat:
///   - Test 1 (UNCONDITIONAL): the pipeline output contains the canonical
///     form — the firing-path guard. Without it, the DEBUG_RECORDER
///     assertion could pass vacuously over an empty rewrite list (memory
///     `feedback_gate_blind_to_firing_path`).
///   - Test 2 (`#if DEBUG_RECORDER`): `record.brand_rewrites` holds exactly
///     one entry attributing the rewrite.
///
/// Cross-platform parity (feedback_cleanup_cross_platform_parity): this file
/// lives in `Shared/DicticusTests`, compiled into both macOS and iOS test
/// targets.
@MainActor
final class BrandRewriteTraceTests: XCTestCase {

    var dictionaryService: DictionaryService!
    var testHistory: HistoryService!

    override func setUp() {
        super.setUp()
        dictionaryService = DictionaryService.shared
        dictionaryService.removeAll()
        let historyContainer = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("BRTTests-\(UUID().uuidString)", isDirectory: true)
        testHistory = HistoryService.makeForTesting(containerURLProvider: { historyContainer })
    }

    override func tearDown() {
        dictionaryService = nil
        testHistory = nil
        super.tearDown()
    }

    // MARK: - testBrandRewriteAttributedInDebugRecord

    /// "I looked at Cellcard today." → BrandMatcher's Step 1b fuzzy match
    /// rewrites the misheard "Cellcard" to the canonical "Cellguard" — the
    /// exact incident pair (2026-08-04 17:44:59 record shape). A hermetic
    /// matcher (not `.shared`) keeps the test independent of the live user
    /// dictionary and the bundled lexicon.
    func testBrandRewriteAttributedInDebugRecord() async {
        let matcher = BrandMatcher(
            canonicals: ["Cellguard"],
            enLexicon: ["i", "looked", "at", "today", "look"],
            deLexicon: []
        )
        let service = TextProcessingService(
            dictionaryService: dictionaryService,
            cleanupService: nil,
            historyService: testHistory,
            brandMatcher: matcher
        )
        // TextProcessingService.init overwrites liveDictionaryCanonicalProvider
        // with a closure reading DictionaryService.shared — nil it out AFTER
        // construction so the test stays hermetic and never depends on
        // whatever is in the developer's live dictionary.
        matcher.liveDictionaryCanonicalProvider = nil

        let output = await service.process(text: "I looked at Cellcard today.", language: "en", mode: .plain)

        // Test 1 (unconditional, every configuration): the firing-path guard.
        XCTAssertTrue(output.contains("Cellguard"),
            "expected the fuzzy brand match to fire on this fixture — got: \(output)")
        XCTAssertEqual(output, "I looked at Cellguard today.")

        #if DEBUG_RECORDER
        // Test 2: the record attributes the rewrite.
        try? await Task.sleep(nanoseconds: 150_000_000)
        let record = await DebugRecorder.shared.lastRecordForTests
        XCTAssertEqual(record?.brand_rewrites?.count, 1,
            "expected exactly one brand_rewrites entry attributing the Step 1b rewrite")
        XCTAssertEqual(record?.brand_rewrites?.first?.from, "Cellcard",
            "brand_rewrites[0].from must record the misheard surface")
        XCTAssertEqual(record?.brand_rewrites?.first?.to, "Cellguard",
            "brand_rewrites[0].to must record the canonical it was mapped to")
        #endif
    }
}
