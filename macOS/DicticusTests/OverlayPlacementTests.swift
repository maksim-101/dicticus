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
            candidates: .init(caret: ax, window: CGRect(x: 200, y: 100, width: 800, height: 700)), panel: panel, screens: [s],
            primaryScreenHeight: 1000, fallback: s
        )
        let caret = OverlayPlacement.appKitRect(fromAX: ax, primaryScreenHeight: 1000)
        XCTAssertEqual(placement.source, .caret)
        XCTAssertFalse(placement.flipped)
        XCTAssertEqual(placement.origin.y, caret.maxY + 8)
        XCTAssertEqual(placement.origin.x, 600 - panel.width / 2)
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

    // Host session 2: Safari's address bar and Music's search field sit at the top of the screen;
    // the flipped panel measured from the caret line covered the lower part of the field.
    func testSingleLineFieldNearTopFlipsBelowTheWholeField() {
        let field = CGRect(x: 300, y: 12, width: 600, height: 34)
        let ax = CGRect(x: 320, y: 21, width: 2, height: 16)
        let p = place(.init(caret: ax, element: field), screens: [screen()])
        let fieldRect = OverlayPlacement.appKitRect(fromAX: field, primaryScreenHeight: 1000)
        XCTAssertTrue(p.flipped)
        XCTAssertEqual(p.origin.y, fieldRect.minY - 8 - panel.height)
        assertInside(p)
    }

    func testSingleLineFieldKeepsThePanelAboveTheWholeField() {
        let field = CGRect(x: 300, y: 500, width: 600, height: 34)
        let ax = CGRect(x: 320, y: 509, width: 2, height: 16)
        let p = place(.init(caret: ax, element: field), screens: [screen()])
        let fieldRect = OverlayPlacement.appKitRect(fromAX: field, primaryScreenHeight: 1000)
        XCTAssertFalse(p.flipped)
        XCTAssertEqual(p.origin.y, fieldRect.maxY + 8)
    }

    // Host session 2: a tall text area inside a window sends the panel to the opposite half of the
    // window; without a window to measure against, the caret line still decides (D-11 fallback).
    func testTallTextAreaWithoutAWindowStillFollowsTheCaretLine() {
        let area = CGRect(x: 0, y: 40, width: 1600, height: 900)
        let ax = CGRect(x: 5, y: 800, width: 2, height: 42)
        let p = place(.init(caret: ax, element: area), screens: [screen()])
        let caret = OverlayPlacement.appKitRect(fromAX: ax, primaryScreenHeight: 1000)
        XCTAssertFalse(p.flipped)
        XCTAssertEqual(p.origin.y, caret.maxY + 8)
    }

    // MARK: - A caret outside its element or window is bogus (review round 1, IN-02)

    func testACaretFarOutsideTheFocusedElementIsIgnoredAndTheElementDecidesTheSpot() {
        let field = CGRect(x: 300, y: 500, width: 600, height: 34)
        let bogus = CGRect(x: 0, y: 0, width: 2, height: 18)
        let p = place(.init(caret: bogus, element: field), screens: [screen()])
        let fieldRect = OverlayPlacement.appKitRect(fromAX: field, primaryScreenHeight: 1000)
        XCTAssertEqual(p.source, .element)
        XCTAssertEqual(p.origin.y, fieldRect.maxY + 8, "a single-line field keeps the panel clear of the whole field")
    }

    func testACaretOutsideTheWindowIsIgnoredWhenThereIsNoElement() {
        let window = CGRect(x: 200, y: 100, width: 800, height: 700)
        let bogus = CGRect(x: 10, y: 10, width: 2, height: 18)
        let p = place(.init(caret: bogus, window: window), screens: [screen()])
        XCTAssertEqual(p.source, .window)
        XCTAssertTrue(OverlayPlacement.appKitRect(fromAX: window, primaryScreenHeight: 1000)
            .insetBy(dx: -1, dy: -1).contains(CGRect(origin: p.origin, size: panel)))
    }

    func testAWindowOnAnotherDisplayCannotVetoTheCaret() {
        let screens = [screen(), screen(1600, 0)]
        let p = place(.init(caret: CGRect(x: 1700, y: 500, width: 2, height: 18),
                            window: CGRect(x: 100, y: 100, width: 800, height: 700)), screens: screens)
        XCTAssertEqual(p.source, .caret, "a stale window on the other display discarded a good caret")
    }

    func testACaretJustOutsideItsElementStaysTheAnchor() {
        let field = CGRect(x: 300, y: 500, width: 600, height: 34)
        let nearEdge = CGRect(x: 292, y: 509, width: 2, height: 16)
        let p = place(.init(caret: nearEdge, element: field), screens: [screen()])
        XCTAssertEqual(p.source, .caret, "a caret a few points past the element edge is within tolerance")
    }

    // MARK: - Large text areas (plan 51-13, host session 2 decision)

    private let largeWindow = CGRect(x: 100, y: 100, width: 1200, height: 800)
    private let largeArea = CGRect(x: 100, y: 140, width: 1200, height: 760)

    func testLargeAreaCaretInLowerHalfPutsThePanelAtTheTopOfTheWindow() {
        let ax = CGRect(x: 140, y: 800, width: 2, height: 18)
        let p = place(.init(caret: ax, element: largeArea, window: largeWindow), screens: [screen()])
        let window = OverlayPlacement.appKitRect(fromAX: largeWindow, primaryScreenHeight: 1000)
        XCTAssertEqual(p.source, .caret)
        XCTAssertFalse(p.flipped)
        XCTAssertEqual(p.origin.y, window.maxY - 44 - panel.height)
        XCTAssertEqual(p.origin.x, window.midX - panel.width / 2)
        assertInside(p)
    }

    func testLargeAreaCaretInUpperHalfPutsThePanelAtTheBottomOfTheWindow() {
        let ax = CGRect(x: 140, y: 200, width: 2, height: 18)
        let p = place(.init(caret: ax, element: largeArea, window: largeWindow), screens: [screen()])
        let window = OverlayPlacement.appKitRect(fromAX: largeWindow, primaryScreenHeight: 1000)
        XCTAssertEqual(p.source, .caret)
        XCTAssertTrue(p.flipped)
        XCTAssertEqual(p.origin.y, window.minY + 16)
        XCTAssertEqual(p.origin.x, window.midX - panel.width / 2)
        assertInside(p)
    }

    func testLargeAreaWithoutCaretPutsThePanelAtTheTopOfTheWindow() {
        let p = place(.init(element: largeArea, window: largeWindow), screens: [screen()])
        let window = OverlayPlacement.appKitRect(fromAX: largeWindow, primaryScreenHeight: 1000)
        XCTAssertEqual(p.source, .element)
        XCTAssertFalse(p.flipped)
        XCTAssertEqual(p.origin.y, window.maxY - 44 - panel.height)
        XCTAssertEqual(p.origin.x, window.midX - panel.width / 2)
    }

    // Review 2 WR-01: a palette-style window (40 pt field in a 70 pt window) passed the large-area
    // ratio, and the top-of-window band covered the whole window and the field.
    func testPaletteWindowFieldIsKeptClearAsASingleLineField() {
        let window = CGRect(x: 500, y: 300, width: 600, height: 70)
        let field = CGRect(x: 520, y: 315, width: 560, height: 40)
        let ax = CGRect(x: 540, y: 327, width: 2, height: 16)
        let p = place(.init(caret: ax, element: field, window: window), screens: [screen()])
        let fieldRect = OverlayPlacement.appKitRect(fromAX: field, primaryScreenHeight: 1000)
        XCTAssertFalse(p.flipped)
        XCTAssertEqual(p.origin.y, fieldRect.maxY + 8)
    }

    func testLargeAreaTopPlacementIsClampedWhenTheWindowReachesAboveTheScreen() {
        let tall = CGRect(x: 100, y: -150, width: 1200, height: 800)
        let area = CGRect(x: 100, y: -100, width: 1200, height: 740)
        let ax = CGRect(x: 140, y: 600, width: 2, height: 18)
        let s = screen(inset: (top: 25, bottom: 0))
        let p = place(.init(caret: ax, element: area, window: tall), screens: [s])
        XCTAssertEqual(p.origin.y, s.visibleFrame.maxY - panel.height)
        assertInside(p)
    }

    func testAnElementUnderHalfTheWindowStillFollowsTheCaretLine() {
        let small = CGRect(x: 100, y: 600, width: 1200, height: 300)
        let ax = CGRect(x: 140, y: 800, width: 2, height: 18)
        let p = place(.init(caret: ax, element: small, window: largeWindow), screens: [screen()])
        XCTAssertEqual(p.origin.y, OverlayPlacement.appKitRect(fromAX: ax, primaryScreenHeight: 1000).maxY + 8)
    }

    func testWindowAtRightEdgeClampsHorizontally() {
        let p = place(.init(caret: CGRect(x: 1590, y: 500, width: 2, height: 18),
                            window: CGRect(x: 1500, y: 100, width: 100, height: 700)), screens: [screen()])
        XCTAssertEqual(p.origin.x, 1600 - panel.width)
        assertInside(p)
    }

    func testCaretOnLeftHandDisplayWithNegativeCoordinates() {
        let screens = [screen(), screen(-1600, 0)]
        let p = place(.init(caret: CGRect(x: -1390, y: 500, width: 2, height: 18),
                            window: CGRect(x: -1400, y: 100, width: 800, height: 700)), screens: screens)
        XCTAssertEqual(p.source, .caret)
        XCTAssertEqual(p.origin.x, -1000 - panel.width / 2)
        XCTAssertEqual(p.visibleFrame, screens[1].visibleFrame)
        assertInside(p)
    }

    func testCaretOnSecondScreenUsesThatScreensVisibleFrame() {
        let screens = [screen(), screen(1600, 0)]
        let p = place(.init(caret: CGRect(x: 2000, y: 500, width: 2, height: 18),
                            window: CGRect(x: 1800, y: 100, width: 600, height: 700)), screens: screens)
        XCTAssertEqual(p.visibleFrame, screens[1].visibleFrame)
        XCTAssertEqual(p.origin.x, 2100 - panel.width / 2)
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
        let p = place(.init(caret: CGRect(x: 800, y: 500, width: 2, height: 18),
                            window: CGRect(x: 100, y: 100, width: 600, height: 700)), screens: [screen()], panel: wide)
        XCTAssertEqual(p.origin.x, 0)
    }

    // MARK: - Window centring (plan 51-12, user decision in host session 1)

    func testPanelIsCentredOnTheWindowWhereverTheCaretIs() {
        let window = CGRect(x: 100, y: 100, width: 1200, height: 700)
        let atStart = place(.init(caret: CGRect(x: 120, y: 500, width: 2, height: 18), window: window), screens: [screen()])
        let atEnd = place(.init(caret: CGRect(x: 1250, y: 500, width: 2, height: 18), window: window), screens: [screen()])
        XCTAssertEqual(atStart.source, .caret)
        XCTAssertEqual(atStart.origin.x, 700 - panel.width / 2)
        XCTAssertEqual(atEnd.origin.x, atStart.origin.x)
        XCTAssertEqual(atEnd.origin.y, atStart.origin.y)
    }

    func testCaretLineStillDecidesTheHeightWhenCentredOnTheWindow() {
        let window = CGRect(x: 100, y: 0, width: 1200, height: 700)
        let ax = CGRect(x: 120, y: 300, width: 2, height: 18)
        let p = place(.init(caret: ax, window: window), screens: [screen()])
        XCTAssertEqual(p.origin.y, OverlayPlacement.appKitRect(fromAX: ax, primaryScreenHeight: 1000).maxY + 8)
        let top = place(.init(caret: CGRect(x: 120, y: 20, width: 2, height: 18), window: window), screens: [screen()])
        XCTAssertTrue(top.flipped)
        XCTAssertEqual(top.origin.x, 700 - panel.width / 2)
    }

    func testWithoutWindowTheElementCentresTheCaretPanel() {
        let p = place(.init(caret: CGRect(x: 300, y: 500, width: 2, height: 18),
                            element: CGRect(x: 200, y: 400, width: 800, height: 200)), screens: [screen()])
        XCTAssertEqual(p.source, .caret)
        XCTAssertEqual(p.origin.x, 600 - panel.width / 2)
    }

    func testWithoutWindowOrElementTheCaretScreenCentresTheCaretPanel() {
        let screens = [screen(), screen(1600, 0, inset: (top: 25, bottom: 70))]
        let p = place(.init(caret: CGRect(x: 1700, y: 500, width: 2, height: 18)), screens: screens)
        XCTAssertEqual(p.origin.x, screens[1].visibleFrame.midX - panel.width / 2)
        assertInside(p)
    }

    func testWindowOnAnotherDisplayDoesNotPullThePanelAwayFromTheCaret() {
        let screens = [screen(), screen(1600, 0)]
        let p = place(.init(caret: CGRect(x: 1700, y: 500, width: 2, height: 18),
                            window: CGRect(x: 100, y: 100, width: 800, height: 700)), screens: screens)
        XCTAssertEqual(p.visibleFrame, screens[1].visibleFrame)
        XCTAssertEqual(p.origin.x, screens[1].visibleFrame.midX - panel.width / 2)
    }

    func testFallbackOnElementCentresOnTheWindowWhenThereIsOne() {
        let p = place(.init(element: CGRect(x: 200, y: 100, width: 300, height: 600),
                            window: CGRect(x: 100, y: 50, width: 1000, height: 800)), screens: [screen()])
        XCTAssertEqual(p.source, .element)
        XCTAssertEqual(p.origin.x, 600 - panel.width / 2)
    }

    func testNoCaretFallsBackToBottomCentreOnElement() {
        let ax = CGRect(x: 200, y: 100, width: 800, height: 600)
        let p = place(.init(element: ax), screens: [screen()])
        let element = OverlayPlacement.appKitRect(fromAX: ax, primaryScreenHeight: 1000)
        XCTAssertEqual(p.source, .element)
        XCTAssertEqual(p.origin.x, element.midX - panel.width / 2)
        XCTAssertEqual(p.origin.y, element.minY + 16)
    }

    // Host session 2: Vivaldi's address bar with the URL selected reports no caret; the
    // bottom-centre fallback put the panel inside the field.
    func testSingleLineFieldWithoutCaretIsKeptClearAsAWhole() {
        let field = CGRect(x: 300, y: 12, width: 600, height: 34)
        let p = place(.init(element: field), screens: [screen()])
        let fieldRect = OverlayPlacement.appKitRect(fromAX: field, primaryScreenHeight: 1000)
        XCTAssertEqual(p.source, .element)
        XCTAssertTrue(p.flipped)
        XCTAssertEqual(p.origin.y, fieldRect.minY - 8 - panel.height)
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
