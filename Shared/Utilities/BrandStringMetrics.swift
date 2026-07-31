import Foundation

/// Orthographic string-similarity metrics for the brand-name matcher (Phase 36.5).
///
/// Two pure metrics over extended grapheme clusters (`[Character]`), mirroring the
/// grapheme-correct style of `LevenshteinDistance`:
///   - `damerauLevenshtein`: restricted edit distance (Optimal String Alignment,
///     a.k.a. OSA) — Levenshtein plus an adjacent-transposition operation.
///   - `jaroWinkler`: Jaro similarity with the Winkler common-prefix boost.
///
/// These are **pure metrics**: they do NOT lowercase, NFC-normalize, or strip
/// characters. Normalization (NFC + umlaut policy) is the caller's job — the
/// matcher in 36.5-04 owns it. Operating on `Character` means a precomposed
/// `é` (U+00E9) or an umlaut counts as one grapheme, never multiple code units.
///
/// `LevenshteinDistance` is intentionally untouched: it is the calibrated signal
/// source for `CleanupService.gateLLMOutput`. These metrics live alongside it
/// rather than modifying it.
public enum BrandStringMetrics {

    /// Restricted Damerau-Levenshtein distance (Optimal String Alignment / OSA):
    /// single-character insert / delete / substitute **plus** adjacent
    /// transposition, where no substring is edited more than once.
    ///
    /// OSA vs. unrestricted Damerau-Levenshtein differs only on edits that reuse
    /// a transposed region (the classic example: `CA` → `ABC` is **3** under OSA,
    /// 2 under unrestricted DL). At the `dl ≤ 2` thresholds the matcher uses the
    /// difference is negligible, so OSA is sufficient (RESEARCH §1).
    ///
    /// Contract: identity → 0; both-empty → 0; one-empty → length of the other.
    public static func damerauLevenshtein(_ s1: String, _ s2: String) -> Int {
        let a = Array(s1)
        let b = Array(s2)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }

        // Three live rows: `prevPrev` (i-2) is needed for the transposition
        // lookback, `prev` (i-1), and `curr` (i).
        var prevPrev = Array(repeating: 0, count: b.count + 1)
        var prev = Array(0...b.count)
        var curr = Array(repeating: 0, count: b.count + 1)

        for i in 1...a.count {
            curr[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                var best = min(
                    prev[j] + 1,        // deletion from a
                    curr[j - 1] + 1,    // insertion into a
                    prev[j - 1] + cost  // substitution (or match)
                )
                // Adjacent transposition (OSA): a[i-1]==b[j-2] && a[i-2]==b[j-1].
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    best = min(best, prevPrev[j - 2] + 1)
                }
                curr[j] = best
            }
            // Rotate rows: prevPrev <- prev <- curr, reuse prevPrev's storage as next curr.
            let recycled = prevPrev
            prevPrev = prev
            prev = curr
            curr = recycled
        }

        return prev[b.count]
    }

    /// Jaro-Winkler similarity in `[0.0, 1.0]` (1.0 = identical).
    ///
    /// Standard Jaro similarity (matching window `max(len)/2 - 1`, half the
    /// out-of-order matches counted as transpositions) plus the Winkler boost
    /// for a common prefix of up to 4 characters (scaling factor 0.1).
    ///
    /// Contract: identical → 1.0; both-empty → 1.0; exactly one empty → 0.0;
    /// no shared characters → 0.0.
    public static func jaroWinkler(_ s1: String, _ s2: String) -> Double {
        let a = Array(s1)
        let b = Array(s2)
        if a.isEmpty && b.isEmpty { return 1.0 }
        if a.isEmpty || b.isEmpty { return 0.0 }
        if a == b { return 1.0 }

        let matchDistance = max(a.count, b.count) / 2 - 1
        // A negative window (very short strings) means only exact-position matches.
        let window = max(matchDistance, 0)

        var aMatched = Array(repeating: false, count: a.count)
        var bMatched = Array(repeating: false, count: b.count)
        var matches = 0

        for i in 0..<a.count {
            let lo = max(0, i - window)
            let hi = min(i + window, b.count - 1)
            if lo > hi { continue }
            for j in lo...hi where !bMatched[j] && a[i] == b[j] {
                aMatched[i] = true
                bMatched[j] = true
                matches += 1
                break
            }
        }

        if matches == 0 { return 0.0 }

        // Count transpositions: walk the matched characters of each string in
        // order and compare; half the mismatches are transpositions.
        var transpositions = 0
        var k = 0
        for i in 0..<a.count where aMatched[i] {
            while !bMatched[k] { k += 1 }
            if a[i] != b[k] { transpositions += 1 }
            k += 1
        }
        let t = Double(transpositions) / 2.0
        let m = Double(matches)
        let jaro = (m / Double(a.count) + m / Double(b.count) + (m - t) / m) / 3.0

        // Winkler boost: common prefix up to 4 chars, scaling factor 0.1.
        var prefix = 0
        let maxPrefix = min(4, min(a.count, b.count))
        while prefix < maxPrefix && a[prefix] == b[prefix] { prefix += 1 }

        return jaro + Double(prefix) * 0.1 * (1.0 - jaro)
    }
}
