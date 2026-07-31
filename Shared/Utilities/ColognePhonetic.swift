import Foundation

/// German Kölner Phonetik (Cologne phonetics) encoder — Postel 1969.
///
/// Maps a German token to a digit string so spelling variants of the same sound
/// collide (e.g. "Meier" and "Mayer" both → "67"). This is the German-appropriate
/// phonetic encoder for the brand matcher; English Double Metaphone (36.5-02) is
/// wrong for German tokens (CONTEXT / RESEARCH §1).
///
/// Ported against the Apache Commons `ColognePhonetic` / `maxwellium/cologne-phonetic`
/// reference. Letters map to digits with at most one character of left/right context.
///
/// Umlaut handling (Pitfall §4.1 — the #1 port-correctness bug): ä/ö/ü are classed
/// as vowels (code 0) and ß is expanded to "ss". The input is lowercased with
/// `String.lowercased()` (which preserves umlauts) — there is deliberately NO
/// `[^a-z]` strip, which would delete ä/ö/ü.
public enum ColognePhonetic {

    private static let vowels: Set<Character> = ["a", "e", "i", "j", "o", "u", "y", "ä", "ö", "ü"]

    /// Encode a token to its Kölner Phonetik digit string.
    ///
    /// Steps: lowercase, expand ß→ss, keep only German letters (a–z + ä/ö/ü),
    /// map each letter to a code using ≤1 char of context, append digits while
    /// collapsing consecutive identical codes, and drop every "0" except a
    /// leading one.
    public static func encode(_ s: String) -> String {
        // Lowercase preserves umlauts; expand ß to ss; keep only German letters.
        let lowered = s.lowercased().replacingOccurrences(of: "ß", with: "ss")
        let letters = Array(lowered).filter { vowels.contains($0) || ($0 >= "a" && $0 <= "z") }
        if letters.isEmpty { return "" }

        var out = ""
        var lastCode: Character? = nil

        for i in 0..<letters.count {
            let prev: Character? = i > 0 ? letters[i - 1] : nil
            let next: Character? = i < letters.count - 1 ? letters[i + 1] : nil
            guard let code = codeFor(letters[i], prev: prev, next: next) else {
                continue // 'h' produces no code and does not reset the run
            }
            for digit in code {
                if digit == lastCode {
                    lastCode = digit
                    continue // collapse consecutive identical codes
                }
                if digit == "0" && !out.isEmpty {
                    lastCode = digit // drop non-leading 0, but it still separates a run
                    continue
                }
                out.append(digit)
                lastCode = digit
            }
        }

        return out
    }

    /// Letter → code (a 0/1/2-digit string), or `nil` for 'h' (no code).
    private static func codeFor(_ c: Character, prev: Character?, next: Character?) -> String? {
        if vowels.contains(c) { return "0" }
        switch c {
        case "h": return nil
        case "b": return "1"
        case "p": return next == "h" ? "3" : "1"
        case "d", "t": return (next == "c" || next == "s" || next == "z") ? "8" : "2"
        case "f", "v", "w": return "3"
        case "g", "k", "q": return "4"
        case "l": return "5"
        case "m", "n": return "6"
        case "r": return "7"
        case "s", "z": return "8"
        case "c":
            if prev == nil {
                // Initial: 4 before A,H,K,L,O,Q,R,U,X; else 8.
                if let n = next, "ahkloqrux".contains(n) { return "4" }
                return "8"
            } else {
                if let p = prev, p == "s" || p == "z" { return "8" }
                if let n = next, "ahkoqux".contains(n) { return "4" }
                return "8"
            }
        case "x":
            // 48, unless preceded by C/K/Q (then the preceding velar already
            // covers the /k/ so X is just 8).
            if let p = prev, p == "c" || p == "k" || p == "q" { return "8" }
            return "48"
        default:
            return nil
        }
    }
}
