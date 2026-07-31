import Foundation
import GRDB
import os.log

/// Metadata for a transcription history entry.
///
/// Phase 20.05 ACT-3-VISIBILITY: `Hashable` is required so iOS HistoryView can
/// use `NavigationLink(value: entry)` + `.navigationDestination(for: TranscriptionEntry.self)`
/// for value-based routing into HistoryDetailView. All stored properties are
/// already Hashable (`Int64?`, `UUID`, `String`, `Date`, `Double`), so Swift
/// synthesises the conformance — no custom `==` or `hash(into:)` needed.
struct TranscriptionEntry: Identifiable, Codable, Hashable, FetchableRecord, PersistableRecord {
    var id: Int64? // SQLite RowID
    var uuid: UUID
    var text: String
    var rawText: String
    var language: String
    var mode: String
    var createdAt: Date
    var confidence: Double

    /// Database column names.
    enum Columns: String, ColumnExpression {
        case id, uuid, text, rawText, language, mode, createdAt, confidence
    }

    /// GRDB requirement: Define the table name.
    /// nonisolated(unsafe) is needed for Swift 6 global shared state.
    nonisolated(unsafe) static var databaseTableName = "transcriptionEntry"

    /// Initialize a new entry from a transcription result.
    init(
        id: Int64? = nil,
        uuid: UUID = UUID(),
        text: String,
        rawText: String,
        language: String,
        mode: String,
        createdAt: Date = Date(),
        confidence: Double
    ) {
        self.id = id
        self.uuid = uuid
        self.text = text
        self.rawText = rawText
        self.language = language
        self.mode = mode
        self.createdAt = createdAt
        self.confidence = confidence
    }
}

/// Manages the transcription history database using GRDB and SQLite FTS5.
@MainActor
class HistoryService: ObservableObject {

    static let shared = HistoryService()

    private let dbPool: DatabasePool

    /// URL of the on-disk SQLite file backing this instance. Exposed for diagnostics
    /// and tests (Phase 20.04 / ACT-4-RESILIENCE) so the fallback path can be asserted
    /// without depending on entitlements.
    let databaseFileURL: URL

    private static let log = Logger(subsystem: "com.dicticus", category: "history")

    /// Backing storage for the App-Group resolution outcome. Set during init.
    /// Settings UIs read this to surface a non-blocking diagnostic warning row.
    /// `true` on the happy path (App Group container resolved); `false` when init
    /// fell back to `applicationSupportDirectory`.
    static private(set) var appGroupAvailable: Bool = true

    /// Log-once guard — ensures the fallback warning is emitted at most once per
    /// process lifetime regardless of how many times `resolveStorage` runs (singleton
    /// + any test factories combined).
    private static var didLogFallback = false

    /// Internal storage backend resolution result — discriminates the App-Group
    /// happy path from the per-app applicationSupport fallback.
    private enum StorageBackend {
        case appGroup(URL)
        case applicationSupport(URL)

        var url: URL {
            switch self {
            case .appGroup(let u), .applicationSupport(let u):
                return u
            }
        }
    }

    /// Resolve the storage backend. Provider closure is injectable so unit tests
    /// can simulate the App-Group-missing path by returning nil without entitlements.
    private static func resolveStorage(provider: () -> URL?) -> StorageBackend {
#if os(macOS)
        // macOS primary path: app-local Application Support — eliminates the
        // kTCCServiceSystemPolicyAppData TCC prompt (group.com.dicticus naming).
        // When the provider returns a non-nil URL (test seam via makeForTesting),
        // honour it so tests can exercise isolated temp containers without touching
        // the real Application Support path.
        if let injectedURL = provider() {
            return .applicationSupport(injectedURL)
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleID = Bundle.main.bundleIdentifier ?? "com.dicticus.fallback"
        return .applicationSupport(appSupport.appendingPathComponent(bundleID, isDirectory: true))
#else
        if let groupURL = provider() {
            return .appGroup(groupURL)
        }
        if !didLogFallback {
            didLogFallback = true
            log.warning("App Group container 'group.com.dicticus' not found — falling back to per-app applicationSupport. History will NOT be visible to keyboard extensions until entitlements are restored.")
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleID = Bundle.main.bundleIdentifier ?? "com.dicticus.fallback"
        return .applicationSupport(appSupport.appendingPathComponent(bundleID, isDirectory: true))
#endif
    }

    @Published private(set) var entries: [TranscriptionEntry] = []

    /// Default initializer used by the `shared` singleton — resolves the App Group
    /// container via the standard FileManager API.
    private convenience init() {
#if os(macOS)
        // macOS uses app-local storage unconditionally — always pass nil so the
        // resolveStorage macOS path falls through to applicationSupportDirectory.
        self.init(containerURLProvider: { nil })
#else
        self.init(containerURLProvider: {
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.dicticus")
        })
#endif
    }

    /// Designated initializer — accepts an injectable container-URL provider so
    /// tests can exercise the fallback path. Default callers go through the
    /// no-arg `convenience init` above.
    private init(containerURLProvider: () -> URL?) {
        let backend = Self.resolveStorage(provider: containerURLProvider)
        switch backend {
        case .appGroup:
            Self.appGroupAvailable = true
        case .applicationSupport:
            Self.appGroupAvailable = false
        }
        let containerURL = backend.url
        let dbFolder = containerURL.appendingPathComponent("Database", isDirectory: true)
        let dbURL = dbFolder.appendingPathComponent("History.sqlite")
        self.databaseFileURL = dbURL
        do {
            try FileManager.default.createDirectory(at: dbFolder, withIntermediateDirectories: true)
            self.dbPool = try DatabasePool(path: dbURL.path)
            try migrate()
            load()
        } catch {
            Self.log.error("Failed to initialize database: \(error.localizedDescription)")
            fatalError("Failed to initialize History database")
        }
    }

    #if DEBUG
    /// Test seam (Phase 20.04 / ACT-4-RESILIENCE). Bypasses the singleton so
    /// each call constructs a fresh instance against the supplied provider —
    /// pass `{ nil }` to force the applicationSupport fallback path.
    static func makeForTesting(containerURLProvider: @escaping () -> URL?) -> HistoryService {
        return HistoryService(containerURLProvider: containerURLProvider)
    }
    #endif

    private func migrate() throws {
        var migrator = DatabaseMigrator()
        
        // Wipe old schema if it exists to fix the UUID/Integer ID conflict
        migrator.registerMigration("v2-setup") { db in
            try db.execute(sql: "DROP TABLE IF EXISTS transcriptionEntry")
            try db.execute(sql: "DROP TABLE IF EXISTS transcription_search")
            
            try db.create(table: "transcriptionEntry") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("uuid", .text).notNull().unique()
                t.column("text", .text).notNull()
                t.column("rawText", .text).notNull()
                t.column("language", .text).notNull()
                t.column("mode", .text).notNull()
                t.column("createdAt", .datetime).notNull().indexed()
                t.column("confidence", .double).notNull()
            }
            
            try db.execute(sql: """
                CREATE VIRTUAL TABLE transcription_search USING fts5(
                    text,
                    rawText,
                    content='transcriptionEntry',
                    content_rowid='id'
                )
                """)
                
            try db.execute(sql: """
                CREATE TRIGGER transcription_search_insert AFTER INSERT ON transcriptionEntry BEGIN
                    INSERT INTO transcription_search(rowid, text, rawText) VALUES (new.id, new.text, new.rawText);
                END;
                CREATE TRIGGER transcription_search_delete AFTER DELETE ON transcriptionEntry BEGIN
                    INSERT INTO transcription_search(transcription_search, rowid, text, rawText) VALUES('delete', old.id, old.text, old.rawText);
                END;
                CREATE TRIGGER transcription_search_update AFTER UPDATE ON transcriptionEntry BEGIN
                    INSERT INTO transcription_search(transcription_search, rowid, text, rawText) VALUES('delete', old.id, old.text, old.rawText);
                    INSERT INTO transcription_search(rowid, text, rawText) VALUES (new.id, new.text, new.rawText);
                END;
                """)
        }
        
        try migrator.migrate(dbPool)
    }

    func load(query: String? = nil) {
        do {
            try dbPool.read { db in
                if let query = query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let sql = "SELECT * FROM transcriptionEntry WHERE id IN (SELECT rowid FROM transcription_search WHERE transcription_search MATCH ?) ORDER BY createdAt DESC"
                    self.entries = try TranscriptionEntry.fetchAll(db, sql: sql, arguments: [query])
                } else {
                    self.entries = try TranscriptionEntry.order(TranscriptionEntry.Columns.createdAt.desc).fetchAll(db)
                }
            }
        } catch {
            Self.log.error("Failed to load history: \(error.localizedDescription)")
        }
    }

    func save(_ entry: TranscriptionEntry) {
        do {
            let entryToSave = entry
            try dbPool.write { db in
                try entryToSave.insert(db)
            }
            Self.log.info("Saved transcription to history: \(entry.text.prefix(20))...")
            load()
        } catch {
            Self.log.error("Failed to save entry: \(error.localizedDescription)")
        }
    }

    /// Update an existing entry in place (used by foreground delivery to persist AI-cleaned text).
    /// The entry must already exist in the database (identified by its rowid `id`).
    /// Leaves `uuid`, `rawText`, `createdAt`, `language`, and `confidence` unchanged.
    ///
    /// Returns `true` if the update succeeded, `false` if the entry had no `id` or the
    /// row was not found. The caller must treat `false` as a persist failure and NOT
    /// advance state (e.g. clear pending list) as if delivery completed.
    @discardableResult
    func update(_ entry: TranscriptionEntry) -> Bool {
        guard entry.id != nil else {
            Self.log.error("update() called with nil id for uuid=\(entry.uuid) — skipping (no rowid)")
            return false
        }
        do {
            let entryToUpdate = entry
            try dbPool.write { db in
                try entryToUpdate.update(db)
            }
            Self.log.info("Updated history entry: \(entry.uuid) mode=\(entry.mode)")
            load()
            return true
        } catch {
            Self.log.error("Failed to update entry uuid=\(entry.uuid): \(error.localizedDescription)")
            return false
        }
    }

    func delete(id: Int64) {
        do {
            _ = try dbPool.write { db in
                try TranscriptionEntry.filter(key: id).deleteAll(db)
            }
            load()
        } catch {
            Self.log.error("Failed to delete entry: \(error.localizedDescription)")
        }
    }

    func clearAll() {
        do {
            _ = try dbPool.write { db in
                try TranscriptionEntry.deleteAll(db)
            }
            load()
        } catch {
            Self.log.error("Failed to clear history: \(error.localizedDescription)")
        }
    }
}
