import Foundation

/// Phase 38 Plan 01 (D-02/D-05/D-06): pure bundle-ID → `DictationContext`
/// resolution. Zero `import AppKit` / `NSWorkspace` — must stay compiled and
/// inert on iOS (D-02). The system-level frontmost-app *detection* call
/// lives only in `macOS/Dicticus/Services/HotkeyManager.swift`; this type
/// only resolves an already-captured bundle ID string, so it is trivially
/// unit-testable without any AppKit dependency.
public enum ContextResolver {

    /// Curated starter map (D-05/D-06) — built-in bundle-ID → context
    /// fallback for common apps. Guarded, user-editable override-map
    /// persistence lands in Plan 38-03; this is only the lowest-precedence
    /// built-in layer.
    public static let curatedMap: [String: DictationContext] = [
        "com.googlecode.iterm2": .code,
        "com.mitchellh.ghostty": .code,
        "com.apple.Terminal": .code,
        "com.apple.dt.Xcode": .code,
        "com.microsoft.VSCode": .code,
        "com.apple.Safari": .default,
        "com.google.Chrome": .default,
        "company.thebrowser.Browser": .default,
        "com.apple.mail": .prose,
        "com.apple.MobileSMS": .prose,
        "com.tinyspeck.slackmacgap": .prose,
    ]

    /// Resolution precedence, top to bottom:
    ///   1. `disabled == true` → `.default` (short-circuits everything else).
    ///   2. Explicit session `pin` non-nil → the pinned context.
    ///   3. `overrides[bundleID]` present → that context (user-editable, Plan 38-03).
    ///   4. `curatedMap[bundleID]` present → that context.
    ///   5. Otherwise → `.default` (includes unknown/nil bundle ID).
    public static func resolve(
        bundleID: String?,
        pin: DictationContext? = nil,
        disabled: Bool = false,
        overrides: [String: DictationContext] = [:]
    ) -> DictationContext {
        if disabled {
            return .default
        }
        if let pin {
            return pin
        }
        if let bundleID, let override = overrides[bundleID] {
            return override
        }
        if let bundleID, let curated = curatedMap[bundleID] {
            return curated
        }
        return .default
    }

    // MARK: - Guarded override-map persistence (Plan 38-03, CTXFMT-03, D-05)
    //
    // Mirrors DictionaryService.loadGuarded(from:key:)/save()'s present-but-
    // unreadable -> suppress-seed + rolling-backup contract verbatim in shape
    // (Shared/Services/DictionaryService.swift, three prior data-loss incidents
    // on this exact UserDefaults-blob shape). Never a fresh encoder.

    /// Persistence key for the user-editable bundle-ID → context override map.
    public static let overridesKey = "contextOverrides"

    /// Rolling one-step backup key: `save` copies the PREVIOUS persisted blob
    /// here before overwriting, so a single bad overwrite is always recoverable.
    public static let overridesBackupKey = "contextOverrides_prevBackup"

    /// Absent-key-default-true toggle key (D-09) — single source of truth
    /// shared by `HotkeyManager`'s press-time resolve call and the Settings
    /// disable toggle (`ContextAwareFormattingFormRow`).
    public static let enabledKey = "contextAwareFormattingEnabled"

    /// Pure/injectable guarded load. Reads the persisted override map from
    /// `defaults[key]` and reports whether it is SAFE to treat an empty
    /// result as a genuine absence. `suppressSeed` is true ONLY when a blob
    /// is PRESENT but never decodes even after a retry — the present-but-
    /// unreadable case a caller must NEVER overwrite. A genuinely absent
    /// blob (real first run / no overrides ever saved) returns
    /// `suppressSeed == false`, and — critically — a blob that is present
    /// AND decodes cleanly to a real, empty map (`"{}"`, e.g. a user removed
    /// their last override) ALSO returns `suppressSeed == false`: decode
    /// success/failure is tracked via an `Optional` result rather than
    /// collapsing both "decode failed" and "decoded to an empty dictionary"
    /// onto the same `[:]` sentinel (CR-01 fix — the collapsed sentinel let
    /// an ordinary add-then-remove-last-override flow spuriously report
    /// `suppressSeed == true`).
    nonisolated public static func loadGuarded(from defaults: UserDefaults, key: String) -> (overrides: [String: DictationContext], suppressSeed: Bool) {
        guard let data = defaults.data(forKey: key) else {
            return ([:], false)  // genuinely absent — first run, safe to treat as empty
        }
        func tryDecode() -> [String: DictationContext]? {
            try? JSONDecoder().decode([String: DictationContext].self, from: data)
        }
        if let decoded = tryDecode() ?? tryDecode() {   // one retry for a transient cfprefsd race
            return (decoded, false)   // present AND decodable — even if genuinely {}
        }
        return ([:], true)   // present but never decodes — the real unreadable case
    }

    /// Saves the override map, stashing the previous blob into `backupKey`
    /// before overwriting when it differs from the new value — the same
    /// rolling-backup contract as `DictionaryService.save()`.
    public static func save(_ overrides: [String: DictationContext], to defaults: UserDefaults, key: String, backupKey: String) {
        guard let data = try? JSONEncoder().encode(overrides) else { return }
        if let previous = defaults.data(forKey: key), previous != data {
            defaults.set(previous, forKey: backupKey)
        }
        defaults.set(data, forKey: key)
    }

    /// Absent-key default true (D-09) — read helper shared by every caller so
    /// there is exactly one place that defines "context-aware formatting is
    /// on unless explicitly turned off".
    public static func isEnabled(_ defaults: UserDefaults) -> Bool {
        defaults.object(forKey: enabledKey) == nil ? true : defaults.bool(forKey: enabledKey)
    }
}
