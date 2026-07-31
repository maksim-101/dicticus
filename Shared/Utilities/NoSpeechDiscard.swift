import Foundation

/// Pure post-decode no-speech discard predicate — the concrete D-09 mechanism
/// (41-RESEARCH.md Pattern 3). WhisperKit does NOT auto-blank
/// `TranscriptionResult.text` when the audio is pure silence; `noSpeechProb` only
/// drives internal decoder fallback/retry behavior, not output suppression
/// (41-RESEARCH.md Pitfall 2). The app must inspect `segments[].noSpeechProb`
/// itself, immediately after `transcribe()` returns, before building
/// `DicticusTranscriptionResult`.
///
/// This is Layer 3 of the app's silence defense (Layer 1 = minimum-duration
/// guard; Layer 2 = AdaptiveVoiceGate, an input-energy gate reintroduced
/// 2026-07-05 cycle 2 after the original fixed-threshold EnergyVAD pre-filter
/// was removed in cycle 1 — see whisper-dictation-dropout debug session).
/// Layer 3 alone cannot catch a CONFIDENT Whisper silence hallucination (low
/// noSpeechProb by definition), which is why Layer 2 exists upstream of
/// WhisperKit entirely. This predicate is separate from — and does not
/// replace — the existing empty-result `noResult` guard: an empty segment list
/// is already handled there, so an empty `noSpeechProbs` array here is its own
/// degenerate case, not a double-discard of the same condition.
///
/// Kept pure over `[Float]` (no `import WhisperKit`) so callers pass
/// `segments.map(\.noSpeechProb)` and the predicate is directly unit-testable
/// with plain arrays — no live WhisperKit instance or segment type required.
enum NoSpeechDiscard {
    /// Returns `true` (discard as silence) when every segment's `noSpeechProb`
    /// exceeds `threshold`. Default `0.6` matches WhisperKit's own
    /// `DecodingOptions.noSpeechThreshold` default.
    ///
    /// Degenerate default: an empty `noSpeechProbs` array returns `true`
    /// (vacuous truth, matching Swift's `Sequence.allSatisfy` semantics used
    /// below — no segments means no evidence of speech). This default is
    /// pinned and documented here per the NoSpeechDiscardTests contract.
    static func looksLikeSilence(noSpeechProbs: [Float], threshold: Float = 0.6) -> Bool {
        noSpeechProbs.allSatisfy { $0 > threshold }
    }
}
