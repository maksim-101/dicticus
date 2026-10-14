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
}
