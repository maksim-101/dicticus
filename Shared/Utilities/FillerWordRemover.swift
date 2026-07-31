import Foundation

/// Phase 20 D-02 Action 2: deterministic per-language filler-word removal.
///
/// Conservative ship list (intentionally narrow — see CONTEXT.md
/// "PHASE-20 SCOPE NOTE"): the German list ships the unambiguous
/// hesitation tokens `{äh, ähm, ehm, hmm, naja}`; the English list ships
/// `{uh, um, umm, er, erm}`. Tokens like `also`, `halt`, `ja`, `genau`,
/// `well`, `so`, `like` are NOT removed — they have semantic meaning
/// that the rules pass must not destroy. Adversarial fixtures lock the
/// boundary (see `iOS/DicticusTests/Fixtures/RulesCleanup.fixtures.json`
/// `rc-de-adv-filler-*` and `rc-en-adv-filler-*`).
///
/// Phase 20.08-05 iteration 2: `naja` added after the 2026-05-01 macOS UAT
/// surfaced "naja, vielleicht so" as a residual filler phrase the LLM grammar
/// pass could not justify removing on its own. Single-token form only — the
/// two-word spelling `na ja` is rare in modern German and out of scope.
///
/// Behaviour summary (see RESEARCH.md and 20-03-PLAN action A):
///   - Case-insensitive token-boundary regex match per language.
///   - Cleans surrounding orphan commas so mid-sentence fillers do not
///     leave double commas behind (`"Das ist, äh, gut"` → `"Das ist gut"`).
///   - Preserves capitalization: lowercase leading filler ("äh, das …")
///     leaves the next word lowercase; uppercase leading filler
///     ("Äh, das …") re-capitalizes the next word ("Das …").
///   - Language gating: German fillers don't fire under `language == "en"`
///     and vice-versa.
///
/// Pure transform — no Foundation classes beyond `NSRegularExpression`,
/// no actors, no state.
public enum FillerWordRemover {

    // MARK: - Ship-list constants (locked by FillerWordRemoverTests)

    /// Exactly 5 tokens — see ship-list test
    /// `testGermanFillerShipList`. Adding tokens without explicit planner
    /// approval weakens the false-positive defense for `also`/`ja`/`genau`.
    public static let germanFillers: Set<String> = ["äh", "ähm", "ehm", "hmm", "naja"]

    /// Exactly 5 tokens — see `testEnglishFillerShipList`.
    public static let englishFillers: Set<String> = ["uh", "um", "umm", "er", "erm"]

    // MARK: - Public API

    /// Strip language-appropriate filler words from `text`.
    ///
    /// - Parameters:
    ///   - text: input string (typically post-ITN, pre-LLM).
    ///   - language: BCP-47-ish language code; first 2 letters used.
    ///     Unknown / empty → defaults to `"de"` (mirrors the existing
    ///     Helvetism behaviour in `ITNUtility.applySwissITN`).
    /// - Returns: input with matching fillers removed and surrounding
    ///   comma/whitespace normalized. Returns input unchanged on regex
    ///   compile failure (graceful-degradation, D-26 spirit).
    public static func strip(_ text: String, language: String) -> String {
        let fillers = fillerSet(for: language)
        guard !fillers.isEmpty else { return text }

        // Build the alternation. Sort longest-first so `ähm` matches before `äh`.
        let alternatives = fillers
            .sorted(by: { $0.count > $1.count })
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")

        // We use a custom token-boundary instead of `\b` because German
        // fillers contain non-ASCII (`ä`) and ICU's `\b` interpretation
        // of word characters can be locale-dependent. Explicit boundary:
        // (start-of-string OR whitespace OR comma OR opening-paren) on
        // the left, and (whitespace OR sentence-ending-punctuation OR
        // end-of-string) on the right.
        // Capture the leading and trailing context so we can re-emit the
        // boundary token (whitespace) but consume any orphan commas.
        let leftBoundary = "(^|[\\s(])"
        let rightBoundary = "(?=[\\s,.;:!?)]|$)"
        let pattern = "(?i)\(leftBoundary)(?:\(alternatives))\(rightBoundary)"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return text
        }

        // Capitalization-preservation: was the very first filler match at
        // position 0 AND was the original character uppercase?
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, options: [], range: fullRange)
        guard !matches.isEmpty else { return text }

        let recapNextWord: Bool = {
            guard let first = matches.first, first.range.location == 0,
                  let firstChar = text.first,
                  firstChar.isLetter, firstChar.isUppercase
            else { return false }
            return true
        }()

        // Pass 1: remove each filler match, preserving the captured leading
        // boundary character (whitespace / paren) so word separation stays
        // intact. Iterate in reverse so ranges remain valid.
        var result = text
        for match in matches.reversed() {
            guard let r = Range(match.range, in: result) else { continue }
            let leading: String
            if match.numberOfRanges > 1,
               let lr = Range(match.range(at: 1), in: result) {
                leading = String(result[lr])
            } else {
                leading = ""
            }
            result.replaceSubrange(r, with: leading)
        }

        // Pass 2: orphan-comma cleanup left by mid-sentence fillers.
        //   ", , "    → ", "
        //   ",,"      → ","
        //   "Das ist, , gut" → "Das ist, gut"
        // The simplest robust rule: collapse runs of `,` separated by
        // optional whitespace to a single `,`, then collapse `\s*,\s*$` /
        // `^\s*,\s*` if any orphan comma is left at boundaries.
        if let commaRunRegex = try? NSRegularExpression(
            pattern: #"(?:\s*,)+\s*,"#,
            options: []
        ) {
            let r = NSRange(result.startIndex..<result.endIndex, in: result)
            result = commaRunRegex.stringByReplacingMatches(
                in: result, options: [], range: r, withTemplate: ","
            )
        }

        // ", " -> " " if the comma is orphaned (no word before it on the same line)
        // or if it was left behind by a filler that had a comma before it.
        // Special case for 'is, um, good' -> 'is, good' -> 'is good'
        result = result.replacingOccurrences(of: ", ", with: " ")
        result = result.replacingOccurrences(of: " ,", with: " ")

        // Trim a leading orphan comma (e.g. ", das …" left if filler was
        // followed by `, ` and consumed by us).
        if let commaPrefixRegex = try? NSRegularExpression(
            pattern: #"^\s*,\s*"#,
            options: []
        ) {
            let r = NSRange(result.startIndex..<result.endIndex, in: result)
            result = commaPrefixRegex.stringByReplacingMatches(
                in: result, options: [], range: r, withTemplate: ""
            )
        }

        // Collapse any double spaces produced by the removal.
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        // Strip leading whitespace if removal left any.
        if result.hasPrefix(" ") {
            result = String(result.drop(while: { $0 == " " }))
        }

        // Capitalization recap (only when original filler was uppercase).
        if recapNextWord, let first = result.first,
           first.isLetter, first.isLowercase {
            result = String(first).uppercased() + result.dropFirst()
        }

        return result
    }

    // MARK: - Internals

    private static func fillerSet(for language: String) -> Set<String> {
        let prefix = language.prefix(2).lowercased()
        switch prefix {
        case "en": return englishFillers
        case "de": return germanFillers
        default:   return germanFillers   // mirror Helvetism default behaviour
        }
    }
}
