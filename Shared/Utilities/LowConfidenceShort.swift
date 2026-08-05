import Foundation

/// SPIKE-PROVISIONAL predicate for catastrophically garbled short dictations
/// (quick task 260805-qx7). Both constants below are sourced from a hand-found
/// 4-record sample and were measured against a 191-record blind-labeled corpus
/// in `.planning/quick/260805-qx7-confidence-warning-spike-low-confidence-/SPIKE.md`
/// — READ THAT FILE before trusting these values or building any user-facing
/// feature on top of them.
///
/// Measured result (SPIKE.md, do not re-derive without reading it first): NOT
/// SHIPPABLE as a user-facing signal today. No (duration, threshold) cell in
/// the tested grid achieves zero false positives — the dominant offender is a
/// confident ASR mishearing of a brand name ("Fable 5" -> "Favo-Phi", mean
/// avg_log_prob -0.64, comfortably past every threshold tested) that no
/// threshold in this constant's plausible range can exclude without also
/// losing most of the already-low recall (28.6% at the shipped default).
/// These two constants (5.0s / -0.35) are kept as-is because the grid found no
/// better alternative in the tested range, NOT because they were validated —
/// see SPIKE.md section 6 for the full recommendation and what additional
/// evidence would settle it. This remains a DEBUG_RECORDER-only diagnostic
/// signal; nothing user-facing is gated on it.
///
/// Kept pure over `[Float]` (no WhisperKit import) so callers pass
/// `allSegments.map(\.avgLogprob)` and the predicate is directly unit-testable
/// with plain arrays, following the house style of `NoSpeechDiscard.swift`.
///
/// This is purely a diagnostic signal today: the only call sites are inside
/// `#if DEBUG_RECORDER` blocks feeding `DiscardProbe`'s JSONL. The computed
/// value must never appear in a branch condition, `guard`, or ternary on the
/// live dictation path — it changes nothing about what the user sees or gets
/// pasted.
enum LowConfidenceShort {
    /// SPIKE-PROVISIONAL: clips at or above this duration (seconds) are never
    /// evaluated — a long clip containing one low-confidence segment is common
    /// and not itself evidence of a garble.
    static let maxDurationSeconds: Float = 5.0

    /// SPIKE-PROVISIONAL: mean avg_log_prob (Whisper's own per-segment
    /// confidence, arithmetic mean across all segments) below this value is
    /// treated as the garble signal, given the duration gate above also passes.
    static let meanAvgLogProbThreshold: Float = -0.35

    /// Returns `true` when `durationSeconds` is strictly less than
    /// `maxDuration` AND the arithmetic mean of `avgLogProbs` is strictly less
    /// than `threshold`.
    ///
    /// Degenerate default: an empty `avgLogProbs` array returns `false` —
    /// deliberately DIVERGING from `NoSpeechDiscard`'s vacuous-true default,
    /// because an empty segment list is already owned by the `noResult` guard
    /// and a no-evidence record must not be reported as a low-confidence one.
    static func flag(
        durationSeconds: Float,
        avgLogProbs: [Float],
        maxDuration: Float = maxDurationSeconds,
        threshold: Float = meanAvgLogProbThreshold
    ) -> Bool {
        guard durationSeconds < maxDuration else { return false }
        guard !avgLogProbs.isEmpty else { return false }
        let mean = avgLogProbs.reduce(0, +) / Float(avgLogProbs.count)
        return mean < threshold
    }
}
