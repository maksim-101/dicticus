import XCTest
@testable import Dicticus

/// The caret decision both the release path and the DEBUG_RECORDER trace share (Phase 51 plan 08).
final class CaretChoiceTests: XCTestCase {

    private let usable = CGRect(x: 100, y: 200, width: 2, height: 16)
    private let prev = CGRect(x: 50, y: 300, width: 8, height: 16)

    func testUsableRangeBoundsWinAndPreviousIsNeverRead() {
        var previousRead = false
        let chosen = CaretAnchor.chooseCaret(
            range: CFRange(location: 5, length: 0), rangeBounds: usable,
            previousBounds: { previousRead = true; return prev })
        XCTAssertEqual(chosen.rect, usable)
        XCTAssertEqual(chosen.source, .range)
        XCTAssertFalse(previousRead, "release path must not pay for the previous-character read")
    }

    func testUnusableRangeFallsBackToPreviousCharacterTrailingEdge() {
        let zeroHeight = CGRect(x: 0, y: 0, width: 0, height: 0)
        let chosen = CaretAnchor.chooseCaret(
            range: CFRange(location: 5, length: 0), rangeBounds: zeroHeight, previousBounds: { prev })
        XCTAssertEqual(chosen.rect, CGRect(x: 58, y: 300, width: 0, height: 16))
        XCTAssertEqual(chosen.source, .prevChar)
    }

    func testNoBoundsAtAllYieldsNone() {
        let chosen = CaretAnchor.chooseCaret(
            range: CFRange(location: 0, length: 0), rangeBounds: nil, previousBounds: { prev })
        XCTAssertNil(chosen.rect)
        XCTAssertEqual(chosen.source, .none)
    }

    func testNonEmptySelectionDoesNotUsePreviousCharacter() {
        let chosen = CaretAnchor.chooseCaret(
            range: CFRange(location: 5, length: 3), rangeBounds: nil, previousBounds: { prev })
        XCTAssertNil(chosen.rect)
        XCTAssertEqual(chosen.source, .none)
    }
}
