import Foundation

/// Quick task 260830-pf3: an INDEPENDENT fact-preservation backstop for the
/// AI-cleanup pipeline. Modeled, approach only (original implementation, not
/// a port — different language, different shape), on competitor app
/// natter's `TranscriptFactGuard.preservesFacts` (Apache-2.0): extract a set
/// of high-value literals (URLs, emails, filesystem paths, numbers with an
/// optional unit) from the pre-LLM text, and require every one of them to
/// still be present in the final text.
///
/// Deliberately separate from `EditGuard`: `EditGuard` accepts/rejects each
/// individual EDIT via `EditDiff`'s token alignment; this guard never looks
/// at an edit, a diff, or a per-edit classification verdict — it compares
/// two whole strings. That independence is the point: it catches corruption
/// `EditDiff`'s alignment can miss, e.g. a multi-token MERGE (`"kink
/// three"` → `"K3"`, project memory `project_v19d_r8_kink_king_bug` — "Lev
/// gate too coarse") or a hard truncation, precisely because it never
/// consults `EditGuard`'s own verdicts to decide anything.
///
/// PLACEMENT (full reasoning in `260830-pf3-SUMMARY.md`): called from
/// `TextProcessingService`, AFTER `NumberRevert.apply` (Step 3a.5) — NOT
/// from inside `EditGuard.apply`. `EditGuard`'s `numberFormChange` accept
/// class legitimately turns a baseline digit into a spelled word (`"10"` →
/// `"zehn"`); `NumberRevert` is what turns it back. Checking literal
/// survival BEFORE `NumberRevert` runs would reject every legitimate
/// `numberFormChange` fixture (`EditGuardFixtures.substituteDigit`'s
/// `fx-sub-digit-de-numberform` / `fx-sub-digit-en-numberform`); checking
/// AFTER it runs means this guard only ever sees the pipeline's own final
/// number-form policy, which already guarantees baseline-form survival for
/// every legitimate ITN/LLM form rewrite.
///
/// NUMBER LITERALS use whole-TOKEN boundary matching, not natter's bare
/// substring matching — a deliberate departure. A substring check on `"3"`
/// is satisfied by `"K3"`, which is exactly this project's documented
/// "kink three" → "K3" collapse shape; token-boundary matching
/// (`(?<![\p{L}\p{N}])3(?![\p{L}\p{N}])`) correctly rejects it. URL/email/
/// path literals stay substring matches (natter's original shape) — those
/// classes are long and distinctive enough that a false substring hit
/// inside unrelated text is not a realistic risk here.
enum FactPreservationGuard {

    struct Result {
        let preserved: Bool
        let missingLiterals: [String]
    }

    /// Recognized unit tokens a digit may glue to WITHOUT a space
    /// (`"15%"`, `"200ms"`). Natter's set (`%`/`ms`/`MB`/`GB`/`TB`/`x`)
    /// extended with the everyday metric/time units this project's German+
    /// English dictation corpus actually produces (`kg`/`km`/`h`/`min`/`s`).
    private static let unitSuffixes: Set<String> = [
        "%", "ms", "mb", "gb", "tb", "x", "kg", "km", "h", "min", "s"
    ]
    /// Currency symbols that glue to the LEFT of a digit without a space
    /// (`"$50"`). `€`/`£` included alongside `$` per this project's German/
    /// Swiss-market dictation (CLAUDE.md: "German decimal commas and
    /// currency are live concerns here").
    private static let currencyPrefixes: Set<String> = ["$", "€", "£"]
    /// Currency WORDS that glue to the right of a digit without a space —
    /// `ITNUtility` never produces a spaceless "50CHF", so this exists for
    /// symmetry/completeness rather than an observed corpus shape.
    private static let currencySuffixWords: Set<String> = ["chf"]

    static func check(baseline: String, output: String) -> Result {
        let literals = extractLiterals(from: baseline)
        guard !literals.isEmpty else { return Result(preserved: true, missingLiterals: []) }

        let missing = literals.filter { !survives($0, in: output) }.map(\.text)
        return Result(preserved: missing.isEmpty, missingLiterals: missing)
    }

    // MARK: - Literal extraction

    private struct Literal {
        let text: String
        /// `true`: match as a boundary-delimited token (numbers).
        /// `false`: match as a case-insensitive substring (URL/email/path).
        let matchWholeToken: Bool
    }

    private static func extractLiterals(from text: String) -> [Literal] {
        var literals: [Literal] = []
        literals.append(contentsOf: extractURLsAndEmails(text).map { Literal(text: $0, matchWholeToken: false) })
        literals.append(contentsOf: extractPaths(text).map { Literal(text: $0, matchWholeToken: false) })
        literals.append(contentsOf: extractNumbers(text).map { Literal(text: $0, matchWholeToken: true) })
        return literals
    }

    private static func extractURLsAndEmails(_ text: String) -> [String] {
        var results: [String] = []
        results.append(contentsOf: regexMatches(in: text, pattern: #"https?://\S+"#))
        results.append(contentsOf: regexMatches(in: text, pattern: #"\bwww\.\S+"#))
        results.append(contentsOf: regexMatches(in: text, pattern: #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#))
        return results
    }

    /// `~/...` or `/segment/segment` (>= 2 slash-delimited segments) — a
    /// bare single slash between two plain words ("and/or") never
    /// qualifies, so ordinary prose isn't misread as a path.
    private static func extractPaths(_ text: String) -> [String] {
        var results: [String] = []
        results.append(contentsOf: regexMatches(in: text, pattern: #"~/[A-Za-z0-9_.\-/]+"#))
        results.append(contentsOf: regexMatches(
            in: text,
            pattern: #"/[A-Za-z0-9_.\-]+(?:/[A-Za-z0-9_.\-]+)+"#
        ))
        return results
    }

    /// Reuses `EditGuardTokenizer` — the project's own trusted DE/EN
    /// digit-flanked-separator tokenizer (`"10,011"` stays one token, not
    /// `["10", "011"]`) — rather than a hand-rolled number regex.
    private static func extractNumbers(_ text: String) -> [String] {
        let tokens = EditGuardTokenizer.tokenize(text)
        var results: [String] = []
        for i in tokens.indices {
            let token = tokens[i]
            guard token.kind == .numeric, EditGuardTokenizer.isDigitBearing(token.text) else { continue }

            var literal = token.text
            if i > 0, tokens[i - 1].trailing.isEmpty, currencyPrefixes.contains(tokens[i - 1].text) {
                literal = tokens[i - 1].text + literal
            }
            if token.trailing.isEmpty, i + 1 < tokens.count {
                let next = tokens[i + 1].text.lowercased()
                if unitSuffixes.contains(next) || currencySuffixWords.contains(next) {
                    literal += tokens[i + 1].text
                }
            }
            results.append(literal)
        }
        return results
    }

    // MARK: - Survival check

    private static func survives(_ literal: Literal, in text: String) -> Bool {
        guard !text.isEmpty else { return false }
        if literal.matchWholeToken {
            let escaped = NSRegularExpression.escapedPattern(for: literal.text)
            let pattern = "(?<![\\p{L}\\p{N}])\(escaped)(?![\\p{L}\\p{N}])"
            return !regexMatches(in: text, pattern: pattern, caseInsensitive: true).isEmpty
        }
        return text.range(of: literal.text, options: .caseInsensitive) != nil
    }

    private static func regexMatches(in text: String, pattern: String, caseInsensitive: Bool = false) -> [String] {
        var options: NSRegularExpression.Options = []
        if caseInsensitive { options.insert(.caseInsensitive) }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let r = Range(match.range, in: text) else { return nil }
            return String(text[r])
        }
    }
}
