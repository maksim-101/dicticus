import Foundation
import GRDB
import os.log

#if os(macOS)
/// One-time migration moving history DB + dictionary + settings
/// from the App Group container to per-app storage.
/// Idempotency contract: gated by `appLocalMigrationV1_Completed` flag in
/// UserDefaults.standard. After first run, subsequent calls are no-ops.
/// Called from macOS/Dicticus/DicticusApp.swift BEFORE SwissDefaultMigration
/// and before any service initialization.
public enum AppLocalMigrationService {
    static let migratedKey = "appLocalMigrationV1_Completed"
    private static let log = Logger(subsystem: "com.dicticus", category: "AppLocalMigration")

    // MARK: - Production Entry Point

    public static func runIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: migratedKey) else { return }

        // Resolve the group container source. The binary ships WITHOUT the entitlement,
        // but users who previously had it retain TCC consent, making the path accessible.
        // Both methods are tried; if both fail, the migration is a graceful no-op.
        let sourceContainer: URL? = {
            if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.dicticus"),
               FileManager.default.fileExists(atPath: url.path) {
                return url
            }
            // Fallback: direct raw path (works when TCC consent exists but API returns nil)
            let rawPath = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Group Containers/group.com.dicticus")
            if FileManager.default.fileExists(atPath: rawPath.path) {
                return rawPath
            }
            return nil
        }()

        let destContainer: URL = {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let bundleID = Bundle.main.bundleIdentifier ?? "com.dicticus.app"
            return appSupport.appendingPathComponent(bundleID, isDirectory: true)
        }()

        do {
            try migrate(
                sourceContainerURL: sourceContainer,
                destDefaults: .standard,
                destDBProvider: { destContainer }
            )
        } catch {
            // Migration failure is non-fatal. Log and set the flag so we never retry
            // forever — the app continues with whatever app-local store exists.
            log.error("[AppLocalMigration] FAILED — \(error.localizedDescription). App will use existing app-local store.")
            UserDefaults.standard.set(true, forKey: migratedKey)
        }
    }

    // MARK: - Core Migration Logic

    /// Shared implementation used by both `runIfNeeded()` (production) and
    /// `runForTesting(...)` (test seam). All external dependencies are injected.
    ///
    /// Source settings/dictionary are read by loading the container's preferences
    /// PLIST FILE DIRECTLY at:
    ///   `<sourceContainerURL>/Library/Preferences/group.com.dicticus.plist`
    ///
    /// This is necessary because `UserDefaults(suiteName: "group.com.dicticus")` does
    /// NOT read the group container's plist when the app-groups entitlement is absent —
    /// it silently reads/creates a separate plist in ~/Library/Preferences/ instead.
    /// Reading the file directly (path-based, like the DB) bypasses this entitlement gate.
    private static func migrate(
        sourceContainerURL: URL?,
        destDefaults: UserDefaults,
        destDBProvider: () -> URL
    ) throws {
        // Idempotency gate — reads destDefaults (UserDefaults.standard in production).
        guard !destDefaults.bool(forKey: migratedKey) else { return }

        let destContainerURL = destDBProvider()
        let destDBDir = destContainerURL.appendingPathComponent("Database", isDirectory: true)
        let destDBURL = destDBDir.appendingPathComponent("History.sqlite")

        // Validate source DB presence.
        guard let srcContainer = sourceContainerURL else {
            // Fresh install — no group container exists. Set flag and return.
            log.info("[AppLocalMigration] Source container absent — fresh install or TCC expired. Marking complete.")
            destDefaults.set(true, forKey: migratedKey)
            return
        }

        let srcDBDir = srcContainer.appendingPathComponent("Database", isDirectory: true)
        let srcDBURL = srcDBDir.appendingPathComponent("History.sqlite")

        guard FileManager.default.fileExists(atPath: srcDBURL.path) else {
            // Source container exists but no DB in it — treat as fresh install.
            log.info("[AppLocalMigration] Source DB absent — marking complete without migration.")
            destDefaults.set(true, forKey: migratedKey)
            return
        }

        // STEP 1: Create backup of source DB files before any writes.
        let ts = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backupDir = destContainerURL
            .appendingPathComponent("Backups", isDirectory: true)
            .appendingPathComponent("pre-migration-\(ts)", isDirectory: true)
        try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)

        // Copy source DB sidecar files to backup (raw copy is safe for backup purposes only).
        let sidecarSuffixes = ["", "-wal", "-shm"]
        for suffix in sidecarSuffixes {
            let srcFile = srcDBDir.appendingPathComponent("History.sqlite\(suffix)")
            if FileManager.default.fileExists(atPath: srcFile.path) {
                let backupFile = backupDir.appendingPathComponent("History.sqlite\(suffix)")
                try FileManager.default.copyItem(at: srcFile, to: backupFile)
            }
        }
        log.info("[AppLocalMigration] Backup created at \(backupDir.path)")

        // STEP 2: Migrate history DB via GRDB online backup API (WAL-safe).
        // No-clobber guard: if the destination DB already exists and contains rows,
        // the app-local store is authoritative (user was already on the fallback path
        // or a prior install already migrated). Do not overwrite it with the group copy.
        let destDBExists = FileManager.default.fileExists(atPath: destDBURL.path)
        let destExistingRowCount: Int = destDBExists ? (try {
            let pool = try DatabasePool(path: destDBURL.path)
            return try pool.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transcriptionEntry") ?? 0
            }
        }()) : 0

        let sourceCount: Int
        let destCount: Int

        if destDBExists && destExistingRowCount > 0 {
            // Destination DB is populated — preserve it; skip the DB copy entirely.
            log.info("[AppLocalMigration] Destination DB already populated (\(destExistingRowCount) rows) — preserving app-local store, skipping DB copy.")
            sourceCount = destExistingRowCount
            destCount = destExistingRowCount
        } else {
            // Destination DB is absent or empty — safe to copy from source.
            try FileManager.default.createDirectory(at: destDBDir, withIntermediateDirectories: true)
            sourceCount = try {
                let sourcePool = try DatabasePool(path: srcDBURL.path)
                let destQueue = try DatabaseQueue(path: destDBURL.path)
                try sourcePool.backup(to: destQueue)
                return try sourcePool.read { db in
                    try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transcriptionEntry") ?? 0
                }
            }()

            // STEP 3: Verify destination DB is readable and row count matches.
            destCount = try {
                let destPool = try DatabasePool(path: destDBURL.path)
                return try destPool.read { db in
                    try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transcriptionEntry") ?? 0
                }
            }()

            guard destCount == sourceCount else {
                throw MigrationError.rowCountMismatch(source: sourceCount, dest: destCount)
            }
        }

        // STEP 4: Migrate dictionary and settings keys by reading the source container's
        // preferences plist FILE DIRECTLY — not via UserDefaults(suiteName:), which would
        // silently read/create ~/Library/Preferences/group.com.dicticus.plist (wrong file)
        // when the app-groups entitlement is absent.
        let srcPrefsURL = srcContainer
            .appendingPathComponent("Library/Preferences/group.com.dicticus.plist")

        if let srcPrefsDict = NSDictionary(contentsOf: srcPrefsURL) as? [String: Any] {
            // Scalar settings: skip-if-present is correct (don't clobber a value the user
            // already set on the app-local side).
            let scalarKeys = ["dictionaryCaseSensitive", "useSwissGerman",
                              "swissDefaultMigratedV2_1", "aiCleanupEnabled"]
            for key in scalarKeys {
                if destDefaults.object(forKey: key) == nil,
                   let value = srcPrefsDict[key] {
                    destDefaults.set(value, forKey: key)
                }
            }

            // Dictionary: MUST MERGE, not skip-if-present. DictionaryService.init seeds its
            // compiled-in defaults into `customDictionaryMetadata` before/around this migration,
            // so the dest key is virtually never nil — a skip-if-present guard silently stranded
            // the user's real entries in the group container (root cause of the 2026-06-13 macOS
            // dictionary loss: 109 user+imported entries never migrated). Union the two blobs;
            // an entry already in the app-local store wins, source fills every gap.
            mergeDictionaryBlob(from: srcPrefsDict["customDictionaryMetadata"], into: destDefaults)

            log.info("[AppLocalMigration] Settings migrated from container plist.")
        } else {
            // Plist absent or unreadable — graceful no-op for settings; history DB migration
            // already completed above. This is normal for fresh installs or containers without
            // any persisted settings.
            log.info("[AppLocalMigration] Source prefs plist absent or unreadable — settings migration skipped.")
        }

        // STEP 5: Verify dictionary is present and count its entries.
        // The real storage format is [String: DictionaryMetadata] — a JSON object keyed
        // by original term. Count top-level keys via JSONSerialization to avoid importing
        // DictionaryService types here (decoupled layer boundary).
        let dictEntryCount: Int
        if let dictData = destDefaults.data(forKey: "customDictionaryMetadata") {
            if let obj = try? JSONSerialization.jsonObject(with: dictData) as? [String: Any] {
                dictEntryCount = obj.count
            } else {
                log.warning("[AppLocalMigration] Dictionary data present but not decodable as [String: DictionaryMetadata] JSON object — migration continues.")
                dictEntryCount = 0
            }
        } else {
            dictEntryCount = 0
        }

        // STEP 6: Write completion flag LAST — only after all assets verified.
        destDefaults.set(true, forKey: migratedKey)
        log.info("[AppLocalMigration] COMPLETE — migrated \(destCount) history entries, \(dictEntryCount) dictionary entries")
    }

    /// Union the source dictionary blob into the destination, entry by entry. Both are JSON
    /// objects keyed by the original term (`[String: DictionaryMetadata]`), stored as `Data`.
    /// A key already present in the destination is left untouched (app-local wins); keys only
    /// in the source are added. Decoupled from DictionaryService types — operates on the raw
    /// JSON object so the migration layer keeps no dependency on the dictionary model.
    private static func mergeDictionaryBlob(from sourceValue: Any?, into destDefaults: UserDefaults) {
        guard let sourceData = sourceValue as? Data,
              let sourceObj = (try? JSONSerialization.jsonObject(with: sourceData)) as? [String: Any],
              !sourceObj.isEmpty else {
            return  // No source dictionary — nothing to merge.
        }

        var merged: [String: Any] = {
            guard let destData = destDefaults.data(forKey: "customDictionaryMetadata"),
                  let destObj = (try? JSONSerialization.jsonObject(with: destData)) as? [String: Any]
            else { return [:] }
            return destObj
        }()

        var added = 0
        for (key, value) in sourceObj where merged[key] == nil {
            merged[key] = value
            added += 1
        }

        if added > 0, let mergedData = try? JSONSerialization.data(withJSONObject: merged) {
            destDefaults.set(mergedData, forKey: "customDictionaryMetadata")
        }
        log.info("[AppLocalMigration] Dictionary merged — \(added) entries carried over from the group container.")
    }

    // MARK: - Errors

    private enum MigrationError: Error {
        case rowCountMismatch(source: Int, dest: Int)
    }

    // MARK: - Test Seam

    #if DEBUG
    /// Runs the migration with fully injected source and destination dependencies.
    /// Tests use this to avoid ever touching the real group container or
    /// UserDefaults.standard.
    ///
    /// Source settings/dictionary are read from the plist file at:
    ///   `<sourceContainerURL>/Library/Preferences/group.com.dicticus.plist`
    ///
    /// Tests must write this file directly into the source container directory
    /// (using PropertyListSerialization or NSDictionary.write(to:)) before calling
    /// this function — matching the same code path used in production.
    ///
    /// - Parameter sourceContainerURL: Root of the source container directory.
    ///   The DB is expected at `<sourceContainerURL>/Database/History.sqlite`.
    ///   The settings plist is expected at
    ///   `<sourceContainerURL>/Library/Preferences/group.com.dicticus.plist`.
    ///   Pass nil or a non-existent URL to simulate a fresh install.
    /// - Parameter destDefaults: UserDefaults suite for destination (receives the
    ///   migration-complete flag and migrated settings).
    /// - Parameter destDBProvider: Closure returning the root of the destination
    ///   container. The DB will be written to `<result>/Database/History.sqlite`.
    public static func runForTesting(
        sourceContainerURL: URL?,
        destDefaults: UserDefaults,
        destDBProvider: @escaping () -> URL
    ) throws {
        try migrate(
            sourceContainerURL: sourceContainerURL,
            destDefaults: destDefaults,
            destDBProvider: destDBProvider
        )
    }
    #endif
}
#endif
