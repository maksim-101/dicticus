import Foundation

/// Platform-conditional UserDefaults suite.
/// macOS: .standard (app-local, no group entitlement needed).
/// iOS: group.com.dicticus suite (Shortcuts IPC + keyboard extension).
public enum DicticusDefaults {
    /// Test-only override consulted FIRST by `suite`, before the platform branch.
    /// `DicticusTestBootstrap` (the DicticusTests bundle's `NSPrincipalClass`) sets
    /// this before any XCTestCase loads, so every reader of `suite` — including
    /// `DictionaryService.shared`, a process-wide singleton — is redirected to an
    /// ephemeral store for the entire test process. `nil` in production, so
    /// production behavior is unchanged.
    ///
    /// Exists because of the 2026-07-24 incident: an XCTest run silently wrote
    /// through to the real com.dicticus.app UserDefaults domain and wiped the
    /// user's live dictionary.
    public nonisolated(unsafe) static var overrideForTesting: UserDefaults?

    public static var suite: UserDefaults {
        if let override = overrideForTesting {
            return override
        }
#if os(macOS)
        return .standard
#else
        return UserDefaults(suiteName: "group.com.dicticus") ?? .standard
#endif
    }

    /// Swiss German spelling and number format. A missing key means ON, matching both settings screens.
    public static var useSwissGerman: Bool {
        let key = SwissDefaultMigration.toggleKey
        return suite.object(forKey: key) == nil ? true : suite.bool(forKey: key)
    }
}
