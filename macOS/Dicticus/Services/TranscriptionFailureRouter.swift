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
    /// `.inputUnavailable`/`.inputInterrupted` notify: a hold whose audio vanished must never route silent.
    static func route(_ error: TranscriptionError) -> TranscriptionFailureOutcome {
        switch error {
        case .tooShort, .silenceOnly, .noResult:
            return .silent
        case .unexpectedLanguage:
            return .notifyUnexpectedLanguage
        case .modelNotReady, .notRecording, .busy, .inputUnavailable, .inputInterrupted:
            return .notifyTranscriptionFailed
        }
    }

    /// What the end of a hold does with the audio it holds.
    enum HoldEnd: Equatable, Sendable {
        case transcribe
        case transcribeWithLossNotice
        case failInterrupted
    }

    /// Below the duration guard's minimum the decode would discard the clip silently, and 261018-go0's rule
    /// is that a hold whose audio vanished must notify.
    static func holdEnd(audioLost: Bool, capturedSeconds: Double, minimumSeconds: Double) -> HoldEnd {
        guard audioLost else { return .transcribe }
        return capturedSeconds >= minimumSeconds ? .transcribeWithLossNotice : .failInterrupted
    }

    /// Speech after the stop was lost, so a captured part that decodes to nothing must not end silently.
    static func afterInputLoss(_ error: TranscriptionError) -> TranscriptionError {
        route(error) == .silent ? .inputInterrupted : error
    }

    /// Audio counts as lost when the engine is down at key-up, or when restarts left a silent gap longer
    /// than `maxGapMs` in the hold (shorter gaps are a pause the recording never noticed).
    static func audioLost(engineRunning: Bool, totalGapMs: Double, maxGapMs: Double) -> Bool {
        !engineRunning || totalGapMs > maxGapMs
    }
}
