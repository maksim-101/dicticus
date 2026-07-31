import Foundation

/// Phase 44 Plan 04 (D-02 / D-02a): the lemma-lock predicate that replaces
/// the edit-distance-based (OSA-2) blanket-accept clause at
/// `CleanupService.swift:1038-1040` — the confirmed leak that let
/// `wohnst`→`wohne` (a person flip) and
/// `Führungsrhythmus`→`Führungsrythmus` (an introduced typo) both pass as
/// "near-miss respellings." Edit distance cannot separate a typo fix from a
/// meaning flip at equal distance; identity can. `isAllowedInflection` is
/// the ONLY accept path for a content-word substitution — there is no
/// edit-distance fallback behind it (see 44-RESEARCH.md Pitfall 1).
///
/// RISK DIRECTION (asymmetric, per 44-RESEARCH.md Pitfall 2 and D-02a): a
/// false REJECT costs a missed repair (the LLM's fix is discarded, the
/// baseline token survives — annoying but safe). A false ACCEPT costs a
/// corrupted meaning pasted at the user's cursor. Every ambiguous case in
/// this file resolves toward REJECT. Do not special-case irregular verbs
/// (`lauft`/`läuft`, `singen`/`sang`) to make them pass — their rejection is
/// a deliberate, priced false-reject (see `InflectionRulesTests`).
///
/// Pure lookup + string logic — no `NaturalLanguage` import, no dependency
/// on `CleanupService`, no actor isolation.
public enum InflectionRules {

    // MARK: - Suffix tables (D-02 inflection vs D-02a derivation)

    /// Legal German inflectional endings: verb agreement (`-e/-st/-t/-en`
    /// person forms, `-te/-ten/-test/-tet` preterite forms) plus noun/
    /// adjective declension endings (`-s/-es/-em/-en/-er`, and `""` for the
    /// unmarked nominative/bare form — e.g. `Format`'s nominative has no
    /// ending, `Formats`' genitive adds `-s`). Does NOT include any
    /// derivational suffix — see `germanDerivationalSuffixes`, checked
    /// first and disjoint from this set by construction.
    public static let germanInflectionalSuffixes: Set<String> = [
        "", "e", "en", "er", "es", "em", "n", "s", "t", "st", "et", "te", "ten", "test", "tet"
    ]

    /// Legal English inflectional endings: plural/3rd-person `-s/-es`,
    /// past tense `-ed/-d`, progressive `-ing`, comparative/superlative
    /// `-er/-est`, plus `""` for the unmarked base form.
    public static let englishInflectionalSuffixes: Set<String> = [
        "", "s", "es", "ed", "d", "ing", "er", "est"
    ]

    /// D-02a's block list (amended 2026-07-12, user decision on research
    /// evidence): German derivational suffixes that create a NEW lemma, not
    /// an inflected form of the old one. `Handhabe`→`Handhabung` is the
    /// named example (SUPERSEDED from D-02's original "permitted" table
    /// entry — see `InflectionRulesTests.testHandhabeToHandhabungIsBlocked`)
    /// but the class is general: `Krankheit`(illness)→`Kränkung`(insult),
    /// `Beobachter`(observer)→`Beobachtung`(observation) are the same
    /// morphological operation and equally forbidden.
    public static let germanDerivationalSuffixes: Set<String> = [
        "ung", "heit", "keit", "nis", "schaft", "tum", "chen", "lein", "lich", "ig", "bar", "sam", "haft", "los", "ei"
    ]

    /// English derivational suffixes, symmetric with `germanDerivationalSuffixes`
    /// per D-02's "applies symmetrically to DE and EN" requirement:
    /// `inform`→`information`, `manage`→`management`, `dark`→`darkness`.
    public static let englishDerivationalSuffixes: Set<String> = [
        "tion", "sion", "ment", "ness", "ity", "able", "ible", "ful", "less", "ish", "ize", "ise", "ly"
    ]

    /// Trap A (44-RESEARCH.md Pitfall 1 / D-02): German verb endings that
    /// carry grammatical PERSON, not just tense/mood. A transition where
    /// EITHER side's remainder is one of these is rejected outright — this
    /// is what blocks `wohnst`(2nd person)→`wohne`(1st person), the exact
    /// pair the pre-Phase-44 gate's edit-distance-based leniency clause let
    /// through.
    /// German only — English marks person on the pronoun, not the verb
    /// ending, so this trap does not apply to `englishInflectionalSuffixes`.
    public static let germanPersonEndings: Set<String> = ["e", "st", "test", "te"]

    // MARK: - Safe swaps (function-word gender/number agreement)

    /// Canonical, sorted-pair-joined (`"a|b"`, always alphabetically
    /// sorted so lookup is order-independent) function-word swaps that
    /// `isAllowedInflection` accepts WITHOUT going through the stem/suffix
    /// predicate at all. These are article/copula agreement fixes
    /// (`der`↔`das`, `is`↔`are`) whose stems are too short to survive the
    /// stem-length floor (`der`/`das` share a 1-char common prefix) — D-02
    /// explicitly names `der`→`das` as permitted, so this set exists to
    /// keep that promise without loosening the floor for content words.
    public static let safeSwaps: Set<String> = {
        let germanArticleForms = ["der", "die", "das", "den", "dem", "des"]
        let germanIndefiniteForms = ["ein", "eine", "einen", "einem", "einer", "eines"]
        var pairs: Set<String> = []
        for forms in [germanArticleForms, germanIndefiniteForms] {
            for i in 0..<forms.count {
                for j in (i + 1)..<forms.count {
                    pairs.insert(canonicalPairKey(forms[i], forms[j]))
                }
            }
        }
        pairs.insert(canonicalPairKey("is", "are"))
        pairs.insert(canonicalPairKey("was", "were"))
        pairs.insert(canonicalPairKey("a", "an"))
        return pairs
    }()

    private static func canonicalPairKey(_ a: String, _ b: String) -> String {
        [a, b].sorted().joined(separator: "|")
    }

    private static func isSafeSwap(_ a: String, _ b: String) -> Bool {
        safeSwaps.contains(canonicalPairKey(a, b))
    }

    // MARK: - Stem-length floor (CALIBRATED — see 44-04-SUMMARY.md)

    /// [CALIBRATED — see 44-04-SUMMARY.md] The minimum shared-prefix length
    /// (in characters) `isAllowedInflection` requires before it will treat a
    /// suffix transition as a legal inflection. This is the `Wagen`→`wagt`
    /// block (`wag` is 3 chars) and the general defense against the
    /// stem-crossover class (44-RESEARCH.md Pitfall 3). Verify against
    /// `EditGuardFixtures`'s content-word substitution set before changing
    /// this value — lowering it re-admits `Wagen`/`wagt`; raising it starts
    /// rejecting real short-stem repairs (`want`→`wants`, `walk`→`walked`,
    /// both stem-length 4). 4 is the only value in {3, 4, 5} that rejects
    /// every required-reject fixture while accepting every required-accept
    /// fixture — see the calibration table in 44-04-SUMMARY.md.
    public static let stemLengthFloor: Int = 4

    // MARK: - Common-prefix stem/suffix split

    /// Splits two lowercased words on their longest common PREFIX. Shared by
    /// `isDerivational` and `isAllowedInflection` — both classification jobs
    /// are "does the divergent tail belong to a known suffix class," just
    /// against different suffix tables.
    private static func commonPrefixSplit(_ a: String, _ b: String) -> (stem: String, suffA: String, suffB: String) {
        let aChars = Array(a)
        let bChars = Array(b)
        var i = 0
        while i < aChars.count, i < bChars.count, aChars[i] == bChars[i] {
            i += 1
        }
        let stem = String(aChars.prefix(i))
        let suffA = String(aChars.dropFirst(i))
        let suffB = String(bChars.dropFirst(i))
        return (stem, suffA, suffB)
    }

    // MARK: - D-02a: derivation detection

    /// Is `candidate` a DERIVATIONAL transformation of `original` (or vice
    /// versa) — does one word END WITH a known derivational suffix such
    /// that, once stripped, the remaining stem overlaps the other word's
    /// start? Evaluated BEFORE `isAllowedInflection`'s accept path (D-02a)
    /// so a derivational change is never misread as a mere ending change,
    /// and so the caller can label the rejection `derivationalSuffixChange`
    /// rather than the generic `contentWordIdentityChange`.
    ///
    /// Uses suffix-STRIPPING (`hasSuffix` + `dropLast`), not the longest-
    /// common-PREFIX split `isAllowedInflection` uses, because derivational
    /// suffixes routinely attach via a linking form the raw suffix string
    /// doesn't capture on its own — `inform`→`informat` + `ion` shares only
    /// its first 6 characters with `information`'s stripped stem `informa`
    /// (the linking `-a-` is part of the derivational attachment, not the
    /// shared stem). A strict common-PREFIX split would compute `suffC =
    /// "ation"`, which is not literally in `englishDerivationalSuffixes`
    /// (only `"tion"` is) and would miss this case.
    ///
    /// Requires the stripped stem and the other word to share a common
    /// prefix of at least 2 characters — without this floor, two unrelated
    /// short words that happen to end in a derivational suffix by
    /// coincidence would be misclassified as derivational. This does not
    /// change the overall verdict of `isAllowedInflection` (both the
    /// derivational and the generic identity-change classes reject), but
    /// keeps the classification honest for D-10's per-class scoring.
    public static func isDerivational(_ original: String, _ candidate: String, language: String) -> Bool {
        let o = original.lowercased()
        let c = candidate.lowercased()
        guard o != c else { return false }
        let isEnglish = language.prefix(2).lowercased() == "en"
        let derivationalSuffixes = isEnglish ? englishDerivationalSuffixes : germanDerivationalSuffixes

        for suffix in derivationalSuffixes {
            if c.hasSuffix(suffix), c.count > suffix.count {
                let strippedStem = String(c.dropLast(suffix.count))
                if commonPrefixSplit(o, strippedStem).stem.count >= 2 { return true }
            }
            if o.hasSuffix(suffix), o.count > suffix.count {
                let strippedStem = String(o.dropLast(suffix.count))
                if commonPrefixSplit(c, strippedStem).stem.count >= 2 { return true }
            }
        }
        return false
    }

    // MARK: - D-02: the lemma-lock predicate

    /// The single predicate that decides whether `candidate` is a legal
    /// inflection of `original`'s lemma (ACCEPT) or a change of identity
    /// (REJECT). This is the ONLY accept path for a content-word
    /// substitution — there is no edit-distance fallback behind it
    /// (44-RESEARCH.md Pitfall 1). Fail-closed: `return false` is the last
    /// line.
    ///
    /// Evaluated in this exact order:
    /// 1. Lowercase both; identical → accept.
    /// 2. Known function-word safe swap (`der`↔`das`, `is`↔`are`, …) → accept.
    /// 3. D-02a derivational-suffix change → reject (checked before the
    ///    suffix-transition path, or `-ung` would slip through as an
    ///    "ending change").
    /// 4. Split on longest common prefix into stem + two suffixes.
    /// 5. Trap B (strip-to-empty, directional): the CANDIDATE's suffix
    ///    stripping to nothing → reject. Blocks `Hunde`→`Hund`,
    ///    `tolles`→`toll`, `Messer`→`Messe`. Deliberately NOT symmetric —
    ///    the ORIGINAL having no suffix while the candidate adds one is the
    ///    ordinary case-marking direction (`Format`→`Formats`, genitive
    ///    `-s`), which D-02 requires this predicate to ACCEPT. See
    ///    `InflectionRulesTests.testFormatToFormatsAccepts` and the
    ///    Deviations section of 44-04-SUMMARY.md — the plan's literal Trap B
    ///    wording (`suffO.isEmpty || suffC.isEmpty`) would reject this
    ///    required accept; none of Trap B's own named examples
    ///    (`Hunde`→`Hund`, `Messer`→`Messe`, `tolles`→`toll`) have an empty
    ///    ORIGINAL suffix, so the directional form is the intended rule.
    /// 6. Trap A (German only): either side's suffix carries grammatical
    ///    person → reject. Blocks `wohnst`→`wohne`.
    /// 7. Stem-length floor: shared prefix shorter than `stemLengthFloor` →
    ///    reject. Blocks `Wagen`→`wagt`.
    /// 8. Both suffixes are legal inflectional endings for the language →
    ///    accept.
    /// 9. Fail closed → reject.
    public static func isAllowedInflection(_ original: String, _ candidate: String, language: String) -> Bool {
        isAllowedInflection(original, candidate, language: language, stemLengthFloor: stemLengthFloor)
    }

    /// Calibration-only overload — exposes the stem-length floor as a
    /// parameter so `InflectionRulesTests` can score floors 3, 4, and 5
    /// against the full fixture corpus (per plan 44-04 Step 7's explicit
    /// requirement). Production code MUST call the 3-argument
    /// `isAllowedInflection(_:_:language:)` above, which always uses the
    /// calibrated `stemLengthFloor` constant.
    static func isAllowedInflection(
        _ original: String,
        _ candidate: String,
        language: String,
        stemLengthFloor floor: Int
    ) -> Bool {
        let o = original.lowercased()
        let c = candidate.lowercased()

        // 1. Identity.
        if o == c { return true }

        // 2. Safe function-word swap.
        if isSafeSwap(o, c) { return true }

        // 3. D-02a — derivation is blocked, checked before the suffix path.
        if isDerivational(o, c, language: language) { return false }

        // 4. Common-prefix stem/suffix split.
        let (stem, suffO, suffC) = commonPrefixSplit(o, c)

        // 5. Trap B — strip-to-empty (directional, candidate side only).
        if suffC.isEmpty { return false }

        // 6. Trap A — German person endings, either side.
        let isEnglish = language.prefix(2).lowercased() == "en"
        if !isEnglish, germanPersonEndings.contains(suffO) || germanPersonEndings.contains(suffC) {
            return false
        }

        // 7. Stem-length floor.
        if stem.count < floor { return false }

        // 8. Both suffixes must be legal inflectional endings.
        let inflectionalSuffixes = isEnglish ? englishInflectionalSuffixes : germanInflectionalSuffixes
        if inflectionalSuffixes.contains(suffO), inflectionalSuffixes.contains(suffC) {
            return true
        }

        // 9. Fail closed.
        return false
    }
}
