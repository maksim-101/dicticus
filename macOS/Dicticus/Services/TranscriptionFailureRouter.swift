/// Outcome of routing a caught `TranscriptionError` to a user-facing notification.
enum TranscriptionFailureOutcome: Equatable {
    /// No notification — expected outcome of an empty/silent capture, not an error.
    case silent
    /// Genuine failure: post the "transcription failed" notification.
    case notifyTranscriptionFailed
    /// ASR output contained a non-Latin script — post the language-specific notification.
    case notifyUnexpectedLanguage
}

/// Decides which `TranscriptionError` cases are silent vs. worth notifying the user
/// about. Split out of `HotkeyManager.handleKeyUp`'s catch block (quick task 260831-nt6)
/// so the SELECTION logic is unit-testable without a live `HotkeyManager`/
/// `TranscriptionService`/`UNUserNotificationCenter`.
enum TranscriptionFailureRouter {
    /// `.tooShort`/`.silenceOnly` were already silent (D-02/D-16). `.noResult` — WhisperKit
    /// completed and decoded literally nothing — joins them here: production evidence
    /// (discard-2026-08-31.jsonl) showed `.noResult` firing on deliberately-silent hotkey
    /// presses (RMS 0.0042-0.0054 vs. 0.015-0.018 for presses with real speech), i.e. it's
    /// AdaptiveVoiceGate's clip-relative noise floor letting ambient room noise register as
    /// "voice detected" on an otherwise-silent clip — not evidence the ASR model is broken.
    static func route(_ error: TranscriptionError) -> TranscriptionFailureOutcome {
        switch error {
        case .tooShort, .silenceOnly, .noResult:
            return .silent
        case .unexpectedLanguage:
            return .notifyUnexpectedLanguage
        case .modelNotReady, .notRecording, .busy:
            return .notifyTranscriptionFailed
        }
    }
}
