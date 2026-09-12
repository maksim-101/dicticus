import XCTest
@testable import Dicticus

final class NotificationServiceTests: XCTestCase {

    // MARK: - Notification message content (UI-SPEC copywriting contract)

    func testBusyNotificationMessage() {
        let notification = DicticusNotification.busy
        XCTAssertEqual(notification.message, "Still processing \u{2014} try again in a moment.")
    }

    func testModelLoadingNotificationMessage() {
        let notification = DicticusNotification.modelLoading
        XCTAssertEqual(notification.message, "Models still loading, please wait a moment.")
    }

    func testTranscriptionFailedMessage() {
        let error = NSError(domain: "test", code: 1)
        let notification = DicticusNotification.transcriptionFailed(error)
        XCTAssertEqual(notification.message, "Transcription failed \u{2014} check model status in the menu bar.")
    }

    func testRecordingFailedMessage() {
        let error = NSError(domain: "test", code: 2)
        let notification = DicticusNotification.recordingFailed(error)
        XCTAssertEqual(notification.message, "Could not start recording. Check microphone permission.")
    }

    func testAllNotificationsHaveDicticusTitle() {
        let cases: [DicticusNotification] = [
            .busy,
            .modelLoading,
            .transcriptionFailed(NSError(domain: "test", code: 1)),
            .recordingFailed(NSError(domain: "test", code: 2)),
            .pasteUndeliverable
        ]
        for notification in cases {
            XCTAssertEqual(notification.title, "Dicticus", "Title mismatch for \(notification)")
        }
    }

    // MARK: - Phase 50 D-02: paste-undeliverable fallback notification

    func testPasteUndeliverableMessage() {
        let notification = DicticusNotification.pasteUndeliverable
        XCTAssertEqual(notification.message, "Couldn't paste \u{2014} text is on your clipboard, \u{2318}V to paste.")
        XCTAssertEqual(notification.title, "Dicticus")
    }

    // MARK: - Phase 50-09: in-app notice surface (D-02 gap)

    @MainActor
    func testPostSetsUnreadNotice() {
        let service = NotificationService()
        XCTAssertNil(service.unreadNotice)

        service.post(.pasteUndeliverable)
        XCTAssertEqual(service.unreadNotice?.message, DicticusNotification.pasteUndeliverable.message)

        service.post(.busy)
        XCTAssertEqual(service.unreadNotice?.message, DicticusNotification.busy.message)
    }

    // MARK: - Phase 50-09 Task 3: caseName never carries payload (T-50-09-01)

    func testCaseNameNeverCarriesPayload() {
        let transcriptionFailed = DicticusNotification.transcriptionFailed(NSError(domain: "secret-domain", code: 7))
        XCTAssertEqual(transcriptionFailed.caseName, "transcriptionFailed")
        XCTAssertFalse(transcriptionFailed.caseName.contains("secret-domain"))

        let recordingFailed = DicticusNotification.recordingFailed(NSError(domain: "x", code: 1))
        XCTAssertEqual(recordingFailed.caseName, "recordingFailed")

        XCTAssertEqual(DicticusNotification.pasteUndeliverable.caseName, "pasteUndeliverable")
        XCTAssertEqual(DicticusNotification.cleanupSkippedTooLong.caseName, "cleanupSkippedTooLong")
    }
}
