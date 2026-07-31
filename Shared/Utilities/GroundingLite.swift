import Foundation

/// Phase 36.6 Plan 04 (CLEANRD-03): grounding-lite deterministic backstops.
///
/// The v-next prompt (Plan 03) does the semantic anti-invention work. These
/// two pure, deterministic functions are the HARD guarantee behind that soft
/// prompt for the residual invention it could occasionally miss on unseen
/// input — per spike-010 track-A root cause + BAKEOFF-RESULTS.md "Grounding-
/// lite validation" (altered 0/20 clean-passthrough outputs).
///
/// INVARIANT: grounding-lite may only REMOVE/REVERT toward the input — it
/// never invents or rewrites. Acceptable failure = a miss, never a
/// corruption. Both functions are identity on inputs with nothing to fix.
public struct GroundingLite {

    // MARK: - Leak-strip (track-A §1.1 / §1.4)

    /// The 8 DE few-shot `Out:` constants that used to live in
    /// `CleanupPrompt.swift:149-172` before Plan 03 removed them from the
    /// prompt builder. The v-next prompt is few-shot-free, so any occurrence
    /// of these lines in LLM output is the model reproducing its own prior
    /// training/context rather than genuine correction — this is the
    /// deterministic hard-0 backstop for that leak family.
    ///
    /// Verbatim, including the raw ß form of "Großteil" — leak-strip runs
    /// BEFORE Swiss ß→ss conversion (per track-A §1.4) so it matches the
    /// model's actual raw output.
    static let deLeakConstants: [String] = [
        "Das Meeting ist um fünf.",
        "Meeting um neun, nein eigentlich um acht.",
        "Ich möchte einen Termin machen.",
        "Wir gehen ins Krankenhaus.",
        "Bitte prüfe, ob in der Zwischenzeit neue Rückmeldungen kamen.",
        "Für den Großteil.",
        "Ich habe drei Termine heute.",
        "Kannst du mir sagen, wie spät es ist?"
    ]

    /// Removes a leading contiguous run of >=2 sentences that exactly match
    /// (byte/whitespace/ß-ss-tolerant) known DE few-shot `Out:` constants,
    /// stopping at the first non-matching sentence.
    ///
    /// - A single leading match is left untouched (>=2 required) — a user who
    ///   genuinely dictates one canned-sounding sentence is never truncated.
    /// - DE-scoped: EN input (or any `language` other than "de") is returned
    ///   unchanged.
    /// - Only ever removes a verbatim-matching leading run; never touches the
    ///   genuine body once a non-matching sentence is reached.
    public static func stripLeadingLeak(_ output: String, language: String) -> String {
        guard language == "de" else { return output }

        let normalizedConstants = Set(deLeakConstants.map(normalizeForLeakMatch))
        var working = output
        var matchedCount = 0

        while let (sentence, remainder) = extractLeadingSentence(working) {
            guard normalizedConstants.contains(normalizeForLeakMatch(sentence)) else { break }
            matchedCount += 1
            working = remainder
        }

        guard matchedCount >= 2 else { return output }
        return working.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Extracts the leading "sentence" (up to and including the first
    /// `.`/`!`/`?`) from `text`, returning `(sentence, remainder)`. Returns
    /// `nil` when `text` is empty after trimming, or contains no sentence
    /// terminator (a genuine tail fragment can never match a known constant,
    /// all of which end in terminal punctuation, so the loop simply stops).
    private static func extractLeadingSentence(_ text: String) -> (sentence: String, remainder: String)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let terminators: Set<Character> = [".", "!", "?"]
        guard let terminatorIndex = trimmed.firstIndex(where: { terminators.contains($0) }) else { return nil }
        let sentenceEnd = trimmed.index(after: terminatorIndex)
        let sentence = String(trimmed[trimmed.startIndex..<sentenceEnd])
        let remainder = String(trimmed[sentenceEnd...])
        return (sentence, remainder)
    }

    /// Whitespace-collapsed, ß-normalized-to-ss comparison key. Makes
    /// "Für den Großteil." and "Für den Grossteil." compare equal, and
    /// tolerates any incidental whitespace differences from token-by-token
    /// LLM detokenization.
    private static func normalizeForLeakMatch(_ s: String) -> String {
        let collapsed = s
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return collapsed.replacingOccurrences(of: "ß", with: "ss")
    }

    // MARK: - Injected "Known terms" hint leak-strip (Phase 36.6 UAT 2026-07-03)

    /// Removes a leading regurgitation of the "Known terms — …" dictionary hint
    /// that `CleanupPrompt` injects into the user turn (CleanupPrompt.swift:77).
    /// Qwen sometimes echoes that block (paraphrased, e.g. "EXACTLY"→"exactly")
    /// ahead of the real output; it then passes the content-word gate (which
    /// guards against dropped, not added, content) and ships to the user's cursor
    /// (observed on-device 2026-07-03, cleanup log entry 20). This is the
    /// deterministic backstop for that leak family — language-agnostic, since the
    /// injected hint is English even for DE dictation.
    ///
    /// Strips only a LEADING block that (a) opens with a `Known terms … as shown:`
    /// header line and (b) is separated from the body by a blank line — exactly the
    /// shape `CleanupPrompt` emits. Everything from the first blank line onward is
    /// preserved. If the header signature or the blank-line boundary is absent, the
    /// input is returned unchanged (a miss, never a corruption — same invariant as
    /// `stripLeadingLeak`).
    public static func stripLeakedKnownTerms(_ output: String) -> String {
        let leading = output.drop(while: { $0.isWhitespace })
        guard let firstLineEnd = leading.firstIndex(of: "\n") else { return output }
        let headerLower = leading[leading.startIndex..<firstLineEnd]
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        guard headerLower.hasPrefix("known terms"), headerLower.hasSuffix("as shown:") else { return output }

        // Body begins after the first blank line (\n[ \t]*\n) — the separator the
        // injection places between the mapping lines and the dictated text.
        let s = String(leading)
        let ns = s as NSString
        guard let regex = try? NSRegularExpression(pattern: "\\n[ \\t]*\\n") else { return output }
        guard let match = regex.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return output }
        let body = ns
            .substring(from: match.range.location + match.range.length)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return output }
        return body
    }

    // MARK: - Letter-expansion guard (eval_set.json en-inve-030/032)

    /// Suffix markers the LLM sometimes appends to a bare dictated letter,
    /// misreading it as a language/tech token (C -> C++/C#).
    private static let letterExpansionSuffixes = ["++", "#", "＃"]

    /// Matches a standalone single ASCII letter, optionally immediately
    /// followed by one of the expansion suffixes, bounded so it never matches
    /// inside a larger word (e.g. the "a" in "cat").
    private static let letterTokenPattern =
        #"(?<![A-Za-z0-9])([A-Za-z])(\+\+|[#＃])?(?![A-Za-z0-9])"#

    // try! is correct: pattern is a compile-time constant literal, validated at authoring time.
    private static let letterTokenRegex: NSRegularExpression = try! NSRegularExpression(pattern: letterTokenPattern)

    /// Reverts a single dictated letter that the LLM rendered as letter+`#`,
    /// letter+`++`, or letter+`＃` back to the bare letter.
    ///
    /// Conservative by construction: a letter is only eligible for reversion
    /// when it appeared as a BARE standalone token in `input` AND never
    /// appeared with an expansion suffix in `input` — so a genuinely dictated
    /// "C++" (present as "C++" in the input, not as bare "C") is left
    /// untouched. Matching is case-insensitive (ASR renders spelled-out
    /// letters inconsistently), but the reversion preserves the OUTPUT's own
    /// casing — it simply drops the suffix.
    public static func guardLetterExpansion(input: String, output: String) -> String {
        let (bareLetters, suffixedLetters) = classifyLetterTokens(in: input)
        let eligibleLetters = bareLetters.subtracting(suffixedLetters)
        guard !eligibleLetters.isEmpty else { return output }

        let nsOutput = output as NSString
        let fullRange = NSRange(location: 0, length: nsOutput.length)
        let matches = letterTokenRegex.matches(in: output, options: [], range: fullRange)

        var result = output
        // Reverse order: earlier match offsets stay valid in `result` while
        // later (higher-offset) replacements are applied first.
        for match in matches.reversed() {
            guard match.numberOfRanges >= 3 else { continue }
            let letterRange = match.range(at: 1)
            let suffixRange = match.range(at: 2)
            guard letterRange.location != NSNotFound, suffixRange.location != NSNotFound else { continue }

            let letterString = nsOutput.substring(with: letterRange)
            guard let letterChar = letterString.lowercased().first else { continue }
            guard eligibleLetters.contains(letterChar) else { continue }

            guard let fullMatchRange = Range(match.range, in: result) else { continue }
            result.replaceSubrange(fullMatchRange, with: letterString)
        }
        return result
    }

    /// Scans `text` for standalone letter tokens, classifying each letter
    /// (lowercased) into `bare` (no expansion suffix present) or `suffixed`
    /// (expansion suffix present) sets.
    private static func classifyLetterTokens(in text: String) -> (bare: Set<Character>, suffixed: Set<Character>) {
        var bare = Set<Character>()
        var suffixed = Set<Character>()

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        letterTokenRegex.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match, match.numberOfRanges >= 3 else { return }
            let letterRange = match.range(at: 1)
            guard letterRange.location != NSNotFound else { return }
            guard let letterChar = nsText.substring(with: letterRange).lowercased().first else { return }

            let suffixRange = match.range(at: 2)
            if suffixRange.location != NSNotFound {
                suffixed.insert(letterChar)
            } else {
                bare.insert(letterChar)
            }
        }
        return (bare, suffixed)
    }
}
