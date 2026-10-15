import XCTest
import AppKit
@testable import Dicticus

final class OverlayPlacementTests: XCTestCase {

    private let panel = CGSize(width: 480, height: 120)

    private func screen(_ x: CGFloat = 0, _ y: CGFloat = 0, w: CGFloat = 1600, h: CGFloat = 1000,
                        inset: (top: CGFloat, bottom: CGFloat) = (0, 0)) -> OverlayPlacement.ScreenGeometry {
        let frame = CGRect(x: x, y: y, width: w, height: h)
        let visible = CGRect(x: x, y: y + inset.bottom, width: w, height: h - inset.top - inset.bottom)
        return .init(frame: frame, visibleFrame: visible)
    }

    // MARK: - Tracer

    func testResolveAndPlaceForOwnProcessStaysOnScreen() throws {
        let candidates = CaretAnchor.resolve(pid: getpid())
        let screens = NSScreen.screens.map {
            OverlayPlacement.ScreenGeometry(frame: $0.frame, visibleFrame: $0.visibleFrame)
        }
        let primary = try XCTUnwrap(screens.first)
        let placement = OverlayPlacement.place(
            candidates: candidates, panel: panel, screens: screens,
            primaryScreenHeight: primary.frame.height, fallback: primary
        )
        XCTAssertTrue(placement.origin.x.isFinite && placement.origin.y.isFinite)
        XCTAssertTrue(placement.visibleFrame.contains(CGRect(origin: placement.origin, size: panel)),
                      "panel \(placement.origin) escapes \(placement.visibleFrame)")
        XCTAssertTrue([.window, .screen].contains(placement.source), "unexpected source \(placement.source)")
    }

    func testCaretAboveByDefault() {
        let s = screen()
        let ax = CGRect(x: 400, y: 500, width: 2, height: 18)
        let placement = OverlayPlacement.place(
            candidates: .init(caret: ax), panel: panel, screens: [s],
            primaryScreenHeight: 1000, fallback: s
        )
        let caret = OverlayPlacement.appKitRect(fromAX: ax, primaryScreenHeight: 1000)
        XCTAssertEqual(placement.source, .caret)
        XCTAssertFalse(placement.flipped)
        XCTAssertEqual(placement.origin.y, caret.maxY + 8)
        XCTAssertEqual(placement.origin.x, caret.minX - 16)
    }
}
