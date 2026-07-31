import XCTest
import KeyboardShortcuts
@testable import Dicticus

/// R-06 decision-logic tests for the revert-to-raw safety valve.
///
/// Covers only the pure `RevertToRawState.evaluate()` seam + the hotkey's
/// nil-default binding. The CGEvent paste itself is Accessibility-gated and
/// is verified on-device in Plan 11 UAT, not here.
@MainActor
final class RevertToRawTests: XCTestCase {

    private func makeEntry(text: String, rawText: String) -> TranscriptionEntry {
        TranscriptionEntry(
            text: text,
            rawText: rawText,
            language: "en",
            mode: "ai",
            confidence: 1.0
        )
    }

    func testEvaluateNoHistory() {
        let decision = RevertToRawState.evaluate(entry: nil)
        XCTAssertFalse(decision.enabled)
        XCTAssertEqual(decision.help, "No dictation yet to revert.")
    }

    func testEvaluateRawEqualsText() {
        let entry = makeEntry(text: "Hello world.", rawText: "Hello world.")
        let decision = RevertToRawState.evaluate(entry: entry)
        XCTAssertFalse(decision.enabled)
        XCTAssertEqual(decision.help, "Nothing to revert — raw and cleaned text match.")
    }

    func testEvaluateRawDiffersFromText() {
        let entry = makeEntry(text: "Hello, world.", rawText: "hello world")
        let decision = RevertToRawState.evaluate(entry: entry)
        XCTAssertTrue(decision.enabled)
    }

    func testRevertToRawHotkeyHasNoDefaultBinding() {
        XCTAssertNil(KeyboardShortcuts.getShortcut(for: .revertToRaw))
    }
}
