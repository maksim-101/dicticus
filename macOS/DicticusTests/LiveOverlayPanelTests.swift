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
