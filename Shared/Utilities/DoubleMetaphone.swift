import Foundation

/// English Double Metaphone (primary code) encoder — Lawrence Philips, 2000.
///
/// Maps an English token to a phonetic key so spelling variants of the same
/// sound collide (e.g. "Catherine" and "Katherine" both → "K0RN", where "0" is
/// the theta sound of "th"). This is the English-appropriate phonetic encoder
/// for the brand matcher (BMATCH-01 / CONTEXT "EN phonetics = metaphone, Double
/// Metaphone preferred"). German tokens use `ColognePhonetic` (36.5-01) instead —
/// English Metaphone rules are wrong for German.
///
/// Output is the **primary** code only (the secondary/alternate code is not
/// required this phase — RESEARCH §1). The key is the **full, uncapped** primary
/// string — NOT truncated to the traditional 4-character convention. The matcher
/// compares keys for equality, so the extra discriminating characters of a long
/// brand reduce false phonetic collisions; the precision-sensitive matcher
/// (the spike's central concern is prose corruption) benefits from the full key.
/// This matches the de-facto reference implementations (jellyfish/metaphone/
/// abydos), which all emit the uncapped primary code.
///
/// Ported from Lawrence Philips' Double Metaphone (the Apache Commons Codec
/// `DoubleMetaphone` control flow), keeping only the primary buffer. Non-letter
/// input is pre-stripped (mirroring the spike `matcher.py` `[^A-Za-z]` removal),
/// so the encoder only ever sees ASCII A–Z and never crashes on digits,
/// punctuation, or umlauts.
///
/// Threat to validity (RESEARCH §4.4 / Open Question 3): the spike validated
/// jellyfish's **single** Metaphone, so this Double Metaphone collides a
/// different set of tokens. The matcher's phonetic / edit-distance thresholds
/// are RE-TUNED against THIS encoder in 36.5-04/05's scale test, not copied from
/// the spike. Falling back to a single-Metaphone simplification is the documented
/// escape hatch if the 36.5-05 scale test shows worse precision/recall.
public enum DoubleMetaphone {

    /// Encode a token to its Double Metaphone primary code (uncapped).
    ///
    /// Non-letter characters are stripped before encoding, so `encode("")` is "",
    /// and a token with digits/punctuation encodes only its letters.
    public static func encode(_ s: String) -> String {
        let v = Array(s.uppercased().filter { $0 >= "A" && $0 <= "Z" })
        if v.isEmpty { return "" }
        let enc = Encoder(v)
        enc.run()
        return enc.primary
    }

    /// Mutable per-call state, mirroring Apache Commons' instance style. Each
    /// branch advances `index` and appends at most once to `primary`.
    private final class Encoder {
        let v: [Character]
        let last: Int
        let slavoGermanic: Bool
        var index: Int
        var primary = ""

        init(_ v: [Character]) {
            self.v = v
            self.last = v.count - 1
            self.slavoGermanic = Encoder.isSlavoGermanic(v)
            self.index = Encoder.isSilentStart(v) ? 1 : 0
        }

        // MARK: - Primitives

        private func charAt(_ i: Int) -> Character {
            (i < 0 || i >= v.count) ? "\0" : v[i]
        }

        /// True when `v[start ..< start+length]` equals any of `criteria`.
        /// Mirrors Apache's bounds rule: false when `start < 0` or the window
        /// runs past the end.
        private func contains(_ start: Int, _ length: Int, _ criteria: String...) -> Bool {
            if start < 0 || start + length > v.count { return false }
            let sub = String(v[start ..< start + length])
            return criteria.contains(sub)
        }

        private func isVowel(_ i: Int) -> Bool {
            if i < 0 || i >= v.count { return false }
            return "AEIOUY".contains(v[i])
        }

        private func add(_ s: String) { primary += s }

        private static func isSlavoGermanic(_ v: [Character]) -> Bool {
            let s = String(v)
            return s.contains("W") || s.contains("K") || s.contains("CZ") || s.contains("WITZ")
        }

        private static func isSilentStart(_ v: [Character]) -> Bool {
            let s = String(v)
            for prefix in ["GN", "KN", "PN", "WR", "PS"] where s.hasPrefix(prefix) {
                return true
            }
            return false
        }

        // MARK: - Main loop

        func run() {
            while index <= last {
                switch v[index] {
                case "A", "E", "I", "O", "U", "Y":
                    if index == 0 { add("A") }
                    index += 1
                case "B":
                    add("P")
                    index += charAt(index + 1) == "B" ? 2 : 1
                case "C":
                    handleC()
                case "D":
                    handleD()
                case "F":
                    add("F")
                    index += charAt(index + 1) == "F" ? 2 : 1
                case "G":
                    handleG()
                case "H":
                    handleH()
                case "J":
                    handleJ()
                case "K":
                    add("K")
                    index += charAt(index + 1) == "K" ? 2 : 1
                case "L":
                    add("L")
                    index += charAt(index + 1) == "L" ? 2 : 1
                case "M":
                    add("M")
                    index += conditionM0() ? 2 : 1
                case "N":
                    add("N")
                    index += charAt(index + 1) == "N" ? 2 : 1
                case "P":
                    handleP()
                case "Q":
                    add("K")
                    index += charAt(index + 1) == "Q" ? 2 : 1
                case "R":
                    handleR()
                case "S":
                    handleS()
                case "T":
                    handleT()
                case "V":
                    add("F")
                    index += charAt(index + 1) == "V" ? 2 : 1
                case "W":
                    handleW()
                case "X":
                    handleX()
                case "Z":
                    handleZ()
                default:
                    index += 1
                }
            }
        }

        // MARK: - Handlers (primary code only)

        private func conditionM0() -> Bool {
            if charAt(index + 1) == "M" { return true }
            return contains(index - 1, 3, "UMB")
                && (index + 1 == last || contains(index + 2, 2, "ER"))
        }

        private func handleC() {
            if conditionC0() {
                add("K")
                index += 2
            } else if index == 0 && contains(index, 6, "CAESAR") {
                add("S")
                index += 2
            } else if contains(index, 2, "CH") {
                handleCH()
            } else if contains(index, 2, "CZ") && !contains(index - 2, 4, "WICZ") {
                add("S")
                index += 2
            } else if contains(index + 1, 3, "CIA") {
                add("X")
                index += 3
            } else if contains(index, 2, "CC") && !(index == 1 && charAt(0) == "M") {
                handleCC()
            } else if contains(index, 2, "CK", "CG", "CQ") {
                add("K")
                index += 2
            } else if contains(index, 2, "CI", "CE", "CY") {
                add("S")
                index += 2
            } else {
                add("K")
                if contains(index + 1, 2, " C", " Q", " G") {
                    index += 3
                } else if contains(index + 1, 1, "C", "K", "Q") && !contains(index + 1, 2, "CE", "CI") {
                    index += 2
                } else {
                    index += 1
                }
            }
        }

        private func conditionC0() -> Bool {
            if contains(index, 4, "CHIA") { return true }
            if index <= 1 { return false }
            if isVowel(index - 2) { return false }
            if !contains(index - 1, 3, "ACH") { return false }
            let c = charAt(index + 2)
            return (c != "I" && c != "E") || contains(index - 2, 6, "BACHER", "MACHER")
        }

        private func handleCC() {
            if contains(index + 2, 1, "I", "E", "H") && !contains(index + 2, 2, "HU") {
                if (index == 1 && charAt(index - 1) == "A") || contains(index - 1, 5, "UCCEE", "UCCES") {
                    add("KS")
                } else {
                    add("X")
                }
                index += 3
            } else {
                add("K")
                index += 2
            }
        }

        private func handleCH() {
            if index > 0 && contains(index, 4, "CHAE") {
                add("K")
                index += 2
            } else if conditionCH0() {
                add("K")
                index += 2
            } else if conditionCH1() {
                add("K")
                index += 2
            } else {
                if index > 0 {
                    add(contains(0, 2, "MC") ? "K" : "X")
                } else {
                    add("X")
                }
                index += 2
            }
        }

        private func conditionCH0() -> Bool {
            if index != 0 { return false }
            if !contains(index + 1, 5, "HARAC", "HARIS")
                && !contains(index + 1, 3, "HOR", "HYM", "HIA", "HEM") { return false }
            if contains(0, 5, "CHORE") { return false }
            return true
        }

        private func conditionCH1() -> Bool {
            let lrnmbhfvwSpace = contains(index + 2, 1, "L", "R", "N", "M", "B", "H", "F", "V", "W", " ")
            return (contains(0, 4, "VAN ", "VON ") || contains(0, 3, "SCH"))
                || contains(index - 2, 6, "ORCHES", "ARCHIT", "ORCHID")
                || contains(index + 2, 1, "T", "S")
                || ((contains(index - 1, 1, "A", "O", "U", "E") || index == 0)
                    && (lrnmbhfvwSpace || index + 1 == last))
        }

        private func handleD() {
            if contains(index, 2, "DG") {
                if contains(index + 2, 1, "I", "E", "Y") {
                    add("J")
                    index += 3
                } else {
                    add("TK")
                    index += 2
                }
            } else if contains(index, 2, "DT", "DD") {
                add("T")
                index += 2
            } else {
                add("T")
                index += 1
            }
        }

        private func handleG() {
            if charAt(index + 1) == "H" {
                handleGH()
            } else if charAt(index + 1) == "N" {
                if index == 1 && isVowel(0) && !slavoGermanic {
                    add("KN")
                } else if !contains(index + 2, 2, "EY") && charAt(index + 1) != "Y" && !slavoGermanic {
                    add("N")
                } else {
                    add("KN")
                }
                index += 2
            } else if contains(index + 1, 2, "LI") && !slavoGermanic {
                add("KL")
                index += 2
            } else if index == 0
                && (charAt(index + 1) == "Y"
                    || contains(index + 1, 2, "ES", "EP", "EB", "EL", "EY", "IB", "IL", "IN", "IE", "EI", "ER")) {
                add("K")
                index += 2
            } else if (contains(index + 1, 2, "ER") || charAt(index + 1) == "Y")
                && !contains(0, 6, "DANGER", "RANGER", "MANGER")
                && !contains(index - 1, 1, "E", "I")
                && !contains(index - 1, 3, "RGY", "OGY") {
                add("K")
                index += 2
            } else if contains(index + 1, 1, "E", "I", "Y") || contains(index - 1, 4, "AGGI", "OGGI") {
                if contains(0, 4, "VAN ", "VON ") || contains(0, 3, "SCH") || contains(index + 1, 2, "ET") {
                    add("K")
                } else if contains(index + 1, 4, "IER") {
                    add("J")
                } else {
                    add("J")
                }
                index += 2
            } else if charAt(index + 1) == "G" {
                index += 2
                add("K")
            } else {
                index += 1
                add("K")
            }
        }

        private func handleGH() {
            if index > 0 && !isVowel(index - 1) {
                add("K")
                index += 2
            } else if index == 0 {
                add(charAt(index + 2) == "I" ? "J" : "K")
                index += 2
            } else if (index > 1 && contains(index - 2, 1, "B", "H", "D"))
                || (index > 2 && contains(index - 3, 1, "B", "H", "D"))
                || (index > 3 && contains(index - 4, 1, "B", "H")) {
                index += 2
            } else {
                if index > 2 && charAt(index - 1) == "U" && contains(index - 3, 1, "C", "G", "L", "R", "T") {
                    add("F")
                } else if index > 0 && charAt(index - 1) != "I" {
                    add("K")
                }
                index += 2
            }
        }

        private func handleH() {
            if (index == 0 || isVowel(index - 1)) && isVowel(index + 1) {
                add("H")
                index += 2
            } else {
                index += 1
            }
        }

        private func handleJ() {
            if contains(index, 4, "JOSE") || contains(0, 4, "SAN ") {
                if (index == 0 && charAt(index + 4) == " ") || last + 1 == 4 || contains(0, 4, "SAN ") {
                    add("H")
                } else {
                    add("J")
                }
                index += 1
            } else {
                if index == 0 && !contains(index, 4, "JOSE") {
                    add("J")
                } else if isVowel(index - 1) && !slavoGermanic
                    && (charAt(index + 1) == "A" || charAt(index + 1) == "O") {
                    add("J")
                } else if index == last {
                    add("J")
                } else if !contains(index + 1, 1, "L", "T", "K", "S", "N", "M", "B", "Z")
                    && !contains(index - 1, 1, "S", "K", "L") {
                    add("J")
                }
                index += charAt(index + 1) == "J" ? 2 : 1
            }
        }

        private func handleP() {
            if charAt(index + 1) == "H" {
                add("F")
                index += 2
            } else {
                add("P")
                index += contains(index + 1, 1, "P", "B") ? 2 : 1
            }
        }

        private func handleR() {
            // 'R' at the end of a French-style "…IER" is silent in the primary
            // code (the alternate keeps it — dropped here).
            if !(index == last && !slavoGermanic
                && contains(index - 2, 2, "IE") && !contains(index - 4, 2, "ME", "MA")) {
                add("R")
            }
            index += charAt(index + 1) == "R" ? 2 : 1
        }

        private func handleS() {
            if contains(index - 1, 3, "ISL", "YSL") {
                index += 1
            } else if index == 0 && contains(index, 5, "SUGAR") {
                add("X")
                index += 1
            } else if contains(index, 2, "SH") {
                add(contains(index + 1, 4, "HEIM", "HOEK", "HOLM", "HOLZ") ? "S" : "X")
                index += 2
            } else if contains(index, 3, "SIO", "SIA") || contains(index, 4, "SIAN") {
                add("S")
                index += 3
            } else if (index == 0 && contains(index + 1, 1, "M", "N", "L", "W")) || contains(index + 1, 1, "Z") {
                add("S")
                index += contains(index + 1, 1, "Z") ? 2 : 1
            } else if contains(index, 2, "SC") {
                handleSC()
            } else {
                if !(index == last && contains(index - 2, 2, "AI", "OI")) {
                    add("S")
                }
                index += contains(index + 1, 1, "S", "Z") ? 2 : 1
            }
        }

        private func handleSC() {
            if charAt(index + 2) == "H" {
                if contains(index + 3, 2, "OO", "ER", "EN", "UY", "ED", "EM") {
                    add(contains(index + 3, 2, "ER", "EN") ? "X" : "SK")
                } else {
                    add("X")
                }
            } else if contains(index + 2, 1, "I", "E", "Y") {
                add("S")
            } else {
                add("SK")
            }
            index += 3
        }

        private func handleT() {
            if contains(index, 4, "TION") {
                add("X")
                index += 3
            } else if contains(index, 3, "TIA", "TCH") {
                add("X")
                index += 3
            } else if contains(index, 2, "TH") || contains(index, 3, "TTH") {
                if contains(index + 2, 2, "OM", "AM") || contains(0, 4, "VAN ", "VON ") || contains(0, 3, "SCH") {
                    add("T")
                } else {
                    add("0")
                }
                index += 2
            } else {
                add("T")
                index += contains(index + 1, 1, "T", "D") ? 2 : 1
            }
        }

        private func handleW() {
            if contains(index, 2, "WR") {
                add("R")
                index += 2
            } else if index == 0 && (isVowel(index + 1) || contains(index, 2, "WH")) {
                add("A")
                index += 1
            } else if (index == last && isVowel(index - 1))
                || contains(index - 1, 5, "EWSKI", "EWSKY", "OWSKI", "OWSKY")
                || contains(0, 3, "SCH") {
                // Alternate-only 'F' (Arnow ↔ Arnoff) — dropped from primary.
                index += 1
            } else if contains(index, 4, "WICZ", "WITZ") {
                add("TS")
                index += 4
            } else {
                index += 1
            }
        }

        private func handleX() {
            if index == 0 {
                add("S")
                index += 1
            } else {
                if !(index == last
                    && (contains(index - 3, 3, "IAU", "EAU") || contains(index - 2, 2, "AU", "OU"))) {
                    add("KS")
                }
                index += contains(index + 1, 1, "C", "X") ? 2 : 1
            }
        }

        private func handleZ() {
            if charAt(index + 1) == "H" {
                add("J")
                index += 2
            } else {
                add("S")
                index += charAt(index + 1) == "Z" ? 2 : 1
            }
        }
    }
}
