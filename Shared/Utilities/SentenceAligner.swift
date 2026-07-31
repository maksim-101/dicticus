import Foundation
import NaturalLanguage

/// Phase 36.6 Rethink R-02 (CLEANRD-03): sentence-alignment utility for the
/// per-sentence phonetic gate (Plan 09 wires this into
/// `CleanupService.gatePerSentence`).
///
/// The prior whole-utterance `gateContentWords` gate reverts an ENTIRE
/// utterance's LLM polish over a single bad edit anywhere in it (the UAT
/// segment-2 failure). This utility pairs baseline (rules-cleaned) sentences
/// with LLM-output sentences into windows so the gate can accept/reject PER
/// SENTENCE instead.
///
/// INVARIANT: ambiguous alignment degrades to a SINGLE whole-utterance
/// window — never worse than the currently-shipped whole-utterance
/// `gateContentWords` gate. Empty/degenerate input always returns one
/// whole-utterance window; this utility never crashes or throws.
///
/// `@MainActor`: reuses `CleanupService.tokenizeForDialectGate` (declared on
/// the `@MainActor`-isolated `CleanupService` class) for the Jaccard
/// word-overlap computation rather than hand-rolling a second tokenizer.
@MainActor
public struct SentenceAligner {

    /// [ASSUMED A1] Mean-Jaccard confidence floor below which alignment is
    /// considered too ambiguous to trust — degrades to a whole-utterance
    /// window. Starting point per 36.6-RESEARCH.md Pattern 1 step 6; Plan 11
    /// tunes this against the eval_set + R-04 corpus before shipping.
    private static let meanJaccardFloor = 0.3

    // MARK: - Public entry point

    /// Aligns `baseline` (rules-cleaned text) and `output` (post
    /// strip/leak-guard LLM text) into `(baseline, output)` windows, one per
    /// matched sentence span.
    ///
    /// Graceful-degradation contract: empty/whitespace-only input on either
    /// side, degenerate sentence counts (<=1 sentence on either side), and
    /// low alignment confidence (mean word-overlap below the floor, or a
    /// sentence-count mismatch of more than half) all return exactly ONE
    /// whole-utterance window `[(baseline, output)]` — never a crash, never
    /// a partial/inconsistent result.
    public static func align(
        baseline: String,
        output: String
    ) -> [(baseline: String, output: String)] {
        let wholeUtterance: [(baseline: String, output: String)] = [(baseline, output)]

        guard !baseline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return wholeUtterance
        }

        let baselineSentences = splitSentences(baseline)
        let outputSentences = splitSentences(output)
        let n = baselineSentences.count
        let m = outputSentences.count

        // DEGENERATE CASE (Pattern 1 step 3): most common for short
        // push-to-talk utterances — no per-sentence subdivision
        // possible/needed, run whole-utterance treatment.
        guard n > 1, m > 1 else { return wholeUtterance }

        // SIMPLE CASE (Pattern 1 step 4): 1:1 index alignment.
        // MERGE/SPLIT CASE (Pattern 1 step 5): greedy monotonic walk.
        let windows: [(baseline: String, output: String)] = n == m
            ? Array(zip(baselineSentences, outputSentences))
            : greedyMonotonicAlign(baselineSentences: baselineSentences, outputSentences: outputSentences)

        // FALLBACK / DEGRADE RULE (Pattern 1 step 6).
        guard isConfident(windows: windows, n: n, m: m) else { return wholeUtterance }
        return windows
    }

    // MARK: - Sentence splitting (lossless reconstruction)

    /// Splits `text` into sentences using `NLTokenizer(unit: .sentence)`,
    /// extending each sentence's range to absorb trailing punctuation and
    /// whitespace up to the start of the next sentence (or to the end of the
    /// string for the last sentence) so that concatenating the results
    /// reproduces `text` exactly, in order.
    private static func splitSentences(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }

        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text

        var ranges: [Range<String.Index>] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            ranges.append(range)
            return true
        }
        guard !ranges.isEmpty else { return [text] }

        var sentences: [String] = []
        sentences.reserveCapacity(ranges.count)
        for (index, range) in ranges.enumerated() {
            let start = index == 0 ? text.startIndex : range.lowerBound
            let end = index + 1 < ranges.count ? ranges[index + 1].lowerBound : text.endIndex
            sentences.append(String(text[start..<end]))
        }
        return sentences
    }

    // MARK: - Greedy monotonic merge/split alignment (Pattern 1 step 5)

    /// Walks `outputSentences` left to right. For each output sentence,
    /// greedily consumes 1 or 2 not-yet-consumed `baselineSentences` —
    /// whichever consumption count MAXIMIZES Jaccard word-overlap between
    /// the output sentence's tokens and the union of the consumed baseline
    /// sentences' tokens. Never looks backward (utterance order is
    /// monotonic). Symmetrically, when only one baseline sentence remains
    /// but two or more output sentences remain, groups all remaining output
    /// sentences into one window against that single baseline sentence (the
    /// LLM split a run-on).
    ///
    /// Does NOT build a full Needleman-Wunsch DP (RESEARCH Anti-Pattern
    /// A4) — greedy is sufficient for typical <=5-sentence push-to-talk
    /// utterances; the confidence/degrade check below is the safety net for
    /// cases where greedy alignment is wrong.
    private static func greedyMonotonicAlign(
        baselineSentences: [String],
        outputSentences: [String]
    ) -> [(baseline: String, output: String)] {
        var windows: [(baseline: String, output: String)] = []
        var baselineIndex = 0
        var outputIndex = 0
        let n = baselineSentences.count
        let m = outputSentences.count

        while outputIndex < m {
            let remainingBaseline = n - baselineIndex
            let remainingOutput = m - outputIndex

            guard remainingBaseline > 0 else {
                // No baseline left to pair — fold any remaining output
                // sentences into the last window rather than dropping them.
                if windows.isEmpty {
                    windows.append((baseline: "", output: outputSentences[outputIndex]))
                } else {
                    let last = windows.removeLast()
                    windows.append((baseline: last.baseline, output: last.output + " " + outputSentences[outputIndex]))
                }
                outputIndex += 1
                continue
            }

            if remainingOutput >= 2, remainingBaseline == 1 {
                // SPLIT: the single remaining baseline sentence spans all
                // remaining output sentences (LLM split a run-on).
                let mergedOutput = outputSentences[outputIndex...].joined(separator: " ")
                windows.append((baseline: baselineSentences[baselineIndex], output: mergedOutput))
                baselineIndex += 1
                outputIndex = m
                continue
            }

            let outputTokens = Set(tokenize(outputSentences[outputIndex]))
            let oneBaselineTokens = Set(tokenize(baselineSentences[baselineIndex]))
            let oneScore = jaccard(outputTokens, oneBaselineTokens)

            var consumeTwo = false
            if remainingBaseline >= 2 {
                let twoBaselineTokens = oneBaselineTokens.union(tokenize(baselineSentences[baselineIndex + 1]))
                let twoScore = jaccard(outputTokens, twoBaselineTokens)
                consumeTwo = twoScore > oneScore
            }

            if consumeTwo {
                let mergedBaseline = baselineSentences[baselineIndex] + " " + baselineSentences[baselineIndex + 1]
                windows.append((baseline: mergedBaseline, output: outputSentences[outputIndex]))
                baselineIndex += 2
            } else {
                windows.append((baseline: baselineSentences[baselineIndex], output: outputSentences[outputIndex]))
                baselineIndex += 1
            }
            outputIndex += 1
        }

        // Defensive: fold any unconsumed baseline sentences into the last
        // window rather than silently dropping content (should not occur
        // for the |N-M| ratios that survive the confidence check below).
        if baselineIndex < n {
            let leftover = baselineSentences[baselineIndex...].joined(separator: " ")
            if windows.isEmpty {
                windows.append((baseline: leftover, output: ""))
            } else {
                let last = windows.removeLast()
                windows.append((baseline: last.baseline + " " + leftover, output: last.output))
            }
        }

        return windows
    }

    // MARK: - Confidence check (Pattern 1 step 6 — the degrade/fallback rule)

    /// After building windows, computes the mean per-window Jaccard overlap.
    /// Degrades (returns `false`) when the mean is below `meanJaccardFloor`
    /// OR when `|N - M| > max(N, M) / 2` (more than half the sentences lack
    /// a clean correspondence) — guaranteeing the per-sentence gate is never
    /// worse than the shipped whole-utterance gate.
    private static func isConfident(
        windows: [(baseline: String, output: String)],
        n: Int,
        m: Int
    ) -> Bool {
        guard !windows.isEmpty else { return false }

        let scores = windows.map { window in
            jaccard(Set(tokenize(window.baseline)), Set(tokenize(window.output)))
        }
        let meanScore = scores.reduce(0, +) / Double(scores.count)

        let countMismatch = Double(abs(n - m)) > Double(max(n, m)) / 2.0
        return meanScore >= meanJaccardFloor && !countMismatch
    }

    // MARK: - Tokenization + Jaccard overlap

    /// Reuses the existing lowercasing + punctuation-stripping tokenizer
    /// (`CleanupService.tokenizeForDialectGate`) rather than hand-rolling a
    /// second one, per 36.6-RESEARCH.md Pattern 1 / 36.6-PATTERNS.md.
    private static func tokenize(_ s: String) -> [String] {
        CleanupService.tokenizeForDialectGate(s)
    }

    private static func jaccard(_ a: Set<String>, _ b: Set<String>) -> Double {
        if a.isEmpty && b.isEmpty { return 1.0 }
        let intersection = a.intersection(b).count
        let union = a.union(b).count
        guard union > 0 else { return 1.0 }
        return Double(intersection) / Double(union)
    }
}
