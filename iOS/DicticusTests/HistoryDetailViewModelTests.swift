import XCTest
@testable import Dicticus

/// Phase 20.05 ACT-3-VISIBILITY — HistoryDetailView variant-switching logic.
///
/// XCUITest-style behaviour assertions are deferred to the dedicated UI test
/// target (`DicticusUITests/HistoryDetailViewTests.swift`). These unit tests
/// cover the deterministic computation that drives `HistoryDetailView` — the
/// `displayedText(for:in:)` helper that swaps between raw/polished and falls
/// back to polished for legacy entries (pre-D-38) where `rawText` is empty.
///
/// Keeping this logic in a pure helper makes it directly testable without
/// hosting a SwiftUI view in XCTest.
final class HistoryDetailViewModelTests: XCTestCase {

    private func makeEntry(text: String, rawText: String) -> TranscriptionEntry {
        TranscriptionEntry(
            uuid: UUID(),
            text: text,
            rawText: rawText,
            language: "de",
            mode: "cleanup",
            createdAt: Date(),
            confidence: 0.95
        )
    }

    func testRawSegmentShowsRawText() {
        let entry = makeEntry(text: "Polished output.", rawText: "raw output")
        XCTAssertEqual(HistoryDetailView.displayedText(for: .raw, in: entry), "raw output")
    }

    func testPolishedSegmentShowsPolishedText() {
        let entry = makeEntry(text: "Polished output.", rawText: "raw output")
        XCTAssertEqual(HistoryDetailView.displayedText(for: .polished, in: entry), "Polished output.")
    }

    func testRawFallsBackToPolishedWhenRawEmpty() {
        // Legacy entries (pre-D-38 / Phase 19 history) had no rawText column;
        // the migration set rawText = "" for old rows. Show polished rather
        // than a blank screen.
        let entry = makeEntry(text: "Polished only.", rawText: "")
        XCTAssertEqual(HistoryDetailView.displayedText(for: .raw, in: entry), "Polished only.")
    }

    func testTranscriptionEntryHashableForNavigationStackRouting() {
        // NavigationStack value-based routing requires Hashable.
        // Two entries with the same id (and identical contents) hash equal.
        let id = UUID()
        let a = TranscriptionEntry(uuid: id, text: "x", rawText: "x", language: "en",
                                   mode: "plain", createdAt: Date(timeIntervalSince1970: 0), confidence: 1)
        let b = TranscriptionEntry(uuid: id, text: "x", rawText: "x", language: "en",
                                   mode: "plain", createdAt: Date(timeIntervalSince1970: 0), confidence: 1)
        var set: Set<TranscriptionEntry> = []
        set.insert(a)
        set.insert(b)
        // Synthesised conformance hashes on all stored properties — identical structs collapse.
        XCTAssertEqual(set.count, 1, "Identical entries must collapse in a Set (Hashable conformance)")
    }
}
