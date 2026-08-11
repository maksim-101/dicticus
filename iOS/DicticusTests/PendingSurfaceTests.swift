import XCTest
@preconcurrency import AVFoundation
@testable import Dicticus

/// Phase 46-05: exact-string display-contract tests for the pending-recordings UI
/// surface. `durationLabel`/`statusLabel` (Task 1) and `PendingQueueChip.label(for:)`/
/// `PendingRecordingStore.pendingCount` (Task 2) are pure functions precisely so this
/// contract is machine-checked rather than eyeballed.
///
/// `@MainActor`: `failedExplanationText(for:)` (round 3) reads
/// `PendingRecordingStore`'s static failure-copy constants, which are
/// MainActor-isolated because `PendingRecordingStore` itself is — this class needs
/// the same isolation to call them.
@MainActor
final class PendingSurfaceTests: XCTestCase {

    // MARK: - PendingRecordingRow.durationLabel

    func testDurationLabelNilReturnsPlaceholder() {
        XCTAssertEqual(PendingRecordingRow.durationLabel(nil), "--:--")
    }

    func testDurationLabelZeroIsDistinguishableFromNil() {
        let zero = PendingRecordingRow.durationLabel(0)
        let nilLabel = PendingRecordingRow.durationLabel(nil)
        XCTAssertNotEqual(zero, nilLabel, "a real zero-length recording and an unknown duration must be distinguishable")
        XCTAssertEqual(zero, "0:00")
    }

    func testDurationLabelKnownValues() {
        XCTAssertEqual(PendingRecordingRow.durationLabel(42), "0:42")
        XCTAssertEqual(PendingRecordingRow.durationLabel(67), "1:07")
    }

    func testDurationLabelFractionalSecond() {
        // Truncates to whole seconds — a fractional value still renders a valid m:ss.
        XCTAssertEqual(PendingRecordingRow.durationLabel(0.7), "0:00")
    }

    func testDurationLabelExactlySixtySeconds() {
        XCTAssertEqual(PendingRecordingRow.durationLabel(60), "1:00")
    }

    func testDurationLabelOverAnHour() {
        // 62 minutes, 5 seconds — minutes are not clamped to 59.
        XCTAssertEqual(PendingRecordingRow.durationLabel(3725), "62:05")
    }

    func testDurationLabelInfinityReturnsPlaceholder() {
        XCTAssertEqual(PendingRecordingRow.durationLabel(.infinity), "--:--")
    }

    func testDurationLabelNegativeReturnsPlaceholder() {
        XCTAssertEqual(PendingRecordingRow.durationLabel(-5), "--:--")
    }

    // MARK: - PendingRecordingRow.statusLabel

    func testStatusLabelQueued() {
        XCTAssertEqual(PendingRecordingRow.statusLabel(for: .queued), "Waiting for model")
    }

    func testStatusLabelTranscribing() {
        XCTAssertEqual(PendingRecordingRow.statusLabel(for: .transcribing), "Transcribing\u{2026}")
    }

    func testStatusLabelFailed() {
        XCTAssertEqual(PendingRecordingRow.statusLabel(for: .failed), "Failed")
    }

    // MARK: - PendingRecordingRow.failedExplanationText (2026-08-11 round 3)

    private func makeRecording(durationSeconds: Double?, retryCount: Int) -> PendingRecording {
        PendingRecording(
            id: 1, uuid: UUID(), fileName: "x.wav", createdAt: Date(),
            status: PendingRecordingStatus.failed.rawValue, durationSeconds: durationSeconds,
            retryCount: retryCount, failureReason: nil
        )
    }

    func testFailedExplanationTextStillRetryableIsGenericCopy() {
        let row = makeRecording(durationSeconds: 5, retryCount: 1)
        XCTAssertTrue(row.isRetryable, "Precondition: one prior failure still leaves one honest retry")
        XCTAssertEqual(PendingRecordingRow.failedExplanationText(for: row),
                       "Couldn't transcribe — tap Retry, or we'll try again automatically once the model reloads.")
    }

    func testFailedExplanationTextStructurallyUnrecoverableIsHonestCopy() {
        let row = makeRecording(durationSeconds: nil, retryCount: 0)
        XCTAssertFalse(row.isRetryable)
        XCTAssertEqual(PendingRecordingRow.failedExplanationText(for: row), PendingRecordingStore.unrecoverableFailureReason)
    }

    func testFailedExplanationTextRetriesExhaustedIsDistinctHonestCopy() {
        let row = makeRecording(durationSeconds: 5.8, retryCount: 2)
        XCTAssertFalse(row.isRetryable)
        XCTAssertEqual(PendingRecordingRow.failedExplanationText(for: row), PendingRecordingStore.retriesExhaustedFailureReason)
        XCTAssertNotEqual(PendingRecordingStore.retriesExhaustedFailureReason, PendingRecordingStore.unrecoverableFailureReason,
                          "The two unrecoverable cases must read differently — one is a save failure, the other is a real, honestly-attempted transcription failure")
    }

    // MARK: - PendingRecording.isRetryable (2026-08-11 round 3: one honest retry)

    func testIsRetryableTrueForFreshStructurallySoundRow() {
        XCTAssertTrue(makeRecording(durationSeconds: 5, retryCount: 0).isRetryable)
    }

    func testIsRetryableTrueAfterExactlyOnePriorFailure() {
        XCTAssertTrue(makeRecording(durationSeconds: 5, retryCount: 1).isRetryable,
                      "One prior failure (the initial automatic attempt) must still allow one honest user-initiated retry")
    }

    func testIsRetryableFalseAfterTwoPriorFailures() {
        XCTAssertFalse(makeRecording(durationSeconds: 5, retryCount: 2).isRetryable,
                       "A structurally-sound row that has already failed twice must stop offering Retry")
    }

    func testIsRetryableFalseForStructurallyUnrecoverableRegardlessOfRetryCount() {
        XCTAssertFalse(makeRecording(durationSeconds: nil, retryCount: 0).isRetryable)
    }

    // MARK: - PendingQueueChip.label(for:)

    func testChipLabelZeroReturnsNilNotRendered() {
        XCTAssertNil(PendingQueueChip.label(for: 0), "count zero must mean not rendered, not an empty-string render")
    }

    func testChipLabelOneIsSingularSentence() {
        XCTAssertEqual(PendingQueueChip.label(for: 1), "1 recording waiting to transcribe")
    }

    func testChipLabelPluralIncludesCount() {
        XCTAssertEqual(PendingQueueChip.label(for: 4), "4 recordings waiting to transcribe")
    }

    func testChipLabelLargeNumber() {
        XCTAssertEqual(PendingQueueChip.label(for: 42), "42 recordings waiting to transcribe")
    }
}

/// The locked count definition (PendingRecordingStore.pendingCount = queued +
/// transcribing + failed) needs a real store with rows in all three statuses, so this
/// is a separate isolated-store test case rather than living alongside the pure-
/// function tests above. Constructs its own `HistoryService`/`PendingRecordingStore`
/// via `makeForTesting` against a temporary directory — no test names either
/// production singleton (see `PendingRecordingStoreTests`'s established convention).
@MainActor
final class PendingSurfaceCountTests: XCTestCase {

    private var tempContainer: URL!
    private var historyService: HistoryService!
    private var store: PendingRecordingStore!
    private var wavDir: URL!

    override func setUp() {
        super.setUp()
        tempContainer = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PendingSurfaceCountTests-\(UUID().uuidString)", isDirectory: true)
        let container = tempContainer!
        historyService = HistoryService.makeForTesting(containerURLProvider: { container })
        store = PendingRecordingStore.makeForTesting(historyService: historyService)
        wavDir = try? AudioRecorder.recordingsDirectory()
    }

    override func tearDown() {
        for row in store.pendingRecordings {
            if let url = try? store.fileURL(for: row) {
                try? FileManager.default.removeItem(at: url)
            }
        }
        try? FileManager.default.removeItem(at: tempContainer)
        tempContainer = nil
        historyService = nil
        store = nil
        super.tearDown()
    }

    @discardableResult
    private func writeRealWav(duration: Double = 1.0) throws -> RecordingArtifact {
        let uuid = UUID()
        let url = wavDir.appendingPathComponent("\(uuid.uuidString).wav")
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        let writer = try RecordingFileWriter(url: url, format: format)
        let frameCount = AVAudioFrameCount(16000 * duration)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        writer.append(buffer)
        let actualDuration = writer.finalize()
        return RecordingArtifact(uuid: uuid, fileURL: url, durationSeconds: actualDuration)
    }

    /// Specifically covers the mid-flight case the UI-SPEC calls out by name: the
    /// last queued item starting to transcribe must not make the chip/badge count
    /// drop, because a bare `queued + failed` count would go from 3 to 2 the instant
    /// the transcribing row's status flips — reading as "the app lost it".
    func testPendingCountCoversQueuedTranscribingAndFailed() throws {
        let queuedArtifact = try writeRealWav()
        let transcribingArtifact = try writeRealWav()
        let failedArtifact = try writeRealWav()

        guard store.enqueue(queuedArtifact) != nil,
              let transcribingRow = store.enqueue(transcribingArtifact),
              let failedRow = store.enqueue(failedArtifact) else {
            XCTFail("enqueue() must succeed for all three artifacts")
            return
        }

        store.markTranscribing(transcribingRow)
        store.markFailed(failedRow, reason: "test failure")

        XCTAssertEqual(store.pendingCount, 3)
    }
}
