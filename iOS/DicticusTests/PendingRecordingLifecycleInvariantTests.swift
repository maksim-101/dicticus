import XCTest
@preconcurrency import AVFoundation
@testable import Dicticus

/// Phase 46-06's closing guard: an executable conservation property over the
/// pending-recording lifecycle as a WHOLE, not any single operation. This is the
/// executable form of 46-02-PLAN.md's assumption-delta decision — promoting the
/// pending RECORDING (not a singular pending dictation) to the durable unit — and
/// goes red the moment a future change re-collapses that promotion or adds a
/// code path that deletes durable (already-enqueued) audio on the app's own
/// initiative.
///
/// Isolation: constructs its own `HistoryService` via `makeForTesting` against a
/// per-suite temporary directory, NEVER `.shared` — this project has already
/// destroyed real user history data from a suite that skipped exactly this once
/// (see `reference_history_db_test_isolation`). `setUp()` asserts this before a
/// single record is created, not merely by convention.
///
/// One documented constraint carried over from `PendingRecordingStoreTests.swift`:
/// `PendingRecordingStore.fileURL(for:)` always resolves through
/// `AudioRecorder.recordingsDirectory()`, which is a fixed, test-host-scoped
/// directory — NOT parametrized by `makeForTesting`. The database half of this
/// suite's storage IS isolated to a temporary directory (asserted below); the raw
/// WAV files are not, and this suite tracks and force-removes every WAV it
/// creates in `tearDown()` instead, mirroring `PendingRecordingStoreTests`' own
/// established pattern. See the plan's 46-06-SUMMARY.md for the full reasoning.
@MainActor
private final class UnusedAudioRecorder: AudioRecording {
    var isRecording = false
    var onSilenceDetected: (() -> Void)?
    // Never expected to be called — every recording in this suite is seeded
    // directly via PendingRecordingStore.enqueue(), bypassing startDictation()/
    // stopDictation() entirely, since this suite's subject is the drain/lifecycle
    // machinery, not the record-session start/stop path (that is
    // AudioRecorderTests'/DictationViewModelTests' job).
    func startRecording() throws -> UUID { throw RecorderError.busy }
    func stopRecording() throws -> RecordingArtifact { throw RecorderError.notRecording }
    func cancelRecording() {}
}

/// Test double for `TranscriptionProviding` — a fixed per-call outcome queue,
/// consumed in call order (matches `store.queuedInArrivalOrder`'s createdAt-
/// ascending drain order). `errorToThrow` (used once the queue is empty) lets
/// "always fails" tests avoid pre-sizing a queue to an exact call count.
@MainActor
private final class SequencedTranscriber: TranscriptionProviding {
    private(set) var callCount = 0
    var responseQueue: [Result<DicticusTranscriptionResult, Error>] = []
    var errorToThrow: Error?

    func transcribe(wavURL: URL) async throws -> DicticusTranscriptionResult {
        callCount += 1
        if !responseQueue.isEmpty {
            switch responseQueue.removeFirst() {
            case .success(let result): return result
            case .failure(let error): throw error
            }
        }
        if let errorToThrow { throw errorToThrow }
        return DicticusTranscriptionResult(text: "unspecified", language: "en", confidence: 0.9)
    }
}

@MainActor
final class PendingRecordingLifecycleInvariantTests: XCTestCase {

    private var tempContainer: URL!
    private var historyService: HistoryService!
    private var store: PendingRecordingStore!
    private var wavDir: URL!
    private var createdWavUUIDs: [UUID] = []

    override func setUp() {
        super.setUp()
        tempContainer = FileManager.default.temporaryDirectory
            .appendingPathComponent("PendingRecordingLifecycleInvariantTests-\(UUID().uuidString)", isDirectory: true)
        let container = tempContainer!
        historyService = HistoryService.makeForTesting(containerURLProvider: { container })
        store = PendingRecordingStore.makeForTesting(historyService: historyService)
        wavDir = try? AudioRecorder.recordingsDirectory()
        createdWavUUIDs = []

        // Isolation guard — an assertion, not a comment, because the failure mode
        // being guarded against is a suite that silently starts operating on the
        // real container. The database half of this suite's storage IS
        // parametrized by makeForTesting and MUST resolve inside this suite's own
        // temporary directory; verify that before a single record is created.
        XCTAssertTrue(
            historyService.databaseFileURL.path.hasPrefix(tempContainer.path),
            "historyService.databaseFileURL (\(historyService.databaseFileURL.path)) must resolve inside " +
            "this suite's temporary directory (\(tempContainer.path)) — this project has already destroyed " +
            "real user history data from a suite that operated on the real database once."
        )
    }

    override func tearDown() {
        // The WAV recordings directory is NOT parametrized by makeForTesting (see
        // the file's top doc comment) — every WAV this suite wrote is force-
        // removed here by UUID, mirroring PendingRecordingStoreTests' tearDown.
        for uuid in createdWavUUIDs {
            if let dir = wavDir {
                try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(uuid.uuidString).wav"))
            }
        }
        for row in store.pendingRecordings {
            if let url = try? store.fileURL(for: row) {
                try? FileManager.default.removeItem(at: url)
            }
        }
        try? FileManager.default.removeItem(at: tempContainer)
        tempContainer = nil
        historyService = nil
        store = nil
        wavDir = nil
        createdWavUUIDs = []
        super.tearDown()
    }

    // MARK: - Helpers

    /// Writes a small real WAV file under the shared (test-host-scoped)
    /// recordings directory and enqueues it into `store` directly — bypassing
    /// `DictationViewModel.stopDictation()` entirely. Mirrors
    /// `PendingRecordingStoreTests.writeRealWav()`.
    @discardableResult
    private func seedRecording(duration: Double = 0.05) throws -> PendingRecording {
        let uuid = UUID()
        createdWavUUIDs.append(uuid)
        let url = wavDir.appendingPathComponent("\(uuid.uuidString).wav")
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        let writer = try RecordingFileWriter(url: url, format: format)
        let frameCount = AVAudioFrameCount(16000 * duration)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        writer.append(buffer)
        let actualDuration = writer.finalize()
        let artifact = RecordingArtifact(uuid: uuid, fileURL: url, durationSeconds: actualDuration)
        guard let row = store.enqueue(artifact) else {
            throw XCTSkip("enqueue() failed — cannot seed test fixture")
        }
        return row
    }

    private func makeViewModel() -> DictationViewModel {
        let vm = DictationViewModel()
        vm.historyService = historyService
        vm.pendingStore = store
        vm.audioRecorder = UnusedAudioRecorder()
        vm.isBackgroundedProvider = { false }
        return vm
    }

    // MARK: - Central invariant: every recording ends delivered XOR held, never both, never neither

    /// The central conservation property this suite exists to protect. Seeds a
    /// non-degenerate mixed batch (14 recordings, alternating success/failure),
    /// drives the REAL drain through
    /// `DictationViewModel.drainPendingRecordingsIfNeeded()` (not a
    /// reimplementation), then cross-checks THREE independently-derived
    /// measurements against each other: the store's remaining rows (held), the
    /// History table's entry count (delivered), and a per-recording filesystem
    /// check (the WAV must exist iff the recording is held). A corruption where a
    /// row ends up silently both delivered-and-still-held, or neither, breaks at
    /// least one of these independent cross-checks even if the other two happen
    /// to agree — a test that only asserted a total count would not catch that.
    func test_everyRecordingEndsDeliveredXorHeld_neverBothNeverNeither() async throws {
        let vm = makeViewModel()
        let batchSize = 14
        var seeded: [PendingRecording] = []
        for i in 0..<batchSize {
            seeded.append(try seedRecording())
            if i < batchSize - 1 { try? await Task.sleep(for: .seconds(0.005)) }  // deterministic createdAt ordering
        }
        XCTAssertEqual(store.pendingRecordings.count, batchSize, "Precondition: all seeded rows present")

        // Precompute each recording's file URL BEFORE the drain — a delivered
        // recording's row (and thus fileURL(for:) lookup) is gone by definition.
        var fileURLByUUID: [UUID: URL] = [:]
        for row in seeded { fileURLByUUID[row.uuid] = try store.fileURL(for: row) }

        // Alternate succeed/fail so the mix is not degenerate. Failures use
        // .noResult — a HOLD-class disposition (see
        // DictationViewModel.failureDisposition(for:)) — deliberately not
        // .tooShort/.silenceOnly, which DISCARD and would introduce a third
        // outcome outside this test's two-state scope (46-03's own
        // testTooShortOutcomeDiscardsRowAndFile already covers that path).
        let transcriber = SequencedTranscriber()
        for i in 0..<batchSize {
            if i % 2 == 0 {
                transcriber.responseQueue.append(.success(
                    DicticusTranscriptionResult(text: "spoken content \(i)", language: "en", confidence: 0.9)))
            } else {
                transcriber.responseQueue.append(.failure(TranscriptionError.noResult))
            }
        }
        vm.transcriptionService = transcriber

        await vm.drainPendingRecordingsIfNeeded()

        XCTAssertEqual(transcriber.callCount, batchSize, "Every seeded recording must have been attempted exactly once")

        // Measurement 1: the store's remaining rows (held).
        let heldRows = store.pendingRecordings
        let heldUUIDs = Set(heldRows.map(\.uuid))
        XCTAssertEqual(heldRows.count, batchSize / 2, "Exactly the odd-indexed (failing) half must remain held")
        XCTAssertTrue(heldRows.allSatisfy { $0.status == PendingRecordingStatus.failed.rawValue },
                     "Every held row must be status .failed — not stuck .transcribing, not silently .queued")

        // Measurement 2: the History table's entry count (delivered) — an
        // INDEPENDENT measurement from the store's row count, not derived from it.
        XCTAssertEqual(historyService.entries.count, batchSize / 2,
                       "Delivered count, measured independently via History entries, must equal N - heldCount")

        // Measurement 3: partition identity — union/intersection over the two sets.
        let allUUIDs = Set(seeded.map(\.uuid))
        let deliveredUUIDs = allUUIDs.subtracting(heldUUIDs)
        XCTAssertEqual(deliveredUUIDs.count + heldUUIDs.count, batchSize,
                       "Delivered and held must partition the whole batch — no recording lost or double-counted")
        XCTAssertTrue(deliveredUUIDs.isDisjoint(with: heldUUIDs), "No recording may be both delivered and held")
        XCTAssertEqual(deliveredUUIDs.union(heldUUIDs), allUUIDs, "No recording may be neither delivered nor held")

        // Measurement 4 (the filesystem, independent of both the store and
        // History): asserted separately per half so a failure names WHICH half
        // broke, not just that some count disagreed somewhere.
        for uuid in deliveredUUIDs {
            let url = try XCTUnwrap(fileURLByUUID[uuid])
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path),
                           "A delivered recording must not have left its WAV behind on disk: \(uuid)")
        }
        for uuid in heldUUIDs {
            let url = try XCTUnwrap(fileURLByUUID[uuid])
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path),
                          "A held recording must not have lost its WAV from disk: \(uuid)")
        }

        // Cleanup — delivered rows already removed both bytes+row; held rows are
        // cleared explicitly rather than left for the next test's tearDown to race.
        for row in store.pendingRecordings { store.clear(row) }
    }

    // MARK: - No self-initiated deletion: only an explicit user clear reduces the held set

    /// Regression target: once a recording is held (`.failed`), repeated
    /// automatic drain attempts must never reduce the held count or touch its
    /// bytes on their own initiative — D-10's whole point is that nothing the
    /// user said is discarded without their say-so.
    ///
    /// RED-capability, empirically verified (not merely reasoned about): the
    /// `.hold` branch of `DictationViewModel.drainQueue`'s catch clause was
    /// temporarily changed from `pendingStore.markFailed(row, reason:)` to
    /// `pendingStore.delete(row)`, this test was re-run and failed (held count
    /// dropped from 5 to 0 after the very first automatic pass, instead of
    /// staying at 5), then the change was reverted and the suite re-confirmed
    /// green. See 46-06-SUMMARY.md for the exact failure output.
    func test_repeatedDrainOverFailedQueueNeverReducesHeldCount() async throws {
        let vm = makeViewModel()
        let failCount = 5
        var seeded: [PendingRecording] = []
        for i in 0..<failCount {
            seeded.append(try seedRecording())
            if i < failCount - 1 { try? await Task.sleep(for: .seconds(0.005)) }
        }
        var fileURLByUUID: [UUID: URL] = [:]
        for row in seeded { fileURLByUUID[row.uuid] = try store.fileURL(for: row) }

        // First pass: every row transitions .queued -> .failed. This is setup —
        // the property under test starts once the store contains ONLY failed
        // recordings, matching the plan's stated precondition.
        let transcriber = SequencedTranscriber()
        transcriber.errorToThrow = TranscriptionError.noResult
        vm.transcriptionService = transcriber
        await vm.drainPendingRecordingsIfNeeded()
        XCTAssertEqual(store.pendingRecordings.count, failCount, "Precondition: all rows held after the first pass")
        XCTAssertTrue(store.pendingRecordings.allSatisfy { $0.status == PendingRecordingStatus.failed.rawValue })

        // Repeated drains (at least 3) over a store containing only failed
        // recordings, transcriber still failing.
        for pass in 1...3 {
            await vm.drainPendingRecordingsIfNeeded()
            XCTAssertEqual(store.pendingRecordings.count, failCount,
                           "Held count must be unchanged after automatic drain pass \(pass)")
            for (uuid, url) in fileURLByUUID {
                XCTAssertTrue(FileManager.default.fileExists(atPath: url.path),
                              "WAV for \(uuid) must still be present after automatic drain pass \(pass)")
            }
        }

        // Cleanup
        for row in store.pendingRecordings { store.clear(row) }
    }

    /// Companion to the above: an explicit user clear IS the one operation that
    /// reduces the held set — by exactly one, for exactly the row cleared, with
    /// every other held row untouched.
    func test_explicitClearIsTheOnlyOperationThatReducesHeldCount() async throws {
        let vm = makeViewModel()
        let failCount = 4
        for i in 0..<failCount {
            _ = try seedRecording()
            if i < failCount - 1 { try? await Task.sleep(for: .seconds(0.005)) }
        }
        let transcriber = SequencedTranscriber()
        transcriber.errorToThrow = TranscriptionError.noResult
        vm.transcriptionService = transcriber
        await vm.drainPendingRecordingsIfNeeded()
        XCTAssertEqual(store.pendingRecordings.count, failCount, "Precondition: all rows held")

        let toClear = try XCTUnwrap(store.pendingRecordings.first)
        let clearedURL = try store.fileURL(for: toClear)
        let survivingUUIDs = Set(store.pendingRecordings.dropFirst().map(\.uuid))

        store.clear(toClear)

        XCTAssertEqual(store.pendingRecordings.count, failCount - 1, "Clear must reduce the held count by exactly one")
        XCTAssertFalse(FileManager.default.fileExists(atPath: clearedURL.path),
                       "Clear must remove the cleared recording's WAV")
        XCTAssertEqual(Set(store.pendingRecordings.map(\.uuid)), survivingUUIDs,
                       "Every OTHER held recording must be untouched by the clear")
        for row in store.pendingRecordings {
            let url = try store.fileURL(for: row)
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Untouched rows must keep their WAV")
        }

        // Cleanup
        for row in store.pendingRecordings { store.clear(row) }
    }

    // MARK: - No cap (D-09)

    /// The queue must accept an arbitrary number of recordings with no refusal
    /// and no silent eviction, asserted at a batch size well beyond any realistic
    /// session (200), not argued from the absence of a cap constant.
    func test_queueAcceptsBatchFarBeyondAnyRealisticSessionWithNoRefusalOrEviction() throws {
        let batchSize = 200
        for _ in 0..<batchSize {
            // Fraction-of-a-second WAVs — count/refusal is the assertion, not audio content.
            _ = try seedRecording(duration: 0.01)
        }
        XCTAssertEqual(store.pendingRecordings.count, batchSize,
                       "All \(batchSize) recordings must be present — no refusal (D-09) and no silent eviction")
        XCTAssertEqual(Set(store.pendingRecordings.map(\.uuid)).count, batchSize,
                       "Every recording must be individually present — no two collapsed into one")

        // Cleanup — 200 real WAVs on the shared test-host directory.
        for row in store.pendingRecordings { store.delete(row) }
    }

    // MARK: - Retry preserves (D-11)

    /// A retry of a failed recording that fails again must leave it still held,
    /// still on disk, with its retry count strictly increased — retrying is not
    /// itself a way to lose the recording.
    func test_retryOfAStillFailingRecordingPreservesHoldAndIncrementsRetryCount() async throws {
        let vm = makeViewModel()
        _ = try seedRecording()
        let failingTranscriber = SequencedTranscriber()
        failingTranscriber.errorToThrow = TranscriptionError.noResult
        vm.transcriptionService = failingTranscriber
        await vm.drainPendingRecordingsIfNeeded()

        let failedRow = try XCTUnwrap(store.pendingRecordings.first)
        XCTAssertEqual(failedRow.status, PendingRecordingStatus.failed.rawValue, "Precondition: row is held")
        let retryCountBefore = failedRow.retryCount
        let fileURL = try store.fileURL(for: failedRow)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), "Precondition: WAV present")

        let stillFailingTranscriber = SequencedTranscriber()
        stillFailingTranscriber.errorToThrow = TranscriptionError.noResult
        vm.transcriptionService = stillFailingTranscriber

        await vm.retryPendingRecording(failedRow)

        let afterRetry = try XCTUnwrap(store.pendingRecordings.first(where: { $0.uuid == failedRow.uuid }))
        XCTAssertEqual(afterRetry.status, PendingRecordingStatus.failed.rawValue, "A retry that fails again must still be held")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), "A retry that fails again must not lose the WAV")
        XCTAssertGreaterThan(afterRetry.retryCount, retryCountBefore, "retryCount must strictly increase on a failed retry attempt")

        // Cleanup
        store.clear(afterRetry)
    }
}
