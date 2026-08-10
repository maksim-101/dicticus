import Foundation
import GRDB
import os.log

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

    var pendingCount: Int { pendingRecordings.count }

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
    func delete(_ recording: PendingRecording) {
        if let url = try? fileURL(for: recording) {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                Self.log.error("Failed to remove WAV for pending recording \(recording.uuid): \(error.localizedDescription)")
            }
        }
        guard let id = recording.id else {
            Self.log.error("delete() called with nil id for uuid=\(recording.uuid) — skipping row delete")
            return
        }
        do {
            _ = try dbPool.write { db in
                try PendingRecording.filter(key: id).deleteAll(db)
            }
            load()
        } catch {
            Self.log.error("Failed to delete pending recording row \(recording.uuid): \(error.localizedDescription)")
        }
    }
}
