import Foundation

/// D-B1a / D-B1c: Currency anti-flip — pre-LLM detection and post-LLM revert
/// to defeat Gemma's German-language EUR bias on CHF/USD/GBP utterances.
///
/// Two-mechanism contract:
///   1. `detectCurrencies(in:)` — pre-LLM. Returns the set of currency
///      families found in the input so `CleanupPrompt.build(...)` can
///      append a STRICT anchor enumerating exactly those families
///      (per D-B1b).
///   2. `revertCurrencyFlip(input:output:)` — post-LLM. If the LLM
///      substituted one currency family for another (e.g., `CHF` →
///      `EUR`), restore the input's family on a positional best-match
///      basis. Numeric values and surrounding format stay as the model
///      wrote them — only the currency LABEL is corrected.
///
/// Per D-B2: gated on `language == "de"` regardless of Swiss toggle.
/// English (`language == "en"`) is excluded — no observed flipping there.
///
/// Graceful-degradation contract (D-26): any unexpected input shape
/// (regex compile failure, mismatched detection counts, NSRange ↔ String
/// conversion failure) returns the original output unmodified rather
/// than throwing or crashing.
public struct CurrencyAntiFlip {

    public enum Family: String, Sendable, CaseIterable {
        case chf
        case eur
        case usd
        case gbp
    }

    public struct Token: Sendable, Equatable {
        public let family: Family
        public let text: String   // verbatim matched substring
    }

    // MARK: - Pre-LLM detection (D-B1a)

    /// Detect currency tokens in the input string. Order-preserving.
    /// Returns an empty array on regex-compile failure (graceful-degradation).
    public static func detectCurrencies(in text: String) -> [Token] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: range)
        return matches.compactMap { match -> Token? in
            guard let r = Range(match.range, in: text) else { return nil }
            let matched = String(text[r])
            guard let fam = family(of: matched) else { return nil }
            return Token(family: fam, text: matched)
        }
    }

    // MARK: - Speaker-explicit word-form detection (Phase 20.06 F-20-UAT-02)

    /// Set of currency families the speaker named by WORD ("Franken", "Euro",
    /// "Dollar", "Pfund"). Glyphs (€/$/£) and 3-letter codes (CHF/EUR/USD/GBP)
    /// do NOT count — those are normalizations, not what the speaker actually said.
    ///
    /// Used by `revertCurrencyFlip` to upgrade canonical-label decisions: when the
    /// speaker used "Franken" and the LLM emitted "Euro" at that index, the revert
    /// restores the WORD form ("Franken"), not the CODE form ("CHF").
    public static func speakerExplicitCurrencies(in text: String) -> Set<Family> {
        // Word-form alternatives only. Bounded pattern, anchored by Unicode-aware
        // non-letter/non-digit lookarounds (matches existing `pattern` style).
        let wordPattern = #"(?<![\p{L}\p{N}])(Franken|Rappen|Euro|Dollar|Pfund|Pounds?)(?![\p{L}\p{N}])"#
        guard let regex = try? NSRegularExpression(pattern: wordPattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: range)
        var result = Set<Family>()
        for match in matches {
            guard let r = Range(match.range, in: text) else { continue }
            let word = String(text[r]).lowercased()
            switch word {
            case "franken", "rappen": result.insert(.chf)
            case "euro":              result.insert(.eur)
            case "dollar":            result.insert(.usd)
            case "pfund", "pound", "pounds": result.insert(.gbp)
            default: continue
            }
        }
        return result
    }

    // MARK: - Post-LLM revert (D-B1c)

    /// If the LLM flipped the currency family (e.g., input had CHF/Franken,
    /// output has only EUR/Euro), restore the input's family on a positional
    /// best-match basis. Returns `output` unchanged when no flip is detected
    /// or detection counts mismatch (graceful-degradation).
    public static func revertCurrencyFlip(input: String, output: String) -> String {
        let inputTokens = detectCurrencies(in: input)
        let outputTokens = detectCurrencies(in: output)

        // No currencies anywhere — nothing to revert.
        guard !inputTokens.isEmpty, !outputTokens.isEmpty else { return output }

        // No flip — input families are a subset of (or equal to) output families.
        let inputFamilies = Set(inputTokens.map(\.family))
        let outputFamilies = Set(outputTokens.map(\.family))

        // Phase 20.06 F-20-UAT-02: speaker-explicit word-form anchor.
        // Even when family SETS match, the LLM may have substituted ONE flipped
        // family at a positional index where the speaker used a word — e.g.
        // input "110.57 € + 4.50 Franken" (families {.eur, .chf}) →
        // output "110.57 Euro + 4.50 Euro" (families {.eur} — set MISMATCH).
        // The set-mismatch case is handled below; the position-by-position
        // word-form anchor handling kicks in when revert proceeds.

        // No flip case (input families ⊆ output families) AND no positional
        // mismatch — return output unchanged.
        if inputFamilies == outputFamilies && inputTokens.count == outputTokens.count {
            // Even when families match in aggregate, check if any position has a
            // speaker-explicit word the LLM rewrote to a different form (e.g.
            // word "Franken" → code "CHF" at the same index). For now this case
            // is a no-op; the speaker-explicit upgrade applies only when there
            // IS a family flip at the position. Return output unchanged.
            return output
        }

        // Different counts — too risky to positional-revert; bail.
        guard inputTokens.count == outputTokens.count else { return output }

        let speakerWords = speakerExplicitCurrencies(in: input)

        // Positional best-match revert with speaker-explicit word-form upgrade.
        var result = output
        for (index, outputToken) in outputTokens.enumerated().reversed() {
            let targetFamily = inputTokens[index].family
            if outputToken.family != targetFamily {
                let isSpeakerWord = speakerWords.contains(targetFamily)
                let replacement = canonicalLabel(
                    for: targetFamily,
                    mirroring: outputToken.text,
                    preferWordForm: isSpeakerWord
                )
                if let replacementRange = rangeOfMatch(text: outputToken.text, in: result, occurrence: index) {
                    result.replaceSubrange(replacementRange, with: replacement)
                }
            }
        }
        return result
    }

    // MARK: - Internals

    // Bounded patterns — avoid catastrophic backtracking. Each alternative is
    // bounded by "not adjacent to a letter or digit" lookarounds rather than
    // ASCII `\b`. WR-01 fix (Phase 19.5): `\b` requires a `\w`↔`\W` transition,
    // so for non-word currency glyphs (`€`, `$`, `£`) and abbreviation forms
    // (`Fr.`, trailing `.` is non-word) the trailing/leading `\b` cannot match
    // in common positions (start/end of string, glyph followed by space, etc.).
    // The Unicode-aware lookarounds match the actual semantic boundary we want.
    private static let pattern = #"(?<![\p{L}\p{N}])(CHF|Franken|Fr\.|Rappen|EUR|Euro|€|USD|Dollar|\$|GBP|Pfund|£)(?![\p{L}\p{N}])"#

    private static func family(of token: String) -> Family? {
        let lowered = token.lowercased()
        switch lowered {
        case "chf", "franken", "fr.", "rappen": return .chf
        case "eur", "euro", "€":                 return .eur
        case "usd", "dollar", "$":                return .usd
        case "gbp", "pfund", "£":                  return .gbp
        default: return nil
        }
    }

    /// Pick a canonical label for `target` that visually mirrors `mirror`.
    /// If `mirror` was a 3-letter code (uppercase), use the target's code.
    /// If `preferWordForm == true` (speaker said the word), force the word form
    /// regardless of mirror shape — this is the F-20-UAT-02 word-form anchor.
    /// Otherwise use the target's most common spelled form.
    private static func canonicalLabel(for target: Family,
                                       mirroring mirror: String,
                                       preferWordForm: Bool = false) -> String {
        if preferWordForm {
            switch target {
            case .chf: return "Franken"
            case .eur: return "Euro"
            case .usd: return "Dollar"
            case .gbp: return "Pfund"
            }
        }
        let isCode = mirror == mirror.uppercased() && mirror.count == 3
        switch target {
        case .chf: return isCode ? "CHF" : "Franken"
        case .eur: return isCode ? "EUR" : "Euro"
        case .usd: return isCode ? "USD" : "Dollar"
        case .gbp: return isCode ? "GBP" : "Pfund"
        }
    }

    /// Find the Nth (0-indexed) occurrence of `text` in `haystack`. Returns nil
    /// if not found that many times (graceful-degradation against rewrites).
    private static func rangeOfMatch(text: String, in haystack: String, occurrence: Int) -> Range<String.Index>? {
        var searchRange = haystack.startIndex..<haystack.endIndex
        var found = 0
        while let r = haystack.range(of: text, options: [.caseInsensitive], range: searchRange) {
            if found == occurrence { return r }
            found += 1
            searchRange = r.upperBound..<haystack.endIndex
        }
        return nil
    }
}
