import XCTest
import AppKit
import SwiftUI
@testable import Dicticus

@MainActor
final class LiveOverlayPanelTests: XCTestCase {

    // MARK: - Tracer: session -> overlay -> hide

    func testSessionPublishesIntoOverlayThenHideKeepsTextThroughTheFade() async throws {
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
        while controller.modelForTesting.combined != "hello world", ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(controller.modelForTesting.combined, "hello world")
        XCTAssertEqual(controller.modelForTesting.tentative, "hello world", "a two-word preview is all pale")

        await session.cancelAndDrain()

        controller.setProcessing()
        XCTAssertEqual(controller.modelForTesting.phase, .processing)
        XCTAssertEqual(controller.modelForTesting.settled, "hello world", "release settles every word")
        XCTAssertEqual(controller.modelForTesting.tentative, "")

        controller.hide(reason: .pasting)
        XCTAssertEqual(controller.modelForTesting.combined, "hello world", "the exit fade still shows the text (IN-04)")
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
        XCTAssertTrue(hosting is NSHostingView<LiveOverlayView>, "SwiftUI content is the glass contentView, got \(hosting.className)")
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

    private func makeStage(
        flags: OverlayAccessibilityFlags = OverlayAccessibilityFlags(reduceMotion: true),
        caretAppKit: (OverlayPlacement.ScreenGeometry) -> CGRect
    ) throws -> (Stage, CaretAnchor.Candidates) {
        let screens = NSScreen.screens.map {
            OverlayPlacement.ScreenGeometry(frame: $0.frame, visibleFrame: $0.visibleFrame)
        }
        guard let primary = screens.first else { throw XCTSkip("no screen") }
        let caret = caretAppKit(primary)
        let ax = CGRect(x: caret.minX, y: primary.frame.height - caret.maxY, width: caret.width, height: caret.height)
        let candidates = CaretAnchor.Candidates(caret: ax, element: nil, window: nil)
        let controller = LiveOverlayController(
            targetAlpha: 0, accessibility: { flags },
            candidateProvider: { _ in candidates })
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

    // MARK: - Accessibility and motion (scene A, 2026-10-15)

    private func midScreenCaret(_ s: OverlayPlacement.ScreenGeometry) -> CGRect {
        CGRect(x: s.visibleFrame.midX, y: s.visibleFrame.midY, width: 2, height: 18)
    }

    func testReduceTransparencyHidesTheShadowAndSwitchesTheModelToTheOpaqueFill() async throws {
        let (reduced, _) = try makeStage(flags: OverlayAccessibilityFlags(reduceTransparency: true, reduceMotion: true),
                                         caretAppKit: midScreenCaret)
        _ = try await presentedPaneRect(reduced.controller)
        defer { reduced.controller.hide(reason: .demo) }
        XCTAssertTrue(try XCTUnwrap(reduced.controller.panelForTesting).shadowView.isHidden)
        XCTAssertTrue(reduced.controller.modelForTesting.reduceTransparency)

        let (normal, _) = try makeStage(caretAppKit: midScreenCaret)
        _ = try await presentedPaneRect(normal.controller)
        defer { normal.controller.hide(reason: .demo) }
        XCTAssertFalse(try XCTUnwrap(normal.controller.panelForTesting).shadowView.isHidden)
        XCTAssertFalse(normal.controller.modelForTesting.reduceTransparency)
    }

    func testFlagsAreReadAtEveryShow() async throws {
        var reduce = false
        let (_, candidates) = try makeStage(caretAppKit: midScreenCaret)
        let controller = LiveOverlayController(
            targetAlpha: 0, accessibility: { OverlayAccessibilityFlags(reduceTransparency: reduce, reduceMotion: true) },
            candidateProvider: { _ in candidates })
        _ = try await presentedPaneRect(controller)
        XCTAssertFalse(controller.modelForTesting.reduceTransparency)
        controller.hide(reason: .demo)
        reduce = true
        controller.show()
        XCTAssertTrue(controller.modelForTesting.reduceTransparency, "the setting changed between presses")
        XCTAssertTrue(try XCTUnwrap(controller.panelForTesting).shadowView.isHidden)
        controller.hide(reason: .demo)
    }

    func testReduceMotionPlacesThePaneAtItsFinalPositionImmediately() async throws {
        let (stage, candidates) = try makeStage(flags: OverlayAccessibilityFlags(reduceMotion: true),
                                                caretAppKit: midScreenCaret)
        defer { stage.controller.hide(reason: .demo) }
        let pane = try await presentedPaneRect(stage.controller)
        let expected = OverlayPlacement.place(
            candidates: candidates, panel: pane.size, screens: stage.screens,
            primaryScreenHeight: stage.primary.frame.height, fallback: stage.primary)
        XCTAssertEqual(pane.minY, expected.origin.y, accuracy: 0.5)
        XCTAssertTrue(stage.controller.modelForTesting.reduceMotion)
    }

    func testEntryRisesFromBelowTheFinalPositionUnlessMotionIsReduced() async throws {
        let (stage, candidates) = try makeStage(flags: OverlayAccessibilityFlags(reduceMotion: false),
                                                caretAppKit: midScreenCaret)
        defer { stage.controller.hide(reason: .demo) }
        let pane = try await presentedPaneRect(stage.controller)
        let expected = OverlayPlacement.place(
            candidates: candidates, panel: pane.size, screens: stage.screens,
            primaryScreenHeight: stage.primary.frame.height, fallback: stage.primary)
        XCTAssertLessThan(pane.minY, expected.origin.y - 0.5, "the pane starts below its target and rises")
        XCTAssertGreaterThanOrEqual(pane.minY, expected.origin.y - 8.5, "the rise is 8 pt")

        let deadline = ContinuousClock.now + .seconds(2)
        var settled = pane
        while abs(settled.minY - expected.origin.y) > 0.5, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
            let panel = try XCTUnwrap(stage.controller.panelForTesting)
            settled = panel.convertToScreen(panel.glassView.convert(panel.glassView.bounds, to: nil))
        }
        XCTAssertEqual(settled.minY, expected.origin.y, accuracy: 0.5, "the rise ends on the placement target")
    }

    func testThePanelIsSilentToVoiceOver() throws {
        let panel = LiveOverlayPanel(model: LiveOverlayModel())
        let hosting = try XCTUnwrap(panel.glassView.contentView)
        for (name, view) in [("wrapper", try XCTUnwrap(panel.contentView)), ("shadow", panel.shadowView),
                             ("glass", panel.glassView), ("hosting", hosting)] {
            XCTAssertFalse(view.isAccessibilityElement(), "\(name) view is announced")
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
        XCTAssertEqual(controller.modelForTesting.combined, "old text")
        XCTAssertFalse(controller.isVisible)

        controller.show()
        XCTAssertEqual(controller.modelForTesting.combined, "")
        XCTAssertEqual(controller.modelForTesting.phase, .listening)
        controller.hide(reason: .demo)
    }

    func testUpdateWhileHiddenDoesNotLeakIntoNextShow() {
        let controller = LiveOverlayController(targetAlpha: 0)
        controller.show()
        controller.update("kept")
        controller.hide(reason: .earlyReturn)
        controller.update("late preview result")
        XCTAssertEqual(controller.modelForTesting.combined, "kept", "a late preview result never reaches the fading panel")

        controller.show()
        XCTAssertEqual(controller.modelForTesting.combined, "", "the next show starts empty")
        controller.hide(reason: .demo)
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

    // MARK: - Settled / tentative (plan 51-10)

    func testUpdatesSplitTheLineIntoSettledAndTentativeWords() {
        let controller = LiveOverlayController(targetAlpha: 0)
        controller.show()
        controller.update("one two three four")
        XCTAssertEqual(controller.modelForTesting.settled, "")
        XCTAssertEqual(controller.modelForTesting.tentative, "one two three four")
        controller.update("one two three four five")
        XCTAssertEqual(controller.modelForTesting.settled, "one two three")
        XCTAssertEqual(controller.modelForTesting.tentative, "four five")
        controller.hide(reason: .demo)
    }

    func testSettleAndProcessingSettleEveryTentativeWord() {
        let controller = LiveOverlayController(targetAlpha: 0)
        controller.show()
        controller.update("one two three four")
        controller.update("one two three four five")
        controller.settle()
        XCTAssertEqual(controller.modelForTesting.settled, "one two three four five")
        XCTAssertEqual(controller.modelForTesting.tentative, "")
        XCTAssertEqual(controller.modelForTesting.phase, .listening, "a pause settles words but is not processing")

        controller.update("one two three four five six seven")
        XCTAssertEqual(controller.modelForTesting.combined, "one two three four five six seven", "words after the pause continue the same line")
        controller.setProcessing()
        XCTAssertEqual(controller.modelForTesting.tentative, "")
        XCTAssertEqual(controller.modelForTesting.settled, "one two three four five six seven")
        controller.hide(reason: .demo)
    }

    func testANewShowStartsAFreshStabilizer() {
        let controller = LiveOverlayController(targetAlpha: 0)
        controller.show()
        controller.update("old words that were said")
        controller.update("old words that were said before")
        controller.hide(reason: .pasting)

        controller.show()
        XCTAssertEqual(controller.modelForTesting.settled, "")
        XCTAssertEqual(controller.modelForTesting.tentative, "")
        controller.update("old words that were said before")
        XCTAssertEqual(controller.modelForTesting.settled, "", "nothing carries over: the first preview is all pale")
        XCTAssertEqual(controller.modelForTesting.tentative, "old words that were said before")
        controller.hide(reason: .demo)
    }

    func testSettleWhileHiddenIsIgnored() {
        let controller = LiveOverlayController(targetAlpha: 0)
        controller.show()
        controller.update("one two three")
        controller.hide(reason: .pasting)
        controller.settle()
        XCTAssertEqual(controller.modelForTesting.tentative, "one two three")
    }

    // MARK: - displayTail

    func testDisplayPartsCutOnlyTheSettledRunAndKeepTheTotalBounded() {
        let settled = (0..<200).map { "s\($0)x" }.joined(separator: " ")
        let tentative = "pale words"
        let parts = LiveOverlayView.displayParts(settled: settled, tentative: tentative)
        XCTAssertEqual(parts.tentative, tentative)
        XCTAssertLessThanOrEqual(parts.settled.count + 1 + parts.tentative.count, 400)
        XCTAssertEqual(parts.settled.last, settled.last)
        XCTAssertTrue(settled.hasSuffix(parts.settled))
    }

    func testDisplayPartsNeverCutAnOverlongTentativeRun() {
        let tentative = (0..<150).map { "t\($0)x" }.joined(separator: " ")
        let parts = LiveOverlayView.displayParts(settled: "settled words", tentative: tentative)
        XCTAssertEqual(parts.settled, "")
        XCTAssertEqual(parts.tentative, tentative)
    }

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
    private(set) var settleCount = 0
    private(set) var updates: [String] = []
    var currentSeq: Int { showCount }

    func show() { showCount += 1 }
    func update(_ text: String) { updates.append(text) }
    func settle() { settleCount += 1 }
    func setProcessing() { processingCount += 1 }
    func hide(reason: LiveOverlayHideReason) { hideReasons.append(reason) }
}
