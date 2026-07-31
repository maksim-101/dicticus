import Foundation

/// Shared in-memory `UserDefaults` test double backed by a plain dictionary,
/// used across the DicticusTests bundles (macOS + iOS).
///
/// Replaces per-test `UserDefaults(suiteName: "<prefix>.<UUID>")` doubles.
/// Those leaked a plist per test run because cfprefsd rewrites the suite's
/// backing file AFTER the test process exits, defeating a `tearDown {
/// removePersistentDomain(...) }` call — the file reappears on disk anyway.
/// This double never registers a real suite and never touches CFPreferences,
/// so nothing is ever written to `~/Library/Preferences`.
///
/// Only the five primitive accessors below are overridden — the full set any
/// caller in this codebase (`ContextResolver`, `DictionaryService`) actually
/// exercises. Routing them through `storage` (NOT `data`, which would
/// collide with `data(forKey:)`) needs no custom initializer — the inherited
/// designated initializer creates no backing plist.
///
/// Originally introduced `fileprivate` in `AppLocalMigrationServiceTests.swift`
/// (quick task 260627-axy) and promoted to this shared, `internal` location so
/// every guard test that leaked a plist can reuse it (quick task 260728-ppj).
final class InMemoryUserDefaults: UserDefaults {
    private var storage: [String: Any] = [:]

    override func set(_ value: Any?, forKey key: String) {
        storage[key] = value
    }

    override func object(forKey key: String) -> Any? {
        storage[key]
    }

    override func removeObject(forKey key: String) {
        storage.removeValue(forKey: key)
    }

    override func bool(forKey key: String) -> Bool {
        storage[key] as? Bool ?? false
    }

    override func data(forKey key: String) -> Data? {
        storage[key] as? Data
    }
}
