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

    // MARK: - Behaviour (pure inputs)

    private func place(_ c: CaretAnchor.Candidates, screens: [OverlayPlacement.ScreenGeometry],
                       panel: CGSize? = nil, primaryHeight: CGFloat = 1000) -> OverlayPlacement.Placement {
        OverlayPlacement.place(candidates: c, panel: panel ?? self.panel, screens: screens,
                               primaryScreenHeight: primaryHeight, fallback: screens[0])
    }

    private func assertInside(_ p: OverlayPlacement.Placement, panel: CGSize? = nil,
                              file: StaticString = #filePath, line: UInt = #line) {
        let rect = CGRect(origin: p.origin, size: panel ?? self.panel)
        XCTAssertTrue(p.visibleFrame.contains(rect), "panel \(rect) escapes \(p.visibleFrame)", file: file, line: line)
    }

    func testAXRectFlipsWithPrimaryScreenHeight() {
        let r = OverlayPlacement.appKitRect(fromAX: CGRect(x: 100, y: 50, width: 2, height: 18), primaryScreenHeight: 1000)
        XCTAssertEqual(r, CGRect(x: 100, y: 932, width: 2, height: 18))
    }

    func testCaretNearTopFlipsBelow() {
        let ax = CGRect(x: 400, y: 20, width: 2, height: 18)
        let p = place(.init(caret: ax), screens: [screen()])
        let caret = OverlayPlacement.appKitRect(fromAX: ax, primaryScreenHeight: 1000)
        XCTAssertEqual(p.source, .caret)
        XCTAssertTrue(p.flipped)
        XCTAssertEqual(p.origin.y, caret.minY - 8 - panel.height)
        assertInside(p)
    }

    func testCaretAtRightEdgeClampsHorizontally() {
        let p = place(.init(caret: CGRect(x: 1590, y: 500, width: 2, height: 18)), screens: [screen()])
        XCTAssertEqual(p.origin.x, 1600 - panel.width)
        assertInside(p)
    }

    func testCaretOnLeftHandDisplayWithNegativeCoordinates() {
        let screens = [screen(), screen(-1600, 0)]
        let p = place(.init(caret: CGRect(x: -1590, y: 500, width: 2, height: 18)), screens: screens)
        XCTAssertEqual(p.source, .caret)
        XCTAssertEqual(p.origin.x, -1600)
        XCTAssertEqual(p.visibleFrame, screens[1].visibleFrame)
        assertInside(p)
    }

    func testCaretOnSecondScreenUsesThatScreensVisibleFrame() {
        let screens = [screen(), screen(1600, 0)]
        let p = place(.init(caret: CGRect(x: 2000, y: 500, width: 2, height: 18)), screens: screens)
        XCTAssertEqual(p.visibleFrame, screens[1].visibleFrame)
        assertInside(p)
    }

    func testPanelStaysOutOfMenuBarAndDockStrips() {
        let s = screen(inset: (top: 25, bottom: 70))
        let low = place(.init(caret: CGRect(x: 400, y: 940, width: 2, height: 18)), screens: [s])
        XCTAssertGreaterThanOrEqual(low.origin.y, 70)
        assertInside(low)
        let high = place(.init(caret: CGRect(x: 400, y: 10, width: 2, height: 18)), screens: [s])
        XCTAssertTrue(high.flipped)
        assertInside(high)
    }

    func testPanelWiderThanVisibleFrameKeepsLeftEdgeOnScreen() {
        let wide = CGSize(width: 2000, height: 120)
        let p = place(.init(caret: CGRect(x: 800, y: 500, width: 2, height: 18)), screens: [screen()], panel: wide)
        XCTAssertEqual(p.origin.x, 0)
    }

    func testNoCaretFallsBackToBottomCentreOnElement() {
        let ax = CGRect(x: 200, y: 100, width: 800, height: 600)
        let p = place(.init(element: ax), screens: [screen()])
        let element = OverlayPlacement.appKitRect(fromAX: ax, primaryScreenHeight: 1000)
        XCTAssertEqual(p.source, .element)
        XCTAssertEqual(p.origin.x, element.midX - panel.width / 2)
        XCTAssertEqual(p.origin.y, element.minY + 16)
    }

    func testNoCaretNoElementUsesWindow() {
        let p = place(.init(window: CGRect(x: 100, y: 100, width: 900, height: 700)), screens: [screen()])
        XCTAssertEqual(p.source, .window)
        assertInside(p)
    }

    func testNoCandidatesUsesScreenBottomCentre() {
        let s = screen(inset: (top: 25, bottom: 70))
        let p = place(.init(), screens: [s])
        XCTAssertEqual(p.source, .screen)
        XCTAssertEqual(p.origin.y, s.visibleFrame.minY + 48)
        assertInside(p)
    }

    func testCaretOnNoScreenIsTreatedAsNoCaret() {
        let p = place(.init(caret: CGRect(x: 9000, y: 500, width: 2, height: 18),
                            element: CGRect(x: 200, y: 100, width: 800, height: 600)),
                      screens: [screen()])
        XCTAssertEqual(p.source, .element)
    }

    func testDegenerateCaretRectsAreTreatedAsNoCaret() {
        let element = CGRect(x: 200, y: 100, width: 800, height: 600)
        for caret in [CGRect(x: 400, y: 500, width: 2, height: 0),
                      CGRect(x: CGFloat.nan, y: 500, width: 2, height: 18),
                      CGRect(x: 400, y: CGFloat.infinity, width: 2, height: 18)] {
            XCTAssertEqual(place(.init(caret: caret, element: element), screens: [screen()]).source, .element,
                           "caret \(caret)")
        }
    }
}
