import Foundation

/// SPIKE-PROVISIONAL predicate for catastrophically garbled short dictations
/// (quick task 260805-qx7). Both constants below are sourced from a hand-found
/// 4-record sample (Aug 2-5 debug logs: durations 2.3-3.3s, mean avg_log_prob
/// -0.39...-0.47) and are NOT validated against a labeled corpus until
/// `.planning/quick/260805-qx7-confidence-warning-spike-low-confidence-/SPIKE.md`
/// says so — check that file before trusting these values or building any
/// user-facing feature on top of them.
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
