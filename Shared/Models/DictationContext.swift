import Foundation

/// Phase 38 Plan 01 (CTXFMT-01/CTXFMT-02, D-04): per-dictation formatting
/// context. Resolved once at hotkey press-time from the frontmost app's
/// bundle ID (see `ContextResolver` + `HotkeyManager`) and threaded through
/// `CleanupPrompt.build(context:)` and `TextProcessingService`'s Step 3a.6
/// finishing-capitalization gate.
///
/// Mirrors the shape of `CleanupPrompt.Variant`
/// (`Shared/Models/CleanupPrompt.swift`) but additionally conforms to
/// `Codable`: this enum round-trips through the DEBUG_RECORDER JSONL
/// (`resolved_context: String?`, raw value only) and — starting Plan 38-03 —
/// the guarded per-app override map persisted via `DicticusDefaults`.
///
/// D-04: exactly 3 cases in v1. Every context routes through exactly one
/// prompt-variant path in `CleanupPrompt.build` — do not add a 4th case
/// without a phase-level decision.
public enum DictationContext: String, CaseIterable, Sendable, Codable {
    case code
    case prose
    case `default`
}
