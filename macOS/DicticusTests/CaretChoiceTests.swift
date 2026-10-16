import XCTest
@testable import Dicticus

/// The caret decision both the release path and the DEBUG_RECORDER trace share (Phase 51 plan 08).
final class CaretChoiceTests: XCTestCase {

    private let usable = CGRect(x: 100, y: 200, width: 2, height: 16)
    private let prev = CGRect(x: 50, y: 300, width: 8, height: 16)

    func testUsableRangeBoundsWinAndPreviousIsNeverRead() {
        var previousRead = false
        var lineRead = false
        let chosen = CaretAnchor.chooseCaret(
            range: CFRange(location: 5, length: 0), rangeBounds: usable,
            previousBounds: { previousRead = true; return prev }, lineStart: { lineRead = true; return 5 })
        XCTAssertEqual(chosen.rect, usable)
        XCTAssertEqual(chosen.source, .range)
        XCTAssertFalse(previousRead, "release path must not pay for the previous-character read")
        XCTAssertFalse(lineRead, "release path must not pay for the line reads")
    }

    func testUnusableRangeFallsBackToPreviousCharacterTrailingEdge() {
        let zeroHeight = CGRect(x: 0, y: 0, width: 0, height: 0)
        let chosen = CaretAnchor.chooseCaret(
            range: CFRange(location: 5, length: 0), rangeBounds: zeroHeight, previousBounds: { prev }, lineStart: { 2 })
        XCTAssertEqual(chosen.rect, CGRect(x: 58, y: 300, width: 0, height: 16))
        XCTAssertEqual(chosen.source, .prevChar)
    }

    func testNoBoundsAtAllYieldsNone() {
        let chosen = CaretAnchor.chooseCaret(
            range: CFRange(location: 0, length: 0), rangeBounds: nil, previousBounds: { prev }, lineStart: { 0 })
        XCTAssertNil(chosen.rect)
        XCTAssertEqual(chosen.source, .none)
    }

    func testNonEmptySelectionDoesNotUsePreviousCharacter() {
        let chosen = CaretAnchor.chooseCaret(
            range: CFRange(location: 5, length: 3), rangeBounds: nil, previousBounds: { prev }, lineStart: { 5 })
        XCTAssertNil(chosen.rect)
        XCTAssertEqual(chosen.source, .none)
    }

    // Review round 3, IN-05: at the start of a line the previous character is the break of the line above.
    func testInsertionPointAtTheStartOfALineHasNoCaretInsteadOfTheLineAbove() {
        let chosen = CaretAnchor.chooseCaret(
            range: CFRange(location: 12, length: 0), rangeBounds: nil, previousBounds: { prev }, lineStart: { 12 })
        XCTAssertNil(chosen.rect, "anchored on the previous line's break")
        XCTAssertEqual(chosen.source, .none)
    }

    func testPreviousCharacterOnTheSameLineStillAnchorsTheCaret() {
        let chosen = CaretAnchor.chooseCaret(
            range: CFRange(location: 12, length: 0), rangeBounds: nil, previousBounds: { prev }, lineStart: { 4 })
        XCTAssertEqual(chosen.rect, CGRect(x: 58, y: 300, width: 0, height: 16))
        XCTAssertEqual(chosen.source, .prevChar)
    }

    func testAnAppWithoutLineAttributesKeepsThePreviousCharacterFallback() {
        let chosen = CaretAnchor.chooseCaret(
            range: CFRange(location: 12, length: 0), rangeBounds: nil, previousBounds: { prev }, lineStart: { nil })
        XCTAssertEqual(chosen.source, .prevChar)
    }
}
