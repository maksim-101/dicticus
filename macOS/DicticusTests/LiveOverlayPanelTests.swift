import XCTest
import AppKit
@testable import Dicticus

@MainActor
final class LiveOverlayPanelTests: XCTestCase {

    // MARK: - Tracer: session -> overlay -> hide

    func testSessionPublishesIntoOverlayThenHideClears() async throws {
        let controller = LiveOverlayController(targetAlpha: 0)
        controller.show()
        XCTAssertTrue(controller.isVisible)

        let session = LivePreviewSession(
            cadence: .milliseconds(50),
            isActive: { true },
            decode: { "hello world" },
            publish: { controller.update($0) }
        )
        session.start()

        let deadline = ContinuousClock.now + .seconds(1)
        while controller.modelForTesting.text != "hello world", ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(controller.modelForTesting.text, "hello world")

        await session.cancelAndDrain()

        controller.setProcessing()
        XCTAssertEqual(controller.modelForTesting.phase, .processing)

        controller.hide(reason: .pasting)
        XCTAssertEqual(controller.modelForTesting.text, "")
        XCTAssertFalse(controller.isVisible)
    }

    override func tearDown() {
        DicticusDefaults.suite.removeObject(forKey: "debugOverlayCapturable")
        super.tearDown()
    }

    // MARK: - Panel invariants (D-12, D-18)

    func testPanelNeverTakesFocus() {
        let panel = LiveOverlayPanel(model: LiveOverlayModel())
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(panel.styleMask.contains(.borderless))
        XCTAssertTrue(panel.ignoresMouseEvents)
        XCTAssertTrue(panel.isFloatingPanel)
        XCTAssertEqual(panel.level, .floating)
        XCTAssertFalse(panel.hidesOnDeactivate)
        for behavior: NSWindow.CollectionBehavior in [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle] {
            XCTAssertTrue(panel.collectionBehavior.contains(behavior), "missing \(behavior)")
        }
    }

    func testOrderedFrontPanelIsNeitherKeyNorMain() {
        let panel = LiveOverlayPanel(model: LiveOverlayModel())
        panel.alphaValue = 0
        panel.setFrameOrigin(CGPoint(x: -20_000, y: -20_000))
        panel.orderFrontRegardless()
        defer { panel.orderOut(nil) }
        XCTAssertFalse(panel.isKeyWindow)
        XCTAssertFalse(panel.isMainWindow)
        XCTAssertTrue(NSApp.keyWindow !== panel)
    }

    func testSharingTypeIsNoneByDefault() {
        XCTAssertEqual(LiveOverlayPanel(model: LiveOverlayModel()).sharingType, .none)
    }

    #if DEBUG
    func testDebugCapturableKeyMakesPanelReadOnly() {
        DicticusDefaults.suite.set(true, forKey: "debugOverlayCapturable")
        XCTAssertEqual(LiveOverlayPanel(model: LiveOverlayModel()).sharingType, .readOnly)
    }
    #endif

    // MARK: - Glass root (2026-10-15 decision, variant J)

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    private func glassView(of panel: NSPanel) throws -> NSGlassEffectView {
        let root = try XCTUnwrap(panel.contentView)
        let glass = descendants(of: root).compactMap { $0 as? NSGlassEffectView }
        XCTAssertEqual(glass.count, 1, "exactly one AppKit glass view")
        return try XCTUnwrap(glass.first)
    }

    func testPaneIsOneAppKitGlassViewHostingTheContentWithRoomForTheShadow() throws {
        let panel = LiveOverlayPanel(model: LiveOverlayModel())
        let root = try XCTUnwrap(panel.contentView)
        let glass = try glassView(of: panel)

        let hosting = try XCTUnwrap(glass.contentView)
        XCTAssertTrue(hosting.className.contains("NSHostingView"), "SwiftUI content is the glass contentView, got \(hosting.className)")
        XCTAssertEqual(hosting.frame, glass.bounds)

        let left = glass.frame.minX, bottom = glass.frame.minY
        let right = root.bounds.maxX - glass.frame.maxX, top = root.bounds.maxY - glass.frame.maxY
        XCTAssertEqual(Set([left, right, top, bottom]).count, 1, "equal margin on every side")
        XCTAssertGreaterThanOrEqual(left, 14 + 7, "margin holds the radius-14, offset-7 shadow")
        XCTAssertEqual(glass.cornerRadius, 22)
    }

    func testGlassTintIsLightAndNoViewPaintsAnOpaqueBackground() throws {
        let panel = LiveOverlayPanel(model: LiveOverlayModel())
        let glass = try glassView(of: panel)
        let tint = try XCTUnwrap(glass.tintColor)

        func alpha(under name: NSAppearance.Name) -> CGFloat {
            var result: CGFloat = -1
            NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
                result = tint.usingColorSpace(.sRGB)?.alphaComponent ?? -1
            }
            return result
        }
        let dark = alpha(under: .darkAqua), light = alpha(under: .aqua)
        XCTAssertGreaterThan(dark, 0)
        XCTAssertLessThanOrEqual(dark, 0.10, "a dark layer on the glass is what made the black box")
        XCTAssertLessThan(light, dark)

        let root = try XCTUnwrap(panel.contentView)
        for view in [root] + descendants(of: root) {
            let background = view.layer?.backgroundColor.flatMap { NSColor(cgColor: $0) }
            XCTAssertTrue(background == nil || background!.alphaComponent == 0,
                          "\(view.className) paints a background")
        }
        let shadowed = descendants(of: root).filter { $0.layer?.shadowPath != nil }
        XCTAssertEqual(shadowed.count, 1, "one sibling view carries the shadow path")
        XCTAssertFalse(glass.layer?.shadowOpacity ?? 0 > 0, "the glass itself casts no shadow")
    }

    // MARK: - Pane placement (D-09..D-11 act on the visible pane, not the shadow margin)

    private struct Stage {
        let controller: LiveOverlayController
        let screens: [OverlayPlacement.ScreenGeometry]
        var primary: OverlayPlacement.ScreenGeometry { screens[0] }
    }

    private func makeStage(caretAppKit: (OverlayPlacement.ScreenGeometry) -> CGRect) throws -> (Stage, CaretAnchor.Candidates) {
        let screens = NSScreen.screens.map {
            OverlayPlacement.ScreenGeometry(frame: $0.frame, visibleFrame: $0.visibleFrame)
        }
        guard let primary = screens.first else { throw XCTSkip("no screen") }
        let caret = caretAppKit(primary)
        let ax = CGRect(x: caret.minX, y: primary.frame.height - caret.maxY, width: caret.width, height: caret.height)
        let candidates = CaretAnchor.Candidates(caret: ax, element: nil, window: nil)
        let controller = LiveOverlayController(targetAlpha: 0, candidateProvider: { _ in candidates })
        return (Stage(controller: controller, screens: screens), candidates)
    }

    private func presentedPaneRect(_ controller: LiveOverlayController) async throws -> CGRect {
        controller.show()
        let deadline = ContinuousClock.now + .seconds(2)
        while controller.panelForTesting?.isVisible != true, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let panel = try XCTUnwrap(controller.panelForTesting)
        XCTAssertTrue(panel.isVisible)
        let glass = try glassView(of: panel)
        return panel.convertToScreen(glass.convert(glass.bounds, to: nil))
    }

    func testVisiblePaneLandsWhereThePlacementMathPutsIt() async throws {
        let (stage, candidates) = try makeStage { s in
            CGRect(x: s.visibleFrame.midX, y: s.visibleFrame.midY, width: 2, height: 18)
        }
        defer { stage.controller.hide(reason: .demo) }
        let pane = try await presentedPaneRect(stage.controller)
        let expected = OverlayPlacement.place(
            candidates: candidates,
            panel: pane.size,
            screens: stage.screens,
            primaryScreenHeight: stage.primary.frame.height,
            fallback: stage.primary)
        XCTAssertEqual(pane.origin.x, expected.origin.x, accuracy: 0.5)
        XCTAssertEqual(pane.origin.y, expected.origin.y, accuracy: 0.5)
    }

    func testPaneIsClampedFlushToTheVisibleFrameAtBothScreenEdges() async throws {
        for atRight in [false, true] {
            let (stage, _) = try makeStage { s in
                CGRect(x: atRight ? s.visibleFrame.maxX - 4 : s.visibleFrame.minX + 4,
                       y: s.visibleFrame.midY, width: 2, height: 18)
            }
            let pane = try await presentedPaneRect(stage.controller)
            stage.controller.hide(reason: .demo)
            let visible = stage.primary.visibleFrame
            // The caret sits inside the edge, so the clamp pins the pane flush to it.
            if atRight {
                XCTAssertEqual(pane.maxX, visible.maxX, accuracy: 0.5, "pane is clamped flush right")
            } else {
                XCTAssertEqual(pane.minX, visible.minX, accuracy: 0.5, "pane is clamped flush left")
            }
            let window = try XCTUnwrap(stage.controller.panelForTesting).frame
            XCTAssertGreaterThan(window.width, pane.width, "the shadow margin may reach past the screen edge")
        }
    }

    // MARK: - Controller lifecycle

    func testHideTwiceIsSafeAndShowResetsTheModel() {
        let controller = LiveOverlayController(targetAlpha: 0)
        controller.show()
        controller.update("old text")
        controller.setProcessing()
        controller.hide(reason: .pasting)
        controller.hide(reason: .taskEnd)
        XCTAssertEqual(controller.modelForTesting.text, "")
        XCTAssertFalse(controller.isVisible)

        controller.show()
        XCTAssertEqual(controller.modelForTesting.text, "")
        XCTAssertEqual(controller.modelForTesting.phase, .listening)
        controller.hide(reason: .demo)
    }

    func testUpdateWhileHiddenDoesNotLeakIntoNextShow() {
        let controller = LiveOverlayController(targetAlpha: 0)
        controller.show()
        controller.hide(reason: .earlyReturn)
        controller.update("late preview result")
        XCTAssertEqual(controller.modelForTesting.text, "")
    }

    func testCurrentSeqCountsRealShowsOnly() {
        let controller = LiveOverlayController(targetAlpha: 0)
        XCTAssertEqual(controller.currentSeq, 0)
        controller.show()
        controller.hide(reason: .pasting)
        controller.hide(reason: .taskEnd)
        controller.show()
        controller.hide(reason: .pasting)
        XCTAssertEqual(controller.currentSeq, 2)
    }

    // MARK: - displayTail

    func testDisplayTailBoundsLongTextOnAWordStart() {
        let words = (0..<200).map { "w\($0)x" }
        let text = words.joined(separator: " ")
        XCTAssertGreaterThan(text.count, 400)
        let tail = LiveOverlayView.displayTail(text)
        XCTAssertLessThanOrEqual(tail.count, 400)
        XCTAssertEqual(tail.last, text.last)
        XCTAssertTrue(words.contains(String(tail.prefix(while: { !$0.isWhitespace }))),
                      "tail must not start mid-word: \(tail.prefix(12))")
    }

    func testDisplayTailLeavesShortTextAlone() {
        let text = String(repeating: "a", count: 50)
        XCTAssertEqual(LiveOverlayView.displayTail(text), text)
    }
}

// MARK: - Spy

@MainActor
final class SpyOverlay: LiveOverlayPresenting {
    private(set) var showCount = 0
    private(set) var hideReasons: [LiveOverlayHideReason] = []
    private(set) var processingCount = 0
    private(set) var updates: [String] = []
    var currentSeq: Int { showCount }

    func show() { showCount += 1 }
    func update(_ text: String) { updates.append(text) }
    func setProcessing() { processingCount += 1 }
    func hide(reason: LiveOverlayHideReason) { hideReasons.append(reason) }
}
