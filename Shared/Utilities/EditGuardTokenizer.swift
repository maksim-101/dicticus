import Foundation

/// Phase 44 Plan 05 (D-03 core): atomic-numeric-aware tokenizer for
/// `EditGuard`.
///
/// EditGuardTokenizer produces the token stream the guard classifies. It
/// exists because the old dialect-gate tokenizer (`CleanupService.swift`,
/// the pre-Phase-44 gate's separator-driven splitter) splits on `,` and
/// `.`, which turns `10,011` into `10`/`011` — both under the ≥4-char
/// content-word threshold, making every digit in the utterance structurally
/// invisible to every clause of the shipped gate. The guard owns numeric
/// VALUE. `NumberRevert` (Step 3a.5) owns numeric FORM. A same-value
/// digit↔word change is ACCEPTED here so `NumberRevert` can normalize it; a
/// value change is REJECTED here so `NumberRevert` never sees it.
///
/// `rebuild(tokenize(s)) == s` for all `s` — lossless reconstruction, the
/// same guarantee `SentenceAligner.splitSentences` already makes at the
/// sentence level. Whitespace and punctuation ride on `Token.trailing`, not
/// inline in `Token.text`, so the guard can diff token identity without
/// noise from surrounding formatting.
public enum EditGuardTokenizer {

    // MARK: - Tokenize

    /// Single forward scan over `Character`s (grapheme clusters, not
    /// `unicodeScalars` — German umlauts and `ß` must not split).
    ///
    /// A `,` or `.` stays inside the current token **iff** the character
    /// immediately before AND immediately after it are both digits — this is
    /// the fix for the D-03 blindspot. Everything else about the scan
    /// (letters/digits continue a token; `'` always continues a word once
    /// started, matching the old dialect-gate tokenizer's apostrophe
    /// handling for `s'het`/`d'Mueter`; `-` continues a word only when flanked by letters
    /// on both sides, so `E-Mail` stays intact instead of splitting into an
    /// invisible `E`/`Mail` edit) mirrors the old separator-driven walk.
    public static func tokenize(_ s: String) -> [EditGuard.Token] {
        let chars = Array(s)
        let n = chars.count
        var tokens: [EditGuard.Token] = []
        var sentenceIndex = 0
        var i = 0

        func emit(text: String, kind: EditGuard.TokenKind) {
            tokens.append(EditGuard.Token(
                text: text,
                normalized: text.lowercased(),
                kind: kind,
                index: tokens.count,
                sentenceIndex: sentenceIndex,
                trailing: ""
            ))
            if kind == .punctuation, text == "." || text == "!" || text == "?" {
                sentenceIndex += 1
            }
        }

        /// Appends a run of whitespace to the trailing of the most recently
        /// emitted token. If no token has been emitted yet (leading
        /// whitespace, or a whitespace-only string), the run is preserved as
        /// its own token instead of being silently dropped — losslessness
        /// holds even for inputs no real pipeline stage is expected to
        /// produce.
        func appendTrailing(_ ws: String) {
            guard !ws.isEmpty else { return }
            if let last = tokens.popLast() {
                tokens.append(EditGuard.Token(
                    text: last.text,
                    normalized: last.normalized,
                    kind: last.kind,
                    index: last.index,
                    sentenceIndex: last.sentenceIndex,
                    trailing: last.trailing + ws
                ))
            } else {
                tokens.append(EditGuard.Token(
                    text: ws,
                    normalized: ws,
                    kind: .punctuation,
                    index: 0,
                    sentenceIndex: sentenceIndex,
                    trailing: ""
                ))
            }
        }

        while i < n {
            let c = chars[i]
            if c.isLetter || c.isNumber {
                var text = String(c)
                i += 1
                while i < n {
                    let cc = chars[i]
                    if cc.isLetter || cc.isNumber {
                        text.append(cc)
                        i += 1
                    } else if cc == "'" {
                        text.append(cc)
                        i += 1
                    } else if cc == "-" {
                        guard let last = text.last, last.isLetter,
                              i + 1 < n, chars[i + 1].isLetter else { break }
                        text.append(cc)
                        i += 1
                    } else if cc == "," || cc == "." {
                        // Digit-flanked iff both neighbours in the SOURCE
                        // string are digits — this is the atomicity fix.
                        guard i > 0, i + 1 < n,
                              chars[i - 1].isNumber, chars[i + 1].isNumber else { break }
                        text.append(cc)
                        i += 1
                    } else {
                        break
                    }
                }
                let kind: EditGuard.TokenKind = text.contains(where: { $0.isNumber }) ? .numeric : .word
                emit(text: text, kind: kind)
            } else if c == "," || c == "." {
                // Reached without an active word/numeric scan (start of
                // string, or immediately after non-digit content) — by
                // construction this cannot be digit-flanked, since a
                // digit-flanked separator would already have been absorbed
                // by the word-scan branch above.
                emit(text: String(c), kind: .punctuation)
                i += 1
            } else if c.isWhitespace {
                var ws = ""
                while i < n, chars[i].isWhitespace {
                    ws.append(chars[i])
                    i += 1
                }
                appendTrailing(ws)
            } else {
                emit(text: String(c), kind: .punctuation)
                i += 1
            }
        }

        return tokens
    }

    // MARK: - Rebuild

    /// Losslessness is a property of `tokenize` populating `trailing`
    /// correctly, not of `rebuild` being clever.
    public static func rebuild(_ tokens: [EditGuard.Token]) -> String {
        tokens.map { $0.text + $0.trailing }.joined()
    }

    // MARK: - Numeric value

    /// Resolves the numeric VALUE of a token so the guard can tell a FORM
    /// change (`10` <-> `zehn`/`ten`, same value) from a VALUE change (`10`
    /// -> `15`, different value).
    ///
    /// ⚠️ Locale-ambiguous by design: `numericValue(token("10,011"), "de")`
    /// reads as the DE decimal-comma convention (`10.011`), while
    /// `numericValue(token("10,011"), "en")` reads as the EN thousands-comma
    /// convention (`10011`). The guard does not need the TRUE magnitude — it
    /// needs `numericValue(A) == numericValue(B)` to be a reliable SAMENESS
    /// test under a FIXED language, and both sides of an edit are always
    /// parsed with the same `language`. Do NOT add locale-guessing
    /// heuristics; an ambiguous-but-consistent parse is sufficient, and
    /// `10,011` vs `10,111` differ under either reading.
    public static func numericValue(_ token: EditGuard.Token, language: String) -> Decimal? {
        switch token.kind {
        case .word:
            let map = language == "de" ? NumberRevert.deWords : NumberRevert.enWords
            guard let digitForm = map[token.normalized] else { return nil }
            return decimalFromLeadingDigits(digitForm)
        case .numeric:
            // An alphanumeric identifier ("M3") has no numeric value — it is
            // handled by the guard via `isDigitBearing` instead, as any
            // change to a digit-bearing token is a hard-lock unless the
            // tokens are byte-identical.
            guard !token.text.contains(where: { $0.isLetter }) else { return nil }
            return decimalFromGroupedNumeral(token.text, language: language)
        case .punctuation:
            return nil
        }
    }

    /// `NumberRevert.deWords`/`.enWords` map to digit forms that sometimes
    /// carry a non-digit suffix (`"1st"`, `"2nd"`, DE ordinal `"1."`) — take
    /// the leading digit run only.
    private static func decimalFromLeadingDigits(_ digitForm: String) -> Decimal? {
        let digits = digitForm.prefix(while: { $0.isNumber })
        guard !digits.isEmpty else { return nil }
        return Decimal(string: String(digits), locale: Locale(identifier: "en_US_POSIX"))
    }

    /// `de`: `.` groups digits, `,` is the decimal separator (`1.250,70`).
    /// `en`: `,` groups digits, `.` is the decimal separator (`1,250.70`).
    private static func decimalFromGroupedNumeral(_ text: String, language: String) -> Decimal? {
        let groupChar: Character = language == "de" ? "." : ","
        let decimalChar: Character = language == "de" ? "," : "."
        var normalized = String(text.filter { $0 != groupChar })
        if decimalChar != "." {
            normalized = normalized.replacingOccurrences(of: String(decimalChar), with: ".")
        }
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }

    // MARK: - Digit-bearing predicate

    /// Any change to a digit-bearing token (`"10,011"`, `"M3"`) is VALUE-
    /// locked by the guard even when `numericValue` cannot resolve it (an
    /// alphanumeric identifier has no `Decimal`, but it must still be
    /// treated as hard-locked content, not free-form text).
    public static func isDigitBearing(_ text: String) -> Bool {
        text.contains(where: \.isNumber)
    }
}
