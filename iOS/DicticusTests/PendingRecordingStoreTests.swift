import XCTest
@preconcurrency import AVFoundation
@testable import Dicticus

/// Phase 46-02: asserts the durable pending-recording queue — the migration really
/// created the table, arrival order is preserved, and delete() really removes bytes
/// (not just the row). Every test constructs its own isolated `HistoryService` via
/// `makeForTesting(containerURLProvider:)` against a temporary directory — this
/// project has already had a test run write to and wipe the real user History
/// database, and the standing guard against a repeat is that no test names either
/// production singleton.
@MainActor
final class PendingRecordingStoreTests: XCTestCase {

    private var tempContainer: URL!
    private var historyService: HistoryService!
    private var store: PendingRecordingStore!
    private var wavDir: URL!

    override func setUp() {
        super.setUp()
        tempContainer = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PendingRecordingStoreTests-\(UUID().uuidString)", isDirectory: true)
        let container = tempContainer!
        historyService = HistoryService.makeForTesting(containerURLProvider: { container })
        store = PendingRecordingStore.makeForTesting(historyService: historyService)
        wavDir = try? AudioRecorder.recordingsDirectory()

        // recordingsDirectory() is a real, test-host-scoped shared path (not a
        // per-test temp directory) — it's also read by AudioRecorderTests,
        // PendingSurfaceTests, PendingRecordingLifecycleInvariantTests, and
        // DictationViewModelTests. A sibling class can leave a `.wav` there that
        // it never enqueue()d, and recoverOrphanedRecordings() correctly counts
        // any such file as an orphan — so this class must start from a genuinely
        // empty directory regardless of what a predecessor left behind. Sweep
        // CONTENTS only: never remove/recreate wavDir itself, never widen to a
        // parent directory.
        if let dir = wavDir,
           let contents = try? FileManager.default.contentsOfDirectory(
               at: dir, includingPropertiesForKeys: nil, options: []) {
            for url in contents {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    override func tearDown() {
        // Hygiene: remove any WAVs a test enqueued but did not itself delete —
        // recordingsDirectory() is a real (test-host-scoped) shared path, not a
        // per-test temp directory, so leftover files would otherwise accumulate.
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

    // MARK: - Helpers

    /// Writes a small real WAV file under the shared recordings directory (mirrors
    /// what AudioRecorder produces) and returns a matching RecordingArtifact.
    @discardableResult
    private func writeRealWav(duration: Double = 1.0) throws -> RecordingArtifact {
        let uuid = UUID()
        let url = wavDir.appendingPathComponent("\(uuid.uuidString).wav")
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        let writer = try RecordingFileWriter(url: url, format: format)
        let frameCount: AVAudioFrameCount = AVAudioFrameCount(16000 * duration)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        writer.append(buffer)
        let actualDuration = writer.finalize()
        return RecordingArtifact(uuid: uuid, fileURL: url, durationSeconds: actualDuration)
    }

    // MARK: - Migration created the table

    /// Regression target: if `v3-pending-recordings` failed to register (or the
    /// migrator silently no-ops it), enqueue()/load() would throw or return an
    /// empty result — this test would fail rather than pass vacuously.
    func testMigrationCreatedTableInsertAndReadBack() throws {
        let artifact = try writeRealWav()
        let row = store.enqueue(artifact)
        XCTAssertNotNil(row, "enqueue() must succeed against a migrated table")
        XCTAssertEqual(store.pendingRecordings.count, 1)
        XCTAssertEqual(store.pendingRecordings.first?.uuid, artifact.uuid)
    }

    // MARK: - Arrival order (D-09's future drain order)

    /// Regression target: if `load()` ordered by `createdAt DESC` (or by insertion
    /// rowid in reverse), this would read back [c, b, a] instead of [a, b, c].
    func testEnqueueThenLoadReturnsArrivalOrder() throws {
        // A tiny synchronous sleep between enqueues keeps this deterministic —
        // `createdAt` is a `Date()` timestamp, and back-to-back calls on a fast
        // host could otherwise land on the same tick.
        let a = try writeRealWav()
        Thread.sleep(forTimeInterval: 0.01)
        let b = try writeRealWav()
        Thread.sleep(forTimeInterval: 0.01)
        let c = try writeRealWav()

        store.enqueue(a)
        store.enqueue(b)
        store.enqueue(c)

        XCTAssertEqual(store.pendingRecordings.map(\.uuid), [a.uuid, b.uuid, c.uuid],
                       "pendingRecordings must be ordered createdAt ascending (arrival order)")
    }

    // MARK: - delete() removes bytes, not just the row

    /// D-02's whole point is that the audio is really gone — assert against the
    /// filesystem, not merely that the row count dropped. A delete() that only
    /// removed the database row (leaving the WAV orphaned on disk) would pass a
    /// row-count-only check but fail this one.
    func testDeleteRemovesBothRowAndBytes() throws {
        let artifact = try writeRealWav()
        guard let row = store.enqueue(artifact) else {
            XCTFail("enqueue() must succeed")
            return
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifact.fileURL.path),
                      "Precondition: WAV must exist before delete")

        store.delete(row)

        XCTAssertEqual(store.pendingRecordings.count, 0, "Row must be gone after delete()")
        XCTAssertFalse(FileManager.default.fileExists(atPath: artifact.fileURL.path),
                       "delete() must remove the WAV bytes from disk, not just the row")
    }

    /// delete() must not throw or crash when the file is already gone (e.g. a
    /// concurrent cleanup already removed it) — it should still remove the row.
    func testDeleteToleratesAlreadyMissingFile() throws {
        let artifact = try writeRealWav()
        guard let row = store.enqueue(artifact) else {
            XCTFail("enqueue() must succeed")
            return
        }
        try FileManager.default.removeItem(at: artifact.fileURL)

        store.delete(row)

        XCTAssertEqual(store.pendingRecordings.count, 0,
                       "delete() must still remove the row when the file is already missing")
    }

    // MARK: - fileURL(for:) composes from a bare filename (T-46-05)

    func testFileURLComposesFromBareFileName() throws {
        let artifact = try writeRealWav()
        guard let row = store.enqueue(artifact) else {
            XCTFail("enqueue() must succeed")
            return
        }
        let resolved = try store.fileURL(for: row)
        XCTAssertEqual(resolved.path, artifact.fileURL.path)
        // Clean up the WAV this test wrote directly (not enqueued through delete()).
        try? FileManager.default.removeItem(at: artifact.fileURL)
    }

    // MARK: - Phase 46-03: recoverOrphanedRecordings() (D-01 relaunch recovery)

    /// Writes an unfinalized mid-write WAV under `wavDir`, matching device evidence
    /// (`46-DEVICE-TEST-PROCEDURE.md` Section A, 2026-08-10, outcome (b)): captures
    /// the file's on-disk bytes WHILE the writer is still alive and before
    /// `finalize()` ever runs, exactly what a killed-mid-recording process leaves
    /// behind — verified separately (off-device, macOS AVFoundation) to reproduce
    /// the identical `AVAudioFile(forReading:).length == 0` symptom the device
    /// showed. Returns the UUID the orphan is named after.
    @discardableResult
    private func writeUnfinalizedOrphanWav(seconds: Double = 1.0) throws -> UUID {
        let uuid = UUID()
        let url = wavDir.appendingPathComponent("\(uuid.uuidString).wav")
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        let writer = try RecordingFileWriter(url: url, format: format)
        let frameCount = AVAudioFrameCount(16000 * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        writer.append(buffer)
        let midWriteBytes = try Data(contentsOf: url)
        writer.discard()  // removes the file + releases the live AVAudioFile cleanly
        try midWriteBytes.write(to: url)  // restore the captured never-finalized snapshot
        return uuid
    }

    /// Regression target: a `.wav` file with no matching row must become a queued
    /// row on scan — this is D-01's entire jetsam-recovery story.
    func testRecoverOrphanedRecordingsQueuesUntrackedWav() throws {
        let artifact = try writeRealWav()  // written directly, never enqueue()d — simulates process death before enqueue() ran
        store.recoverOrphanedRecordings()

        XCTAssertEqual(store.pendingRecordings.count, 1)
        let row = try XCTUnwrap(store.pendingRecordings.first)
        XCTAssertEqual(row.uuid, artifact.uuid)
        XCTAssertEqual(row.status, PendingRecordingStatus.queued.rawValue)
    }

    /// 2026-08-11 correction: a properly-finalized recording AT THE APP'S OWN
    /// `minimumDurationSeconds` FLOOR (0.3s) must still classify as recoverable.
    /// `AVAudioFile(forWriting:)`'s fixed ~4KB container overhead is a LARGER
    /// fraction of a short clip's total bytes — before the fix, this exact case
    /// (empirically measured ~18% header/byte-size disagreement) tripped the
    /// cross-check's 5% threshold and silently marked a perfectly valid short
    /// recording as unrecoverable, hiding its Retry button for no real reason.
    func testRecoverOrphanedRecordingsShortValidWavIsRecoverable() throws {
        let artifact = try writeRealWav(duration: 0.3)
        store.recoverOrphanedRecordings()

        let row = try XCTUnwrap(store.pendingRecordings.first(where: { $0.uuid == artifact.uuid }))
        XCTAssertEqual(row.status, PendingRecordingStatus.queued.rawValue,
                       "A short but properly-finalized recording must not be misclassified as unrecoverable")
        XCTAssertTrue(row.isRetryable)
        XCTAssertNotNil(row.durationSeconds)
        if let duration = row.durationSeconds {
            XCTAssertEqual(duration, 0.3, accuracy: 0.01)
        }
    }

    /// Regression target: a row whose WAV was never finalized must report `nil` for
    /// `durationSeconds` — NOT `0`. `AVAudioFile(forReading:)` does not throw for
    /// this class of file; it opens successfully and silently reports zero frames
    /// even though real audio bytes are present. Trusting that zero at face value
    /// would misreport every jetsammed recording as an empty clip.
    func testRecoverOrphanedRecordingsUnfinalizedFileYieldsNilDurationNotZero() throws {
        let uuid = try writeUnfinalizedOrphanWav(seconds: 1.0)
        store.recoverOrphanedRecordings()

        XCTAssertEqual(store.pendingRecordings.count, 1)
        let row = try XCTUnwrap(store.pendingRecordings.first(where: { $0.uuid == uuid }))
        XCTAssertNil(row.durationSeconds,
                     "An unfinalized (killed-mid-write) recording must report nil duration, never 0")
    }

    /// 2026-08-11 device UAT fix: an unfinalized orphan must be inserted ALREADY
    /// `.failed`, honestly, once — not `.queued` (which would show "Waiting for
    /// model" and offer Retry on a WAV empirically confirmed to always fail the
    /// transcriber's file read, the exact "transcribing… then back to failed, no
    /// change" trap the coordinator's device report described).
    func testRecoverOrphanedRecordingsUnfinalizedFileIsInsertedAlreadyFailed() throws {
        let uuid = try writeUnfinalizedOrphanWav(seconds: 1.0)
        store.recoverOrphanedRecordings()

        let row = try XCTUnwrap(store.pendingRecordings.first(where: { $0.uuid == uuid }))
        XCTAssertEqual(row.status, PendingRecordingStatus.failed.rawValue,
                       "An unrecoverable orphan must never pass through .queued — it can never succeed")
        XCTAssertEqual(row.failureReason, PendingRecordingStore.unrecoverableFailureReason)
        XCTAssertFalse(row.isRetryable)
    }

    /// A normally-enqueued row (real, non-optional duration from a live recording)
    /// must remain retryable — this fix must not make EVERY failed row un-retryable,
    /// only the specific class recovered from an untrustworthy header.
    func testNormallyEnqueuedRowIsRetryable() throws {
        let artifact = try writeRealWav()
        let row = try XCTUnwrap(store.enqueue(artifact))
        XCTAssertTrue(row.isRetryable)
    }

    /// Regression target: a row whose file has vanished from disk becomes `.failed`
    /// with a reason, and the row itself is never deleted by the scan — deleting a
    /// row for a missing file would be the scan silently discarding evidence that
    /// something was recorded and lost, which D-10 forbids even here.
    func testRecoverOrphanedRecordingsMarksMissingFileAsFailed() throws {
        let artifact = try writeRealWav()
        guard let row = store.enqueue(artifact) else {
            XCTFail("enqueue() must succeed")
            return
        }
        try FileManager.default.removeItem(at: artifact.fileURL)  // simulate the file vanishing without the row being updated

        store.recoverOrphanedRecordings()

        XCTAssertEqual(store.pendingRecordings.count, 1, "The row must still exist — never deleted by the scan")
        let updated = try XCTUnwrap(store.pendingRecordings.first(where: { $0.uuid == row.uuid }))
        XCTAssertEqual(updated.status, PendingRecordingStatus.failed.rawValue)
        XCTAssertNotNil(updated.failureReason)
    }

    /// Regression target: a row left `.transcribing` by a process killed mid-
    /// transcription must reset to `.queued`, not remain stranded forever.
    func testRecoverOrphanedRecordingsResetsStrandedTranscribingRow() throws {
        let artifact = try writeRealWav()
        guard let row = store.enqueue(artifact) else {
            XCTFail("enqueue() must succeed")
            return
        }
        store.markTranscribing(row)
        XCTAssertEqual(store.pendingRecordings.first?.status, PendingRecordingStatus.transcribing.rawValue,
                       "Precondition: row is stranded in .transcribing")

        store.recoverOrphanedRecordings()

        let updated = try XCTUnwrap(store.pendingRecordings.first(where: { $0.uuid == row.uuid }))
        XCTAssertEqual(updated.status, PendingRecordingStatus.queued.rawValue,
                       "A stranded .transcribing row must reset to .queued, not stay stuck")

        // Cleanup
        store.delete(updated)
    }

    /// T-46-05: a symlink, a non-`.wav` file, and a `.wav` file whose basename does
    /// not parse as a UUID must all be skipped without a row and without throwing —
    /// the scan must not follow or trust anything it did not itself write.
    func testRecoverOrphanedRecordingsSkipsForeignAndSymlinkEntries() throws {
        // A real, valid orphan — the positive control, so a bug that skips
        // EVERYTHING (rather than just the foreign entries) would still be caught.
        let goodArtifact = try writeRealWav()

        // Non-UUID-named .wav file.
        let foreignWavURL = wavDir.appendingPathComponent("not-a-uuid.wav")
        try Data("not a real wav".utf8).write(to: foreignWavURL)

        // Non-.wav file, otherwise UUID-named (so only the extension check should reject it).
        let nonWavURL = wavDir.appendingPathComponent("\(UUID().uuidString).txt")
        try Data("hello".utf8).write(to: nonWavURL)

        // Symlink pointing at the real good WAV — must be skipped even though its
        // target is legitimate; only the entry itself is evaluated.
        let symlinkURL = wavDir.appendingPathComponent("\(UUID().uuidString).wav")
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: goodArtifact.fileURL)

        store.recoverOrphanedRecordings()

        XCTAssertEqual(store.pendingRecordings.count, 1,
                       "Only the one real orphan must produce a row — symlink/foreign/non-UUID entries must not")
        XCTAssertEqual(store.pendingRecordings.first?.uuid, goodArtifact.uuid)

        // Cleanup
        try? FileManager.default.removeItem(at: foreignWavURL)
        try? FileManager.default.removeItem(at: nonWavURL)
        try? FileManager.default.removeItem(at: symlinkURL)
    }

    /// Running the scan twice must produce identical rows — no duplicate inserts,
    /// no re-processing of rows the first pass already reconciled.
    func testRecoverOrphanedRecordingsIsIdempotent() throws {
        let artifact = try writeRealWav()

        store.recoverOrphanedRecordings()
        let firstPassUUIDs = Set(store.pendingRecordings.map(\.uuid))
        store.recoverOrphanedRecordings()
        let secondPassUUIDs = Set(store.pendingRecordings.map(\.uuid))

        XCTAssertEqual(store.pendingRecordings.count, 1, "Second pass must not duplicate the row")
        XCTAssertEqual(firstPassUUIDs, secondPassUUIDs)
        XCTAssertTrue(firstPassUUIDs.contains(artifact.uuid))
    }

    // MARK: - Phase 46-03: clear()/markFailed() (D-10 hold + user-initiated delete)

    /// `clear(_:)` (the user-initiated D-10 delete) must remove both the row and the
    /// bytes — identical contract to `delete(_:)`, distinguished by name/log line only.
    func testClearRemovesRowAndBytes() throws {
        let artifact = try writeRealWav()
        guard let row = store.enqueue(artifact) else {
            XCTFail("enqueue() must succeed")
            return
        }

        store.clear(row)

        XCTAssertEqual(store.pendingRecordings.count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: artifact.fileURL.path),
                       "clear() must remove the WAV bytes, not just the row")
    }

    /// Regression target for fix 46-06/3. If `FileManager.removeItem` genuinely
    /// fails (e.g. permission denied) AND the file still exists afterward, the row
    /// must NOT be deleted — deleting it anyway is a latent resurrection bug:
    /// `recoverOrphanedRecordings()` on the next cold launch would find that
    /// orphaned WAV with no matching row and silently re-insert it, making a
    /// "successful" clear reappear later as if nothing happened.
    ///
    /// Forces a REAL `unlink()` failure via `chflags`-style `isUserImmutable`
    /// (`NSURLIsUserImmutableKey`) on just this one file — not a directory-wide
    /// permission change, which would risk contending with any other concurrently
    /// running test/process sharing the same test-host-scoped recordings
    /// directory.
    func testClearDoesNotDeleteRowWhenFileRemovalFails() throws {
        let artifact = try writeRealWav()
        guard let row = store.enqueue(artifact) else {
            XCTFail("enqueue() must succeed")
            return
        }

        var url = artifact.fileURL
        var immutableValues = URLResourceValues()
        immutableValues.isUserImmutable = true
        try url.setResourceValues(immutableValues)
        defer {
            var mutableValues = URLResourceValues()
            mutableValues.isUserImmutable = false
            try? url.setResourceValues(mutableValues)
            try? FileManager.default.removeItem(at: url)
        }

        store.clear(row)

        XCTAssertEqual(store.pendingRecordings.count, 1,
                       "The row must survive when the WAV removal genuinely failed — " +
                       "deleting it anyway would let recoverOrphanedRecordings() resurrect it later")
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifact.fileURL.path),
                     "Precondition check: the WAV must still exist (removal genuinely failed, not a no-op)")
    }

    /// `markFailed(_:reason:)` must retain the WAV bytes — D-10's hold. Only
    /// `delete(_:)`/`clear(_:)` ever remove audio.
    func testMarkFailedRetainsBytes() throws {
        let artifact = try writeRealWav()
        guard let row = store.enqueue(artifact) else {
            XCTFail("enqueue() must succeed")
            return
        }

        store.markFailed(row, reason: "test failure")

        XCTAssertTrue(FileManager.default.fileExists(atPath: artifact.fileURL.path),
                      "markFailed() must NOT remove the WAV — D-10 hold")
        let updated = try XCTUnwrap(store.pendingRecordings.first(where: { $0.uuid == row.uuid }))
        XCTAssertEqual(updated.status, PendingRecordingStatus.failed.rawValue)
        XCTAssertEqual(updated.failureReason, "test failure")
        XCTAssertEqual(updated.retryCount, 1, "markFailed() must increment retryCount")

        // Cleanup
        store.delete(updated)
    }

    /// `queuedInArrivalOrder` — D-09's drain order — must exclude `.failed` and
    /// `.transcribing` rows, keeping only rows actually eligible to be drained.
    func testQueuedInArrivalOrderExcludesNonQueuedRows() throws {
        let a = try writeRealWav()
        Thread.sleep(forTimeInterval: 0.01)
        let b = try writeRealWav()
        Thread.sleep(forTimeInterval: 0.01)
        let c = try writeRealWav()

        store.enqueue(a)
        guard let bRow = store.enqueue(b) else { XCTFail(); return }
        store.enqueue(c)

        store.markFailed(bRow, reason: "excluded from drain order")

        XCTAssertEqual(store.queuedInArrivalOrder.map(\.uuid), [a.uuid, c.uuid],
                       "queuedInArrivalOrder must skip the failed row and keep arrival order for the rest")

        // Cleanup
        for row in store.pendingRecordings { store.delete(row) }
    }
}
