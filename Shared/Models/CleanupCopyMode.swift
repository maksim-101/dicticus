import Foundation

/// Phase 20.05 ACT-3-VISIBILITY — cross-platform Copy-mode default.
///
/// Backs the per-row Copy buttons in HistoryView on both iOS and macOS, plus the
/// segmented controls in both Settings panels. The user's choice is persisted in
/// the standard UserDefaults suite under the canonical key `cleanupCopyMode`.
///
/// **Default:** `.raw` — per CONTEXT.md, the rules-cleaned raw output is the
/// trusted path until LLM trust is rebuilt post-Phase 20 UAT. The polished
/// (LLM-cleaned) variant remains opt-in until then.
///
/// **Precedence (per CONTEXT.md / RESEARCH.md):**
///   - List-row Copy buttons read `CleanupCopyMode.current` — the global default.
///   - Detail-view / inline-disclosure Copy buttons copy whatever variant the
///     user has explicitly selected in the Picker (the user's local choice
///     wins over the global default).
///
/// **Storage:** `UserDefaults.standard` (not the App Group suite). The Copy mode
/// is a UI preference scoped to the host app, not shared with the keyboard
/// extension; Phase 19's keyboard extension is currently disabled and the row
/// Copy actions only fire from the host app.
public enum CleanupCopyMode: String {
    case raw
    case polished

    /// Canonical UserDefaults key — both iOS Settings (`SettingsView.swift`) and
    /// macOS Settings (`SettingsSection.swift`) bind to this string. Changing
    /// the key string is a breaking change for round-tripping.
    public static let userDefaultsKey = "cleanupCopyMode"

    /// Read/write accessor backed by `UserDefaults.standard`. Unknown / missing
    /// values resolve to `.raw` — never trap on a corrupt value (matches the
    /// fail-soft pattern used elsewhere in the cleanup pipeline).
    public static var current: CleanupCopyMode {
        get {
            let stored = UserDefaults.standard.string(forKey: userDefaultsKey) ?? ""
            return CleanupCopyMode(rawValue: stored) ?? .raw
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: userDefaultsKey)
        }
    }
}
