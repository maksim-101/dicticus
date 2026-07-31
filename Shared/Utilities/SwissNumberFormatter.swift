import Foundation

/// D-C2 / D-C3: Post-LLM number-formatting pass for Swiss output.
///
/// Replaces the Phase 19 D-20 LLM-only thousands-separator approach with a
/// deterministic post-pass. Phase 20.08 strikes the original D-C1
/// apostrophe-thousands rule: rendering `"2026"` as `"2'026"` was wrong
/// for years and the simpler fix is to emit no thousands separator at all.
///
///   - No thousands grouping (apostrophe-strike, Phase 20.08). Years like
///     `2026` and amounts like `10000` flow through unchanged.
///   - Period decimal separator on every numeric token (currency and
///     non-currency alike) when Swiss toggle is ON. Per D-C2.
///
/// Single call site: `Shared/Services/CleanupService.cleanup(...)` —
/// runs after the existing D-19 `applySwissITN` safety-net, gated on the
/// same `useSwissGerman` AppGroup toggle.
///
/// Graceful-degradation contract (D-26): tokens that don't parse as
/// numbers are emitted unchanged. The function never throws and never
/// drops surrounding whitespace or punctuation.
///
/// Parser-strategy lock (B3 fix, Phase 19.5 revision):
///   The naive approach of "try parseSwiss first, fall back to parseGerman"
///   silently corrupts German-thousands inputs: `"1.250"` parses as `1.25`
///   under en_US_POSIX (period read as decimal), short-circuiting the
///   correct German-thousands interpretation. We pre-classify by
///   punctuation pattern: tokens containing `'` or U+2019 go to parseSwiss
///   directly; other tokens go to parseGerman first, then fall back to
///   parseSwiss as a safety net for already-Swiss-formatted input.
///
/// Currency-glyph handling (W7 fix, Phase 19.5 revision):
///   Tokens prefixed by a currency glyph (€, $, £) without a separating
///   space — e.g., `"€6,70"` — must reformat the numeric core while
///   preserving the glyph. We strip a leading currency glyph before
///   reformatting and re-attach it to the result.
public struct SwissNumberFormatter {

    /// Reformat every numeric token in `text` to no-grouping + period-decimal.
    /// Non-numeric tokens are emitted unchanged. Phase 20.08 dropped the
    /// apostrophe thousands separator (years like 2026 should not become 2'026).
    public static func format(_ text: String) -> String {
        // UAT-discovered cross-token gap (Phase 19.5 follow-up):
        // Gemma occasionally detokenizes German decimals with a stray space
        // after the comma — `"1.250, 70"` instead of `"1.250,70"`. The
        // tokenizer below splits on whitespace, so without a pre-pass
        // `"1.250,"` and `"70"` would be reformatted independently and the
        // user sees `"1'250, 70"`. Collapse `<digit>, <1-2 digits>` only
        // when the right side is bounded by whitespace or end-of-string,
        // which matches the cents/decimal shape and avoids merging genuine
        // lists like `"5, 6 oder 7"` (right side longer than 2 digits or
        // followed by a non-numeric token).
        //
        // Phase 20 (D-02 Action 2): `foldCurrencyUnits` runs FIRST so that
        // patterns like "15 Franken 50 Rappen" collapse to "CHF 15.50" before
        // the lower-precision `bridgeCrossTokenDecimal` ever sees them.
        // Order: fold → bridge → token-level reformat.
        let folded = foldCurrencyUnits(text)
        let bridged = bridgeCrossTokenDecimal(folded)
        let tokens = bridged.split(separator: " ", omittingEmptySubsequences: false)
        let reformed = tokens.map(reformatToken)
        return reformed.joined(separator: " ")
    }

    /// Phase 20 D-02 Action 2: collapse spoken-out currency-unit pairs into
    /// canonical glyph-prefixed decimal form.
    ///
    /// Patterns (case-insensitive). Cents are zero-padded to 2 digits.
    ///   - `<int> Franken|CHF <0-99> Rappen|Rp.`  → `CHF <int>.<cents>`
    ///   - `<int> Euro|EUR|€ <0-99> Cent|Ct.`     → `€<int>.<cents>`
    ///   - `<int> Dollar|USD|$ <0-99> Cents?`     → `USD <int>.<cents>`
    ///   - `<int> Pfund|Pound[s]|GBP|£ <0-99> Pence|p.` → `GBP <int>.<cents>`
    ///
    /// Idempotent: the patterns require the spoken `<unit>` keyword on both
    /// sides, so already-folded forms (`"CHF 15.50"`) do not match. Inputs
    /// without the second unit ("100 Franken") also do not match — bare
    /// integers are left for downstream passes.
    ///
    /// Runs BEFORE `bridgeCrossTokenDecimal` in `format(_:)` so the folded
    /// canonical form is what the rest of the pipeline sees. Returns the
    /// input unchanged on regex compile failure (graceful-degradation, D-26).
    public static func foldCurrencyUnits(_ text: String) -> String {
        // Phase 20.06 F-20-UAT-02: idempotency guard.
        // Each pattern requires the SECOND unit keyword (Rappen/Cent/Cents/Pence) so
        // already-folded forms ("CHF 15.50") cannot match. This was Phase 20.03's
        // intended idempotency mechanism. UAT 2026-04-27 surfaced a different
        // failure mode: the LLM (or a misconfigured upstream pass) can emit
        // duplicated currency tokens like "110.57 € Euro" or "110.57 Euro Euro"
        // BEFORE this function runs. A post-fold de-duplication pass collapses
        // those duplicates without altering single-token forms.
        var result = text

        struct CurrencyPattern {
            let pattern: String
            let format: (_ integerPart: String, _ cents: String) -> String
        }

        let patterns: [CurrencyPattern] = [
            CurrencyPattern(
                pattern: #"(\d+)\s+(?:Franken|CHF)\s+(\d{1,2})\s+(?:Rappen|Rp\.?)"#,
                format: { i, c in "CHF \(i).\(zeroPad(c))" }
            ),
            CurrencyPattern(
                pattern: #"(\d+)\s+(?:Euro|EUR|€)\s+(\d{1,2})\s+(?:Cent|Ct\.?)"#,
                format: { i, c in "€\(i).\(zeroPad(c))" }
            ),
            CurrencyPattern(
                pattern: #"(\d+)\s+(?:Dollar|USD|\$)\s+(\d{1,2})\s+Cent[s]?"#,
                format: { i, c in "USD \(i).\(zeroPad(c))" }
            ),
            CurrencyPattern(
                pattern: #"(\d+)\s+(?:Pfund|Pounds?|GBP|£)\s+(\d{1,2})\s+(?:Pence|p\.?)"#,
                format: { i, c in "GBP \(i).\(zeroPad(c))" }
            ),
        ]

        for cp in patterns {
            guard let regex = try? NSRegularExpression(
                pattern: cp.pattern,
                options: [.caseInsensitive]
            ) else { continue }

            let nsResult = result as NSString
            let fullRange = NSRange(location: 0, length: nsResult.length)
            let matches = regex.matches(in: result, options: [], range: fullRange)
            // Apply matches in reverse so range arithmetic stays stable.
            for match in matches.reversed() {
                guard match.numberOfRanges >= 3,
                      let intRange = Range(match.range(at: 1), in: result),
                      let centsRange = Range(match.range(at: 2), in: result),
                      let fullMatchRange = Range(match.range, in: result)
                else { continue }
                let integerPart = String(result[intRange])
                let cents = String(result[centsRange])
                let replacement = cp.format(integerPart, cents)
                result.replaceSubrange(fullMatchRange, with: replacement)
            }
        }

        // Phase 20.06 F-20-UAT-02: collapse adjacent duplicate currency tokens.
        // Catches "Euro Euro", "€ Euro", "Euro €", "Franken Franken", "CHF CHF" etc.
        // Bounded patterns — each alternative is fully anchored, no nesting, no
        // unbounded quantifiers — so backtracking is O(n) at worst.
        let dedupePatterns: [String] = [
            // Word-word duplications (case-insensitive).
            #"\b(Euro|Franken|Dollar|Pfund|CHF|EUR|USD|GBP)\s+\1\b"#,
            // Glyph then word of the SAME family.
            #"€\s+Euro\b"#,
            #"\bEuro\s+€"#,
            #"\$\s+Dollar\b"#,
            #"\bDollar\s+\$"#,
            #"£\s+Pfund\b"#,
            #"\bPfund\s+£"#,
        ]
        for pattern in dedupePatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let nsResult = result as NSString
            let fullRange = NSRange(location: 0, length: nsResult.length)
            let matches = regex.matches(in: result, options: [], range: fullRange)
            for match in matches.reversed() {
                guard let r = Range(match.range, in: result) else { continue }
                // Replace the duplicate run with the LEADING token (preserves the
                // form the user/LLM committed to first, glyph-or-word).
                let matched = String(result[r])
                // Take the first non-whitespace word/glyph and emit only that.
                let firstToken = matched.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? matched
                result.replaceSubrange(r, with: firstToken)
            }
        }

        return result
    }

    private static func zeroPad(_ s: String) -> String {
        return s.count == 1 ? "0" + s : s
    }

    /// Conservative cross-token bridges applied before tokenization.
    ///
    /// **Bridge 1 — Gemma decimal detokenization (existing).**
    ///   `"<thousand-pattern>, <1-2 digits>"` → `"<thousand-pattern>,<1-2 digits>"`
    ///   only when the LEFT side is a period-grouped thousand pattern (e.g.
    ///   `1.250`, `1.000.250`) and the right side is bounded by whitespace,
    ///   punctuation, or end-of-string. Requiring the period prefix avoids
    ///   merging bare-digit lists like `"5, 6 oder 7"` while still catching
    ///   the Gemma-detokenization case `"1.250, 70"` → `"1.250,70"`.
    ///
    /// **Bridge 2 — Split-cents-with-currency-between (Phase 19.5 UAT B3 fix).**
    ///   `"<1-3 digits> <currency> <2 digits>"` → `"<int>.<cents> <currency>"`
    ///   when the right side is exactly 2 digits and bounded by a non-digit
    ///   or end-of-string. Recovers from the original B3 case where ASR
    ///   transcribes spoken Swiss prices as three separate tokens (e.g.
    ///   "fünfzehn Franken fünfzig" → `"15 Franken 50"`) and the LLM either
    ///   leaves them literal (macOS path) or worse, concatenates them
    ///   (`"15'500 Franken"`, iOS path — that mangling is unrecoverable
    ///   post-LLM, but this bridge stops the LLM from being asked the
    ///   question on the macOS path AND covers the case where iOS happens
    ///   to leave the tokens literal).
    ///   Restricting the right side to exactly 2 digits avoids false
    ///   positives like `"15 Franken 5 Stück"` where `"5 Stück"` is a
    ///   separate phrase. The leading `(?<!\d)` and `(?<![.,'\u{2019}])`
    ///   lookbehinds prevent matching inside an already-formatted thousand
    ///   pattern like `"1.250 Franken 50"` (which would otherwise match
    ///   `"250 Franken 50"`).
    ///
    /// Returns input unchanged on regex compile failure (graceful-degradation, D-26).
    private static func bridgeCrossTokenDecimal(_ text: String) -> String {
        var result = text
        // Bridge 1: cross-token German decimal.
        let pattern1 = #"(\d+(?:\.\d{3})+),\s+(\d{1,2})(?=$|\s|[.,;:?!])"#
        if let r1 = try? NSRegularExpression(pattern: pattern1, options: []) {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = r1.stringByReplacingMatches(
                in: result, options: [], range: range, withTemplate: "$1,$2"
            )
        }
        // Bridge 1.5 (Phase 20.08): word-form cardinal cents prep. ITN keeps
        // German cardinals 1–9 spelled out per the project's "spell out one
        // through nine" style rule, so utterances like "vier Franken 50" reach
        // this stage as a word-Integer + digit-cents mix that Bridge 2 cannot
        // match (its first capture is `\d+`). Digitize the word-form integer
        // ONLY when the full currency-cents context is present; we don't want
        // to convert a bare "vier Äpfel" or "vier Franken" (no cents) — the
        // style rule still applies outside the cents-fold context. After this
        // pass, Bridge 2 below folds the result to "4.50 Franken".
        let cardinalWordToDigit: [(String, String)] = [
            ("eins", "1"), ("ein", "1"),
            ("zwei", "2"), ("drei", "3"), ("vier", "4"), ("fünf", "5"),
            ("sechs", "6"), ("sieben", "7"), ("acht", "8"), ("neun", "9"),
        ]
        for (word, digit) in cardinalWordToDigit {
            let prePattern = "(?<!\\w)\(word)\\s+(Franken|CHF|Euro|EUR|€|\\$|£)\\s+(\\d{2})(?=\\D|$)"
            if let rPre = try? NSRegularExpression(pattern: prePattern, options: [.caseInsensitive]) {
                let range = NSRange(result.startIndex..<result.endIndex, in: result)
                result = rPre.stringByReplacingMatches(
                    in: result, options: [], range: range, withTemplate: "\(digit) $1 $2"
                )
            }
        }
        // Bridge 2: split-cents with currency between (B3 original-case fix).
        // NB: U+2019 (right single quote) is written literally in the negative
        // lookbehind class. ICU regex accepts `\uhhhh` (no braces) but not
        // Swift's `\u{hhhh}` brace form, and the raw-string delimiter `#"..."#`
        // does NOT process `\u{...}`. Embedding the literal U+2019 sidesteps
        // both pitfalls.
        let pattern2 = "(?<!\\d)(?<![.,'\u{2019}])(\\d+)\\s+(Franken|CHF|Euro|EUR|€|\\$|£)\\s+(\\d{2})(?=\\D|$)"
        if let r2 = try? NSRegularExpression(pattern: pattern2, options: [.caseInsensitive]) {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = r2.stringByReplacingMatches(
                in: result, options: [], range: range, withTemplate: "$1.$3 $2"
            )
        }
        return result
    }

    // MARK: - Internals

    /// Set of leading currency glyphs we strip-and-reattach (W7).
    private static let leadingGlyphs: Set<Character> = ["€", "$", "£"]

    /// Reformat a single token. Strips a single trailing punctuation
    /// character (`.`, `,`, `;`, `:`, `?`, `!`) before parsing and
    /// re-attaches it to the output. Also strips a single leading currency
    /// glyph (€, $, £) per W7 and re-attaches it. Returns the input
    /// verbatim on any parse failure.
    private static func reformatToken(_ raw: Substring) -> String {
        let token = String(raw)
        guard !token.isEmpty else { return token }

        // W7: detach a leading currency glyph (€, $, £) so it doesn't
        // poison parsing. Whitespace-prefixed currencies (`"€ 6,70"`)
        // already split on the space and don't hit this path.
        let leadingGlyph: String
        let afterGlyph: String
        if let first = token.first, leadingGlyphs.contains(first), token.count > 1 {
            leadingGlyph = String(first)
            afterGlyph = String(token.dropFirst())
        } else {
            leadingGlyph = ""
            afterGlyph = token
        }

        // Detach a trailing punctuation tail so it doesn't poison parsing.
        let tail: Character?
        let core: String
        if let last = afterGlyph.last, ".,;:?!".contains(last), afterGlyph.count > 1 {
            tail = last
            core = String(afterGlyph.dropLast())
        } else {
            tail = nil
            core = afterGlyph
        }

        // UAT-discovered phantom-zero (Phase 19.5 follow-up): Foundation's
        // `Decimal(string: "Euro", locale: ...)` returns Optional(0) — same
        // for "EUR", "ein", and other strings that Foundation interprets as
        // a degenerate exponent form ("E…"). Without this guard, parseSwiss
        // / parseGerman silently parse currency words to 0 and emitSwiss
        // rewrites them to literal "0" in the output. Restrict the parser
        // path to tokens whose core contains only digits and number
        // punctuation (`.`, `,`, `'`, U+2019, sign).
        let numericChars: Set<Character> = [
            "0","1","2","3","4","5","6","7","8","9",
            ".", ",", "'", "\u{2019}", "+", "-"
        ]
        let hasDigit = core.contains(where: { $0.isNumber })
        let onlyNumericChars = core.allSatisfy({ numericChars.contains($0) })
        guard hasDigit, onlyNumericChars else {
            return token
        }

        // B3 (Phase 19.5 revision): pre-classify by punctuation pattern,
        // do NOT speculatively parseSwiss first.
        //
        // Rule:
        //   - Token contains `'` or U+2019 → it's already Swiss-formatted.
        //     parseSwiss only.
        //   - Otherwise → parseGerman first (covers German-thousands `1.250`
        //     correctly as 1250). If parseGerman fails (e.g., input has
        //     no separator at all, like `"5.70"` which is valid Swiss
        //     decimal), fall back to parseSwiss.
        let containsApostrophe = core.contains("'") || core.contains("\u{2019}")
        let parsed: Decimal?
        if containsApostrophe {
            parsed = parseSwiss(core)
        } else {
            parsed = parseGerman(core) ?? parseSwiss(core)
        }

        guard let value = parsed else {
            // Not a number — emit verbatim (with original glyph + tail).
            return token
        }
        let body = emitSwiss(value, originalSampleForFractionDigits: core)
        return leadingGlyph + body + (tail.map(String.init) ?? "")
    }

    private static func parseSwiss(_ s: String) -> Decimal? {
        // Swiss: apostrophe thousands (ASCII or U+2019), period decimal.
        let stripped = s
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "")
        return Decimal(string: stripped, locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func parseGerman(_ s: String) -> Decimal? {
        // German: period thousands, comma decimal. UAT-discovered regression
        // (Phase 19.5 follow-up): `Decimal(string: "1.250", locale: de_DE)`
        // returns 1 on macOS — Foundation truncates at the first period and
        // ignores grouping, so `Decimal(string: "1.250,70", de_DE)` is also 1.
        // We therefore parse manually rather than trusting locale handling:
        //   1. Split optional leading sign.
        //   2. Split on the LAST comma to separate integer / decimal parts.
        //   3. Validate the integer part as either pure digits or strict
        //      3-digit-grouped period thousands (e.g. "1.250" or "1.000.250").
        //   4. Validate the decimal part as digits only.
        //   5. Reassemble as `<sign><intDigits>.<fracDigits>` (or just
        //      `<sign><intDigits>`) and parse with `en_US_POSIX`, which
        //      handles a single-period decimal predictably.
        // Returns nil for any malformed shape so the caller falls back to
        // parseSwiss (e.g. "5.70" → no period-thousand pattern → nil →
        // parseSwiss → 5.70).
        var sign = ""
        var body = s
        if let first = body.first, first == "-" || first == "+" {
            sign = String(first)
            body = String(body.dropFirst())
        }
        guard !body.isEmpty else { return nil }

        let intPart: String
        let fracPart: String?
        if let commaIdx = body.lastIndex(of: ",") {
            intPart = String(body[body.startIndex..<commaIdx])
            let frac = String(body[body.index(after: commaIdx)...])
            guard !frac.isEmpty, frac.allSatisfy({ $0.isNumber }) else { return nil }
            // Reject more than one comma — ambiguous in German.
            guard !intPart.contains(",") else { return nil }
            fracPart = frac
        } else {
            intPart = body
            fracPart = nil
        }

        guard let intDigits = stripAndValidateGermanThousands(intPart) else { return nil }

        let canonical: String
        if let frac = fracPart {
            canonical = "\(sign)\(intDigits).\(frac)"
        } else {
            canonical = "\(sign)\(intDigits)"
        }
        return Decimal(string: canonical, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// Validate that `s` is either pure digits or a strict 3-digit-grouped
    /// German thousands pattern (`1`, `123`, `1.250`, `1.000.250`, …) and
    /// return the digit-only form. Empty input or any other shape returns nil.
    private static func stripAndValidateGermanThousands(_ s: String) -> String? {
        guard !s.isEmpty else { return nil }
        if !s.contains(".") {
            return s.allSatisfy({ $0.isNumber }) ? s : nil
        }
        let segments = s.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2 else { return nil }
        let first = segments.first!
        guard (1...3).contains(first.count), first.allSatisfy({ $0.isNumber }) else { return nil }
        for seg in segments.dropFirst() {
            guard seg.count == 3, seg.allSatisfy({ $0.isNumber }) else { return nil }
        }
        return segments.joined()
    }


    /// Emit a Decimal with no thousands grouping and period decimal,
    /// preserving the fraction-digit count of `sample` so 5.70 stays 5.70.
    /// (Apostrophe-strike: Phase 20.08.)
    private static func emitSwiss(_ value: Decimal, originalSampleForFractionDigits sample: String) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "de_CH")
        formatter.numberStyle = .decimal
        // Apostrophe-strike (Phase 20.08): years like "2026" were being
        // rendered as "2'026", which is wrong by Swiss orthography. Simpler
        // fix than a year-range heuristic — drop thousands grouping entirely.
        // Period decimal still applies (D-C2).
        formatter.usesGroupingSeparator = false
        formatter.decimalSeparator = "."         // explicit period — D-C2
        // Preserve the input's fraction digits when possible.
        let fractionDigits = fractionDigitCount(of: sample)
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = max(fractionDigits, 4)
        let result = formatter.string(from: value as NSDecimalNumber) ?? sample
        // Belt-and-suspenders: ensure no U+2019 leaks even if a future iOS
        // changes the formatter's grouping behavior.
        return result.replacingOccurrences(of: "\u{2019}", with: "'")
    }

    /// Determine fraction-digit count from the original sample string.
    /// For inputs like `"5.70"` (Swiss decimal) or `"5,70"` (German decimal),
    /// returns 2. For thousands-only inputs like `"1.250"` (German thousands)
    /// returns 0 — but only when the digits-after-separator length is exactly
    /// 3 AND there's no other separator suggesting a true decimal.
    private static func fractionDigitCount(of sample: String) -> Int {
        // If the sample contains BOTH `.` and `,`, the LAST one wins as
        // decimal. Otherwise: a single `,` is decimal; a single `.` is
        // decimal UNLESS it's followed by exactly 3 digits and no other
        // separator (then it's German thousands → 0 fraction digits).
        let lastDot = sample.lastIndex(of: ".")
        let lastComma = sample.lastIndex(of: ",")

        if let d = lastDot, let c = lastComma {
            // Both present — the latter is the decimal separator.
            let decimalIdx = d > c ? d : c
            return sample.distance(from: sample.index(after: decimalIdx), to: sample.endIndex)
        } else if let c = lastComma {
            // Comma only — German decimal.
            return sample.distance(from: sample.index(after: c), to: sample.endIndex)
        } else if let d = lastDot {
            let after = sample.distance(from: sample.index(after: d), to: sample.endIndex)
            // German thousands heuristic: exactly 3 digits after the dot,
            // no other separator → it's thousands (0 fraction digits).
            if after == 3 { return 0 }
            return after
        }
        return 0
    }
}
