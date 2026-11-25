import KeyboardShortcuts

// Per D-14: Hotkeys are user-configurable from the start.
// Per D-04/D-05: Fn key not supported by KeyboardShortcuts (RESEARCH.md Pitfall 1).
// Using Control+Shift+S (dictation) and Control+Shift+D (cleanup) as defaults
// per RESEARCH.md Open Question 1 recommendation.
extension KeyboardShortcuts.Name {
    /// Plain dictation hotkey — hold to record, release to transcribe and paste.
    /// Default: Control+Shift+S (per RESEARCH.md, Fn+Shift not supported by KeyboardShortcuts).
    static let plainDictation = Self("plainDictation", default: .init(.s, modifiers: [.control, .shift]))

    /// AI cleanup hotkey — registered in Phase 3, wired to LLM pipeline in Phase 4.
    /// Default: Control+Shift+D (per RESEARCH.md, Fn+Control not supported by KeyboardShortcuts).
    static let aiCleanup = Self("aiCleanup", default: .init(.d, modifiers: [.control, .shift]))

    /// Revert-to-raw hotkey — re-pastes the raw ASR text of the last dictation (R-06).
    /// No default binding: this is an opt-in safety-valve action, not a primary hotkey,
    /// so it must never silently claim a key combination the user hasn't chosen.
    static let revertToRaw = Self("revertToRaw", default: nil)
}
