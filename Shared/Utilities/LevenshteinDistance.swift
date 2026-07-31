import Foundation

/// Edit distance between two strings, in O(m·n) time and O(min(m,n)) space.
///
/// Phase 20 D-01: this is the signal source for `CleanupService.gateLLMOutput`,
/// which compares the rules-cleaned text against the LLM output and rejects
/// the LLM result when the normalized distance exceeds the
/// `CleanupService.levenshteinGateThreshold` (0.30 of `max(len)`).
///
/// Operates on `Character` (extended grapheme clusters) so composed and
/// decomposed Unicode forms compare correctly when the strings use the same
/// normalization form. Naive UTF-8 / UTF-16 walking would count multi-byte
/// graphemes (e.g. precomposed `é` U+00E9) as multiple edits.
///
/// Memory:
///   - Two `Int` rows of size `min(m, n) + 1` are kept live during the inner
///     loop (`prev` and `curr`), giving O(min(m,n)) extra space.
///   - No full m×n matrix is allocated.
///
/// Performance budget:
///   - Dictation inputs are ≤ 2 KB. At 2 KB × 2 KB the dominant cost is
///     ~4M Int comparisons, well under 10 ms even on the slowest supported
///     Apple Silicon. No batching / chunking needed.
///
/// Coarseness contract (documented by the tests):
///   - Word-substitution hallucinations (e.g. `Franken` ↔ `Euro`) ARE
///     detectable — that is the gate's primary signal.
///   - Morpheme-level hallucinations (e.g. `ausgeflogen` ↔ `ausgezogen`)
///     slip through; the gate is intentionally a coarse fail-safe, not a
///     semantic oracle. Higher-confidence checks live in the rules pass.
public enum LevenshteinDistance {

    /// Edit distance — count of single-character insert / delete / substitute
    /// operations required to transform `s1` into `s2`.
    ///
    /// Symmetry holds: `distance(a, b) == distance(b, a)`.
    public static func distance(_ s1: String, _ s2: String) -> Int {
        // Operate on `Character` arrays so we count grapheme clusters,
        // not UTF-8 / UTF-16 code units.
        let a = Array(s1)
        let b = Array(s2)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }

        // Two-row optimization: only `prev` and `curr` rows are kept live.
        // Initialize `prev` as the distance from the empty prefix of `a` to
        // each prefix of `b` (0, 1, 2, ..., b.count).
        var prev = Array(0...b.count)
        var curr = Array(repeating: 0, count: b.count + 1)

        for i in 1...a.count {
            curr[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                curr[j] = min(
                    prev[j] + 1,         // deletion from a
                    curr[j - 1] + 1,     // insertion into a
                    prev[j - 1] + cost   // substitution (or match)
                )
            }
            swap(&prev, &curr)
        }

        return prev[b.count]
    }

    /// Normalized edit distance in `[0.0, 1.0]` using `max(len(s1), len(s2))`
    /// as the denominator. Returns `0.0` when both inputs are empty (the 0/0
    /// case must resolve to 0.0, not NaN — implementation contract).
    ///
    /// The `CleanupService.levenshteinGateThreshold` (0.30) is calibrated
    /// against this specific normalization. Do not change the denominator
    /// without re-tuning the gate.
    public static func normalizedDistance(_ s1: String, _ s2: String) -> Double {
        let d = distance(s1, s2)
        let denom = max(s1.count, s2.count)
        return denom == 0 ? 0.0 : Double(d) / Double(denom)
    }
}
