import Foundation
import GRDB
import os.log
@preconcurrency import AVFoundation

/// Lifecycle status of a `PendingRecording` row. Maps exactly onto the three status
/// pills in `46-UI-SPEC`'s Component Inventory (46-04/46-05 build the UI; this plan
/// only needs `queued`, but the enum is declared complete now so the column values
/// those later plans write are stable from day one).
enum PendingRecordingStatus: String {
    case queued
    case transcribing
    case failed
}

/// A captured recording that exists on disk before any transcript exists — the
/// durable unit from capture until the transcript is saved (see 46-02-PLAN.md's
/// assumption-delta decision: `pendingTranscriptUUIDs` tracks an already-transcribed,
/// already-saved entry; this table tracks the state *before* that).
struct PendingRecording: Identifiable, Codable, Hashable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var uuid: UUID
    /// Bare `{uuid}.wav` filename — never an absolute or relative path. Container
    /// paths change between installs, and a stored bare filename is also the
    /// mitigation for T-46-05 (path traversal via a stored recording path).
    var fileName: String
    var createdAt: Date
    var status: String
    var durationSeconds: Double?
    var retryCount: Int
    var failureReason: String?

    enum Columns: String, ColumnExpression {
        case id, uuid, fileName, createdAt, status, durationSeconds, retryCount, failureReason
    }

    /// GRDB requirement: Define the table name.
    /// nonisolated(unsafe) is needed for Swift 6 global shared state.
    nonisolated(unsafe) static var databaseTableName = "pendingRecording"

    /// Whether a failed row could plausibly succeed if retried. `false` exactly when
    /// `durationSeconds` is `nil` — the ONLY way that happens is
    /// `recoverOrphanedRecordings()`'s `determineDurationSeconds(for:)` returning nil
    /// because the WAV's header could not be trusted (a freshly-recorded row via
    /// `enqueue(_:)` always carries a real, non-optional `RecordingArtifact.durationSeconds`,
    /// so it can never produce a nil-duration row through the normal path).
    ///
    /// 2026-08-11 on-device UAT (device re-test of the drain-deadlock fix, 1ea1e03):
    /// empirically confirmed via a direct simulator probe that a WAV whose header
    /// reports zero frames (46-03's "outcome (b)") makes `AVAudioFile.read(into:)`
    /// throw a deterministic, content-independent
    /// `required condition is false: buffer.frameCapacity != 0` assertion EVERY
    /// single time, regardless of how much real audio the file actually contains.
    /// Retrying can never succeed for this class of file — offering Retry is a trap,
    /// not a recovery path, and the coordinator's device report ("transcribing…
    /// then back to failed, no change") is exactly what that trap looks like from
    /// the user's side. `durationSeconds == nil` is the store's existing, exclusive
    /// signal for "this file's structure could not be verified" — reusing it here
    /// avoids inventing a second, possibly-disagreeing classification.
    var isRetryable: Bool { durationSeconds != nil }
}

/// Manages the durable pending-recording queue: recordings that have been captured
/// but not yet transcribed. Backed by `HistoryService`'s existing GRDB pool rather
/// than a second database, so there is exactly one migrator and one storage-resolution
/// algorithm (see 46-02-PLAN.md Section B).
@MainActor
final class PendingRecordingStore: ObservableObject {

    static let shared = PendingRecordingStore(historyService: .shared)

    private static let log = Logger(subsystem: "com.dicticus", category: "pendingRecordings")

    private let historyService: HistoryService
    private var dbPool: DatabasePool { historyService.databasePool }

    /// Ordered `createdAt` ascending — arrival order, the queue's drain order (46-03).
    @Published private(set) var pendingRecordings: [PendingRecording] = []

    /// Locked count definition (46-05-PLAN.md): queued + transcribing + failed —
    /// identical to the History tab badge and the Home chip, so the two can never
    /// disagree. Written as an explicit status filter rather than the array's bare
    /// count: the three statuses happen to be exhaustive today, so the two are
    /// numerically equal, but a filter means a fourth status added later forces a
    /// deliberate decision instead of silently changing the number the user sees.
    /// Counting only queued+failed would make the chip vanish mid-flight the moment
    /// the last queued recording started transcribing — exactly the "app lost it"
    /// read this definition exists to prevent.
    var pendingCount: Int {
        pendingRecordings.filter { row in
            switch PendingRecordingStatus(rawValue: row.status) {
            case .queued: return true
            case .transcribing: return true
            case .failed: return true
            case nil: return false
            }
        }.count
    }

    private init(historyService: HistoryService) {
        self.historyService = historyService
        load()
    }

    #if DEBUG
    /// Test seam — this project has already had a test run write to and wipe the
    /// real user History database. The standing guard against a repeat is that no
    /// test names a singleton; this factory is the only sanctioned way to construct
    /// a `PendingRecordingStore` from a test.
    static func makeForTesting(historyService: HistoryService) -> PendingRecordingStore {
        PendingRecordingStore(historyService: historyService)
    }
    #endif

    func load() {
        do {
            try dbPool.read { db in
                self.pendingRecordings = try PendingRecording
                    .order(PendingRecording.Columns.createdAt.asc)
                    .fetchAll(db)
            }
        } catch {
            Self.log.error("Failed to load pending recordings: \(error.localizedDescription)")
        }
    }

    @discardableResult
    func enqueue(_ artifact: RecordingArtifact) -> PendingRecording? {
        let row = PendingRecording(
            id: nil,
            uuid: artifact.uuid,
            fileName: "\(artifact.uuid.uuidString).wav",
            createdAt: Date(),
            status: PendingRecordingStatus.queued.rawValue,
            durationSeconds: artifact.durationSeconds,
            retryCount: 0,
            failureReason: nil
        )
        do {
            try dbPool.write { db in
                try row.insert(db)
            }
            load()
            return pendingRecordings.first(where: { $0.uuid == artifact.uuid })
        } catch {
            Self.log.error("Failed to enqueue pending recording \(artifact.uuid): \(error.localizedDescription)")
            return nil
        }
    }

    func fileURL(for recording: PendingRecording) throws -> URL {
        try AudioRecorder.recordingsDirectory().appendingPathComponent(recording.fileName)
    }

    /// Removes the WAV bytes first, then the row — logging but not throwing if the
    /// file is already gone. D-02's whole point is that the audio is really gone, so
    /// callers should verify via `FileManager.fileExists(atPath:)`, not row count alone.
    /// This is one of exactly two places audio bytes leave the device — the other is
    /// `clear(_:)` (the user-initiated D-10 delete) — both funnel through the same
    /// `removeItem` call so a future incident can be traced to one of these two sites.
    func delete(_ recording: PendingRecording) {
        removeFileAndRow(recording, logPrefix: "delete")
    }

    /// User-initiated delete (D-10's "clear" action, surfaced by a future plan's UI).
    /// Identical byte-removing implementation to `delete(_:)`, distinguished only by
    /// name and by its own log line — the store has no other code path that removes
    /// audio on its own initiative (T-46-07: an incident investigation must be able to
    /// tell an app-initiated deletion from a user-initiated one).
    func clear(_ recording: PendingRecording) {
        Self.log.info("User cleared pending recording \(recording.uuid) (explicit clear, not app-initiated)")
        removeFileAndRow(recording, logPrefix: "clear")
    }

    private func removeFileAndRow(_ recording: PendingRecording, logPrefix: String) {
        if let url = try? fileURL(for: recording) {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                Self.log.error("\(logPrefix)(): failed to remove WAV for pending recording \(recording.uuid): \(error.localizedDescription)")
            }
        }
        guard let id = recording.id else {
            Self.log.error("\(logPrefix)() called with nil id for uuid=\(recording.uuid) — skipping row delete")
            return
        }
        do {
            _ = try dbPool.write { db in
                try PendingRecording.filter(key: id).deleteAll(db)
            }
            load()
        } catch {
            Self.log.error("\(logPrefix)(): failed to delete pending recording row \(recording.uuid): \(error.localizedDescription)")
        }
    }

    /// Marks a row as actively being transcribed. Called by the drain immediately
    /// before invoking the transcriber, so a process death mid-transcription leaves a
    /// `.transcribing` row for `recoverOrphanedRecordings()` to reset to `.queued` on
    /// the next launch, rather than a row silently stuck forever.
    func markTranscribing(_ recording: PendingRecording) {
        guard recording.id != nil else {
            Self.log.error("markTranscribing() called with nil id for uuid=\(recording.uuid)")
            return
        }
        var updated = recording
        updated.status = PendingRecordingStatus.transcribing.rawValue
        do {
            try dbPool.write { db in try updated.update(db) }
            load()
        } catch {
            Self.log.error("Failed to mark pending recording \(recording.uuid) as transcribing: \(error.localizedDescription)")
        }
    }

    /// D-10's hold: a transcription attempt that failed on audio that may still
    /// contain something the user said is never deleted. Sets `status`, records
    /// `reason`, and increments `retryCount` — the WAV is left untouched on disk.
    /// This function, `delete(_:)`, and `clear(_:)` are the store's complete set of
    /// row-mutating operations after enqueue; nothing else removes audio.
    func markFailed(_ recording: PendingRecording, reason: String) {
        guard recording.id != nil else {
            Self.log.error("markFailed() called with nil id for uuid=\(recording.uuid)")
            return
        }
        var updated = recording
        updated.status = PendingRecordingStatus.failed.rawValue
        updated.failureReason = reason
        updated.retryCount += 1
        do {
            try dbPool.write { db in try updated.update(db) }
            load()
        } catch {
            Self.log.error("Failed to mark pending recording \(recording.uuid) as failed: \(error.localizedDescription)")
        }
    }

    /// Returns a previously-failed row to `.queued` — the implementation detail behind
    /// `DictationViewModel.retryPendingRecording(_:)`'s "reset the row to queued"
    /// step. Does not touch `retryCount` (the count survives a retry attempt) but
    /// clears `failureReason`, since a queued row has no failure reason by
    /// definition.
    func requeue(_ recording: PendingRecording) {
        guard recording.id != nil else {
            Self.log.error("requeue() called with nil id for uuid=\(recording.uuid)")
            return
        }
        var updated = recording
        updated.status = PendingRecordingStatus.queued.rawValue
        updated.failureReason = nil
        do {
            try dbPool.write { db in try updated.update(db) }
            load()
        } catch {
            Self.log.error("Failed to requeue pending recording \(recording.uuid): \(error.localizedDescription)")
        }
    }

    /// House-voice explanation for a row `recoverOrphanedRecordings()` determined can
    /// never be transcribed (2026-08-11) — plain language, leads with what actually
    /// happened, states the (permanent) consequence, and says what the user can do.
    /// Proposed wording, not yet folded into the locked `46-UI-SPEC.md` copy table —
    /// see `46-05-SUMMARY.md` for the sign-off request.
    static let unrecoverableFailureReason =
        "This recording was cut off before it finished saving, so it can't be transcribed. Clear it to remove it."

    /// D-09's drain order — the only ordering the drain may use. `pendingRecordings`
    /// is already `createdAt` ascending (see `load()`), so this filters to just the
    /// rows actually eligible to be drained (excludes `.transcribing`/`.failed`).
    var queuedInArrivalOrder: [PendingRecording] {
        pendingRecordings.filter { $0.status == PendingRecordingStatus.queued.rawValue }
    }

    /// Diagnostic for the recovery-scan log line and for a future storage-safety UI —
    /// deliberately not a cap (see 46-03-PLAN.md "No cap, by decision").
    func totalBytesOnDisk() -> Int64 {
        guard let dir = try? AudioRecorder.recordingsDirectory() else { return 0 }
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles, .skipsPackageDescendants]
        )) ?? []
        return entries.reduce(Int64(0)) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return total + Int64(size)
        }
    }

    /// Determines a recovered file's duration defensively. Device evidence
    /// (`46-DEVICE-TEST-PROCEDURE.md` Section A, outcome (b), 2026-08-10, 8 total
    /// samples across two controlled runs + 6 debris files) shows `AVAudioFile` does
    /// NOT throw on a mid-write-killed WAV — it opens successfully and reports
    /// `length == 0`, even though the file contains real, non-trivial audio data on
    /// disk. Trusting the header at face value would misreport every jetsammed
    /// recording as an empty clip, exactly the ambiguity D-01 exists to resolve.
    /// Returns `nil` (never `0`) whenever the duration cannot be trusted — a
    /// confidently-wrong duration is worse than an absent one.
    private static func determineDurationSeconds(for url: URL) -> Double? {
        guard let audioFile = try? AVAudioFile(forReading: url) else { return nil }
        let format = audioFile.processingFormat
        guard format.sampleRate > 0 else { return nil }
        let headerDuration = Double(audioFile.length) / format.sampleRate
        guard audioFile.length > 0, headerDuration.isFinite, headerDuration > 0 else { return nil }

        // Defense-in-depth beyond the observed length==0 case: even a nonzero header
        // duration is cross-checked against the file's own byte size, in case a
        // future device/OS combination produces a plausible-but-wrong nonzero value
        // instead of a flat zero.
        //
        // 2026-08-11 correction: `AVAudioFile(forWriting:)` adds a fixed container
        // overhead — empirically confirmed EXACTLY identical (4096 bytes) at
        // 0.3s/1s/10s test durations (16kHz mono Float32), i.e. duration-independent,
        // not a data-proportional discrepancy. A pure percentage check against raw
        // file size falsely flagged perfectly fine, freshly-recorded SHORT clips as
        // untrustworthy: a 1s recording disagreed by 6%, and the app's own
        // `minimumDurationSeconds` floor (0.3s) disagreed by ~18% — comfortably past
        // the original 5% threshold. That false positive silently denied Retry to
        // recordings that were never actually broken (this cross-check feeds
        // `PendingRecording.isRetryable`). Subtracting the measured fixed overhead
        // before comparing brought all three probed durations to an exact 0%
        // disagreement — restoring the check's original intent (catching GROSS
        // truncation) without punishing routine container overhead on short, valid
        // recordings. Deliberately NOT padded further: over-subtracting would
        // reintroduce the same asymmetric harm to short clips in the other
        // direction (an under-count of true PCM bytes), and the 5% tolerance below
        // already has headroom for minor cross-format variance this store hasn't
        // directly measured.
        let knownFixedContainerOverheadBytes = 4096.0
        let bytesPerFrame = Int(format.streamDescription.pointee.mBytesPerFrame)
        if bytesPerFrame > 0,
           let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           fileSize > 0 {
            let adjustedByteCount = max(0, Double(fileSize) - knownFixedContainerOverheadBytes)
            let byteSizeDuration = adjustedByteCount / Double(bytesPerFrame) / format.sampleRate
            if byteSizeDuration > 0 {
                let disagreement = abs(headerDuration - byteSizeDuration) / max(headerDuration, byteSizeDuration)
                guard disagreement <= 0.05 else { return nil }
            }
        }
        return headerDuration
    }

    /// Relaunch-time recovery scan (D-01). Finds `.wav` files on disk with no
    /// matching row (a process died before `enqueue()` ran — the whole point of
    /// writing to disk incrementally) and reconciles rows against a possibly-changed
    /// disk state in the other direction: a row whose file vanished becomes `.failed`
    /// (never deleted by the scan itself), and a row stranded `.transcribing` by a
    /// killed transcription process resets to `.queued`. Idempotent — running it
    /// twice in a row produces the same rows.
    ///
    /// T-46-05 mitigation: this is the one place the store reads a directory whose
    /// contents it did not just write in this process — enumerated non-recursively,
    /// symlinks and non-regular files rejected, and only a bare `{UUID}.wav` basename
    /// is accepted (rejects path traversal, foreign files, and non-WAV extensions).
    func recoverOrphanedRecordings() {
        let dir: URL
        do {
            dir = try AudioRecorder.recordingsDirectory()
        } catch {
            Self.log.error("Recovery scan: could not resolve recordings directory: \(error.localizedDescription)")
            return
        }

        let resourceKeys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: resourceKeys,
                options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles, .skipsPackageDescendants]
            )
        } catch {
            Self.log.error("Recovery scan: could not enumerate recordings directory: \(error.localizedDescription)")
            return
        }

        load()  // fresh view of existing rows before deciding what's orphaned

        var recoveredCount = 0
        for url in entries {
            guard url.pathExtension.lowercased() == "wav" else { continue }
            let values = try? url.resourceValues(forKeys: Set(resourceKeys))
            guard values?.isRegularFile == true, values?.isSymbolicLink != true else { continue }
            guard let uuid = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { continue }
            guard !pendingRecordings.contains(where: { $0.uuid == uuid }) else { continue }

            let durationSeconds = Self.determineDurationSeconds(for: url)
            // 2026-08-11: a nil duration means determineDurationSeconds() could not
            // trust this WAV's header — and (empirically confirmed via a direct
            // simulator probe) that specific class of file makes the transcriber's
            // own file read throw a deterministic, content-independent assertion
            // every time. Inserting it as `.queued` would show "Waiting for model"
            // and offer Retry on something that can never succeed — the exact trap
            // the 2026-08-11 device report described ("transcribing… then back to
            // failed, no change"). Insert it already `.failed`, honestly, once.
            let isRecoverable = durationSeconds != nil
            let row = PendingRecording(
                id: nil,
                uuid: uuid,
                fileName: url.lastPathComponent,
                createdAt: Date(),
                status: isRecoverable ? PendingRecordingStatus.queued.rawValue : PendingRecordingStatus.failed.rawValue,
                durationSeconds: durationSeconds,
                retryCount: 0,
                failureReason: isRecoverable ? nil : Self.unrecoverableFailureReason
            )
            do {
                try dbPool.write { db in try row.insert(db) }
                recoveredCount += 1
            } catch {
                Self.log.error("Recovery scan: failed to insert recovered row for \(uuid): \(error.localizedDescription)")
            }
        }

        load()

        // Reconcile the other direction. Neither branch deletes anything — a missing
        // file becomes `.failed` (D-10's hold applies even here: the scan itself must
        // never be the thing that discards audio), and a stranded `.transcribing` row
        // resets to `.queued` so it is not stuck forever.
        var resetCount = 0
        var failedCount = 0
        for row in pendingRecordings {
            let resolvedURL = try? fileURL(for: row)
            let fileExists = resolvedURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false

            if !fileExists {
                markFailed(row, reason: "Recording file missing on disk: \(row.fileName)")
                failedCount += 1
            } else if row.status == PendingRecordingStatus.transcribing.rawValue {
                var reset = row
                reset.status = PendingRecordingStatus.queued.rawValue
                do {
                    try dbPool.write { db in try reset.update(db) }
                    resetCount += 1
                } catch {
                    Self.log.error("Recovery scan: failed to reset transcribing row \(row.uuid): \(error.localizedDescription)")
                }
            }
        }

        load()
        Self.log.info("Recovery scan complete: recovered=\(recoveredCount) reset=\(resetCount) failed=\(failedCount) totalBytesOnDisk=\(self.totalBytesOnDisk())")
    }
}
