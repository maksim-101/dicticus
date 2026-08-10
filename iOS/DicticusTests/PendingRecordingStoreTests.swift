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
}
