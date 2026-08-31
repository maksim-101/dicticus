import XCTest
@testable import Dicticus

/// Quick task 260831-nt6: the selection logic that decides whether a caught
/// TranscriptionError is silent or worth a user-facing notification — extracted
/// specifically so it's testable as pure logic, without a live HotkeyManager,
/// TranscriptionService, or UNUserNotificationCenter.
final class TranscriptionFailureRouterTests: XCTestCase {

    // MARK: - Silent outcomes (D-02/D-16 + the noResult extension)

    func testTooShortIsSilent() {
        XCTAssertEqual(TranscriptionFailureRouter.route(.tooShort), .silent)
    }

    func testSilenceOnlyIsSilent() {
        XCTAssertEqual(TranscriptionFailureRouter.route(.silenceOnly), .silent)
    }

    func testNoResultIsSilent() {
        // The regression this quick task fixes: a no-result outcome after a
        // deliberately-silent hotkey press (no voice activity, WhisperKit decoded
        // nothing) must NOT surface a "models failed to load" notification —
        // the models were never at fault.
        XCTAssertEqual(TranscriptionFailureRouter.route(.noResult), .silent)
    }

    // MARK: - Genuine failures still notify

    func testModelNotReadyNotifiesTranscriptionFailed() {
        XCTAssertEqual(TranscriptionFailureRouter.route(.modelNotReady), .notifyTranscriptionFailed)
    }

    func testNotRecordingNotifiesTranscriptionFailed() {
        XCTAssertEqual(TranscriptionFailureRouter.route(.notRecording), .notifyTranscriptionFailed)
    }

    func testBusyNotifiesTranscriptionFailed() {
        XCTAssertEqual(TranscriptionFailureRouter.route(.busy), .notifyTranscriptionFailed)
    }

    // MARK: - Unexpected language keeps its own distinct notification

    func testUnexpectedLanguageNotifiesUnexpectedLanguage() {
        XCTAssertEqual(TranscriptionFailureRouter.route(.unexpectedLanguage), .notifyUnexpectedLanguage)
    }

    // MARK: - Every TranscriptionError case is covered (regression net against a future case being forgotten)

    func testEveryTranscriptionErrorCaseHasARoute() {
        let errors: [TranscriptionError] = [
            .tooShort, .silenceOnly, .noResult, .modelNotReady, .notRecording, .busy, .unexpectedLanguage
        ]
        for error in errors {
            _ = TranscriptionFailureRouter.route(error)  // must not crash / must be exhaustive
        }
    }
}
