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

    func testInputUnavailableNotifiesTranscriptionFailed() {
        XCTAssertEqual(TranscriptionFailureRouter.route(.inputUnavailable), .notifyTranscriptionFailed)
    }

    func testInputInterruptedNotifiesTranscriptionFailed() {
        // A hold whose audio vanished must notify, never route silent (quick task 261018-go0).
        XCTAssertEqual(TranscriptionFailureRouter.route(.inputInterrupted), .notifyTranscriptionFailed)
    }

    // MARK: - Unexpected language keeps its own distinct notification

    func testUnexpectedLanguageNotifiesUnexpectedLanguage() {
        XCTAssertEqual(TranscriptionFailureRouter.route(.unexpectedLanguage), .notifyUnexpectedLanguage)
    }

    // MARK: - Every TranscriptionError case is covered (regression net against a future case being forgotten)

    func testEveryTranscriptionErrorCaseHasARoute() {
        let errors: [TranscriptionError] = [
            .tooShort, .silenceOnly, .noResult, .modelNotReady, .notRecording, .busy, .unexpectedLanguage,
            .inputUnavailable, .inputInterrupted
        ]
        for error in errors {
            _ = TranscriptionFailureRouter.route(error)  // must not crash / must be exhaustive
        }
    }

    // MARK: - End of a hold whose input was lost (quick task 261019-87x plan 02)

    func testHoldWithoutLossTranscribes() {
        XCTAssertEqual(TranscriptionFailureRouter.holdEnd(audioLost: false, capturedSeconds: 0, minimumSeconds: 0.3),
                       .transcribe)
    }

    func testLostHoldWithAudioTranscribesWithNotice() {
        XCTAssertEqual(TranscriptionFailureRouter.holdEnd(audioLost: true, capturedSeconds: 12.5, minimumSeconds: 0.3),
                       .transcribeWithLossNotice)
    }

    func testLostHoldAtMinimumTranscribesWithNotice() {
        XCTAssertEqual(TranscriptionFailureRouter.holdEnd(audioLost: true, capturedSeconds: 0.3, minimumSeconds: 0.3),
                       .transcribeWithLossNotice)
    }

    func testLostHoldBelowMinimumFails() {
        XCTAssertEqual(TranscriptionFailureRouter.holdEnd(audioLost: true, capturedSeconds: 0.29, minimumSeconds: 0.3),
                       .failInterrupted)
    }

    func testLostHoldWithoutAudioFails() {
        XCTAssertEqual(TranscriptionFailureRouter.holdEnd(audioLost: true, capturedSeconds: 0, minimumSeconds: 0.3),
                       .failInterrupted)
    }

    func testTooShortAfterLossBecomesInterrupted() {
        XCTAssertEqual(TranscriptionFailureRouter.afterInputLoss(.tooShort), .inputInterrupted)
    }

    func testSilenceOnlyAfterLossBecomesInterrupted() {
        XCTAssertEqual(TranscriptionFailureRouter.afterInputLoss(.silenceOnly), .inputInterrupted)
    }

    func testNoResultAfterLossBecomesInterrupted() {
        XCTAssertEqual(TranscriptionFailureRouter.afterInputLoss(.noResult), .inputInterrupted)
    }

    func testUnexpectedLanguageAfterLossIsKept() {
        XCTAssertEqual(TranscriptionFailureRouter.afterInputLoss(.unexpectedLanguage), .unexpectedLanguage)
    }

    // MARK: - Silent gap threshold (orchestrator patch W3)

    func testEngineDownIsLostWhateverTheGap() {
        XCTAssertTrue(TranscriptionFailureRouter.audioLost(engineRunning: false, totalGapMs: 0, missingMs: 0, maxGapMs: 2000))
    }

    func testShortRestartGapKeepsAudio() {
        XCTAssertFalse(TranscriptionFailureRouter.audioLost(engineRunning: true, totalGapMs: 2000, missingMs: 0, maxGapMs: 2000))
    }

    func testLongRestartGapCountsAsLostAudio() {
        XCTAssertTrue(TranscriptionFailureRouter.audioLost(engineRunning: true, totalGapMs: 2001, missingMs: 0, maxGapMs: 2000))
    }

    // MARK: - Missing audio net (261019-87x plan 03)

    func testMissingAudioAtThresholdKeepsAudio() {
        XCTAssertFalse(TranscriptionFailureRouter.audioLost(engineRunning: true, totalGapMs: 0, missingMs: 2000, maxGapMs: 2000))
    }

    func testMissingAudioOverThresholdCountsAsLostAudio() {
        XCTAssertTrue(TranscriptionFailureRouter.audioLost(engineRunning: true, totalGapMs: 0, missingMs: 2001, maxGapMs: 2000))
    }

    func testMissingAudioUnderThresholdKeepsAudio() {
        XCTAssertFalse(TranscriptionFailureRouter.audioLost(engineRunning: true, totalGapMs: 0, missingMs: 100, maxGapMs: 2000))
    }

    func testNegativeMissingAudioKeepsAudio() {
        XCTAssertFalse(TranscriptionFailureRouter.audioLost(engineRunning: true, totalGapMs: 0, missingMs: -50, maxGapMs: 2000))
    }

    func testMissingAudioWithEngineDownIsLost() {
        XCTAssertTrue(TranscriptionFailureRouter.audioLost(engineRunning: false, totalGapMs: 0, missingMs: 0, maxGapMs: 2000))
    }

    func testGapAndMissingAudioEachDecideAlone() {
        XCTAssertTrue(TranscriptionFailureRouter.audioLost(engineRunning: true, totalGapMs: 2001, missingMs: 10, maxGapMs: 2000))
        XCTAssertTrue(TranscriptionFailureRouter.audioLost(engineRunning: true, totalGapMs: 10, missingMs: 2001, maxGapMs: 2000))
    }
}
