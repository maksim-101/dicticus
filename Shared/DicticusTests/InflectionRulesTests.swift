import XCTest
@testable import Dicticus

/// Phase 44 Plan 04 (D-02 / D-02a): adversarial test suite for
/// `InflectionRules.isAllowedInflection` / `.isDerivational` — the lemma-lock
/// predicate that replaces the Damerau-OSA ≤2 blanket-accept clause at
/// `CleanupService.swift:1038-1040`.
///
/// Every case here is either a fixture drawn from `EditGuardFixtures.all`
/// (content-word substitution cluster) or a named example from
/// `44-CONTEXT.md` / `44-RESEARCH.md`. Where a test mirrors a fixture, its
/// name references the fixture id so the two stay traceable to each other,
/// even though this plan does not wire `InflectionRules` into the
/// `EditGuard` classifier (that is plan 44-10).
final class InflectionRulesTests: XCTestCase {

    // MARK: - Blocking-constraint fixtures (must pass; see execute-plan prompt)

    /// The proof that distance-thinking is gone: OSA-1 introduced typo.
    /// ANY edit-distance-based rule accepts this; the identity predicate
    /// must not. Mirrors fixture `fx-sub-content-de-typo-introduced`.
    func testFuehrungsrhythmusTypoIsRejected() {
        XCTAssertFalse(
            InflectionRules.isAllowedInflection("Führungsrhythmus", "Führungsrythmus", language: "de"),
            "An introduced typo (OSA-1) must be rejected — no accept class covers it."
        )
    }

    /// Trap A: person-ending flip, OSA-2. Mirrors fixture
    /// `fx-sub-content-de-personflip-verb`.
    func testWohnstToWohneIsRejected() {
        XCTAssertFalse(
            InflectionRules.isAllowedInflection("wohnst", "wohne", language: "de"),
            "wohnst -> wohne is a person flip (Trap A), not a legal inflection."
        )
    }

    /// Trap B / adversarial defeat named explicitly in 44-RESEARCH.md:
    /// spurious stem overlap via -r <-> "" transition. Mirrors fixture
    /// `fx-sub-content-de-messer-messe`.
    func testMesserToMesseIsRejected() {
        XCTAssertFalse(
            InflectionRules.isAllowedInflection("Messer", "Messe", language: "de"),
            "Messer -> Messe is a spurious stem overlap (different words), not an inflection."
        )
    }

    /// Adversarial defeat named explicitly in 44-RESEARCH.md: noun/verb
    /// crossover via -en <-> -t transition. Mirrors fixture
    /// `fx-sub-content-de-wagen-wagt`. THIS is the stem-length-floor proof —
    /// see `testStemLengthFloorCalibration` for the floor=3/4/5 comparison.
    func testWagenToWagtIsRejected() {
        XCTAssertFalse(
            InflectionRules.isAllowedInflection("Wagen", "wagt", language: "de"),
            "Wagen -> wagt is a noun/verb crossover (car -> dares), not an inflection."
        )
    }

    /// Trap B: plural -> singular strip-to-empty-suffix. Mirrors fixture
    /// `fx-sub-content-de-hunde-hund`.
    func testHundeToHundIsRejected() {
        XCTAssertFalse(
            InflectionRules.isAllowedInflection("Hunde", "Hund", language: "de"),
            "Hunde -> Hund silently flips plural to singular; Trap B must block it."
        )
    }

    /// Trap B: adjective strip-to-empty-suffix. Mirrors fixture
    /// `fx-sub-content-de-tolles-toll`.
    func testTollesToTollIsRejected() {
        XCTAssertFalse(
            InflectionRules.isAllowedInflection("tolles", "toll", language: "de"),
            "tolles -> toll strips the declined-adjective ending to empty; Trap B must block it."
        )
    }

    // MARK: - D-02a: derivation is blocked

    /// The named D-02a example: SUPERSEDES D-02's original "permitted" table
    /// entry. `isDerivational` must ALSO return true so the rejection can be
    /// classified `derivationalSuffixChange`, not the generic
    /// `contentWordIdentityChange` (per success_criteria).
    func testHandhabeToHandhabungIsBlocked() {
        XCTAssertFalse(
            InflectionRules.isAllowedInflection("Handhabe", "Handhabung", language: "de"),
            "D-02a: derivation is blocked, including the previously-permitted Handhabe -> Handhabung."
        )
        XCTAssertTrue(
            InflectionRules.isDerivational("Handhabe", "Handhabung", language: "de"),
            "isDerivational must recognize the -ung derivational suffix so D-10 can price the D-02a block."
        )
    }

    /// Same morphological operation as Handhabe -> Handhabung — the reason
    /// permitting derivation at all is unsafe. Mirrors fixture
    /// `fx-sub-content-de-beobachter-beobachtung`.
    func testBeobachterToBeobachtungIsBlocked() {
        XCTAssertFalse(
            InflectionRules.isAllowedInflection("Beobachter", "Beobachtung", language: "de"),
            "Beobachter -> Beobachtung is a derivational change (observer -> observation)."
        )
        XCTAssertTrue(
            InflectionRules.isDerivational("Beobachter", "Beobachtung", language: "de"),
            "isDerivational must fire on the -ung suffix even with a different original ending (-er)."
        )
    }

    /// Same class; umlaut mutation additionally breaks the exact-stem
    /// hypothesis for the -heit/-ung pair, so `isDerivational` is not
    /// required to fire here — only the overall REJECT verdict is required.
    /// Mirrors fixture `fx-sub-content-de-krankheit-kraenkung`.
    func testKrankheitToKraenkungIsRejected() {
        XCTAssertFalse(
            InflectionRules.isAllowedInflection("Krankheit", "Kränkung", language: "de"),
            "Krankheit -> Kränkung is a meaning-changing derivation (illness -> insult)."
        )
    }

    /// D-02: symmetric to DE — derivation is blocked in English too.
    func testEnglishDerivationsAreBlocked() {
        XCTAssertFalse(InflectionRules.isAllowedInflection("inform", "information", language: "en"))
        XCTAssertFalse(InflectionRules.isAllowedInflection("manage", "management", language: "en"))
        XCTAssertFalse(InflectionRules.isAllowedInflection("dark", "darkness", language: "en"))
        XCTAssertTrue(InflectionRules.isDerivational("inform", "information", language: "en"))
        XCTAssertTrue(InflectionRules.isDerivational("manage", "management", language: "en"))
        XCTAssertTrue(InflectionRules.isDerivational("dark", "darkness", language: "en"))
    }

    // MARK: - D-02: named blocked list (identity changes, not inflections)

    func testNamedBlockedContentWordPairsAreRejected() {
        let blockedPairs: [(String, String)] = [
            ("putzen", "bestehst"),
            ("aufzuzeigen", "aufzuführen"),
            ("Reglement", "Regelung"),
            ("bestimmt", "wahrscheinlich"),
            ("fast", "bereits")
        ]
        for (original, candidate) in blockedPairs {
            XCTAssertFalse(
                InflectionRules.isAllowedInflection(original, candidate, language: "de"),
                "\(original) -> \(candidate) is a content-identity change, not an inflection."
            )
        }
    }

    func testEnglishContentWordIdentityChangeIsRejected() {
        // Mirrors fixture fx-sub-content-en-identity-reject.
        XCTAssertFalse(
            InflectionRules.isAllowedInflection("scheduled", "planned", language: "en")
        )
    }

    // MARK: - Deliberate, priced false-rejects (irregulars — DO NOT special-case)

    /// EXPECTED FALSE REJECT — a missed repair, not a bug. Umlaut mutation
    /// breaks the exact-stem hypothesis. Do not special-case irregulars.
    /// Mirrors fixture `fx-sub-content-de-lauft-umlaut`.
    func testLauftToLaeuftIsRejectedAsDeliberateFalseReject() {
        XCTAssertFalse(
            InflectionRules.isAllowedInflection("lauft", "läuft", language: "de"),
            "EXPECTED FALSE REJECT: umlaut mutation (lauft -> läuft) is a real repair the " +
            "exact-stem hypothesis cannot see through. Priced cost of precision — do not fix."
        )
    }

    /// EXPECTED FALSE REJECT — a missed repair, not a bug. Ablaut mutation.
    /// Do not special-case irregulars. Mirrors fixture
    /// `fx-sub-content-de-singen-ablaut`.
    func testSingenToSangIsRejectedAsDeliberateFalseReject() {
        XCTAssertFalse(
            InflectionRules.isAllowedInflection("singen", "sang", language: "de"),
            "EXPECTED FALSE REJECT: ablaut mutation (singen -> sang) is a real repair the " +
            "exact-stem hypothesis cannot see through. Priced cost of precision — do not fix."
        )
    }

    // MARK: - D-02: legal inflections (ACCEPT)

    /// Mirrors fixture fx-sub-content-de-inflection-beinhalten.
    func testBeinhaltenToBeinhaltetAccepts() {
        XCTAssertTrue(
            InflectionRules.isAllowedInflection("beinhalten", "beinhaltet", language: "de"),
            "beinhalten -> beinhaltet is verb-agreement inflection of the same lemma."
        )
    }

    /// Mirrors fixture fx-sub-content-de-format-formats. THIS is the fixture
    /// that pins the Trap B directionality fix (see 44-04-SUMMARY.md
    /// Deviations) — the original's suffix is empty (nominative, unmarked)
    /// while the candidate's is not (genitive -s); this is the safe
    /// case-marking direction, not the dangerous strip-to-empty direction.
    func testFormatToFormatsAccepts() {
        XCTAssertTrue(
            InflectionRules.isAllowedInflection("Format", "Formats", language: "de"),
            "Format -> Formats is genitive case-marking, D-02's own named permitted example."
        )
    }

    func testDerToDasAccepts() {
        // Mirrors fixture fx-sub-func-de-der-das (safeSwaps path).
        XCTAssertTrue(InflectionRules.isAllowedInflection("der", "das", language: "de"))
        XCTAssertTrue(InflectionRules.isAllowedInflection("das", "der", language: "de"))
    }

    func testAllArticleAndIndefiniteCrossPairsAreSafeSwaps() {
        let articleForms = ["der", "die", "das", "den", "dem", "des"]
        for a in articleForms {
            for b in articleForms where a != b {
                XCTAssertTrue(
                    InflectionRules.isAllowedInflection(a, b, language: "de"),
                    "\(a) <-> \(b) must be a safe article-agreement swap."
                )
            }
        }
        let indefiniteForms = ["ein", "eine", "einen", "einem", "einer", "eines"]
        for a in indefiniteForms {
            for b in indefiniteForms where a != b {
                XCTAssertTrue(
                    InflectionRules.isAllowedInflection(a, b, language: "de"),
                    "\(a) <-> \(b) must be a safe indefinite-article-agreement swap."
                )
            }
        }
    }

    func testAAnIsAreWasWereAreSafeSwaps() {
        // Mirrors fixture fx-sub-func-en-a-an, plus D-02/44-04's named
        // is/are and was/were examples.
        XCTAssertTrue(InflectionRules.isAllowedInflection("a", "an", language: "en"))
        XCTAssertTrue(InflectionRules.isAllowedInflection("an", "a", language: "en"))
        XCTAssertTrue(InflectionRules.isAllowedInflection("is", "are", language: "en"))
        XCTAssertTrue(InflectionRules.isAllowedInflection("was", "were", language: "en"))
    }

    /// Mirrors fixture fx-sub-content-en-inflection-accept. THIS is also a
    /// stem-length-floor proof — stem "want" is exactly 4 characters.
    func testWantToWantsAccepts() {
        XCTAssertTrue(
            InflectionRules.isAllowedInflection("want", "wants", language: "en"),
            "want -> wants is subject-verb agreement inflection."
        )
    }

    /// Named EN example from the plan's <behavior> block (not a fixture id,
    /// but explicitly required): "commit" -> "commits" (plural, EN).
    func testCommitToCommitsAccepts() {
        XCTAssertTrue(InflectionRules.isAllowedInflection("commit", "commits", language: "en"))
    }

    /// Named EN example: "walk" -> "walked" (tense, EN). Stem "walk" is
    /// exactly 4 characters — a second stem-length-floor proof alongside
    /// want/wants.
    func testWalkToWalkedAccepts() {
        XCTAssertTrue(InflectionRules.isAllowedInflection("walk", "walked", language: "en"))
    }

    // MARK: - Identity

    func testIdenticalWordsAccept() {
        XCTAssertTrue(InflectionRules.isAllowedInflection("Format", "Format", language: "de"))
        XCTAssertTrue(InflectionRules.isAllowedInflection("word", "Word", language: "en"), "Case-only identity must accept.")
    }

    // MARK: - Fail-closed default

    func testUnrelatedWordsFailClosed() {
        XCTAssertFalse(InflectionRules.isAllowedInflection("Katze", "Baum", language: "de"))
        XCTAssertFalse(InflectionRules.isAllowedInflection("apple", "orange", language: "en"))
    }

    // MARK: - Stem-length-floor calibration (plan Step 7's explicit requirement)

    /// Runs the full `EditGuardFixtures.all` content-word substitution set
    /// against stem-length floors 3, 4, and 5 and asserts floor 4 is the
    /// only value that rejects every REQUIRED reject while accepting every
    /// REQUIRED accept. See 44-04-SUMMARY.md for the full accept/reject
    /// table this test proves.
    func testStemLengthFloorCalibration() {
        let contentWordSubstitutions = EditGuardFixtures.substituteContentWordDe
            + EditGuardFixtures.substituteContentWordEn

        XCTAssertGreaterThanOrEqual(
            contentWordSubstitutions.count, 14,
            "Calibration must run against the full content-word substitution corpus."
        )

        for floor in [3, 4, 5] {
            for fixture in contentWordSubstitutions {
                // Extract the substituted word pair from baseline/candidate.
                // Every fixture in this cluster is a single-word substitution
                // inside an otherwise-identical sentence; find the first
                // differing whitespace-delimited token pair.
                let (original, candidate) = Self.substitutedWordPair(fixture)
                let result = InflectionRules.isAllowedInflection(
                    original, candidate, language: fixture.language, stemLengthFloor: floor
                )
                let expectedAccept = fixture.expectedVerdict == .accept

                if floor == 4 {
                    XCTAssertEqual(
                        result, expectedAccept,
                        "floor=4 (the calibrated value): \(fixture.id) ('\(original)' -> '\(candidate)') " +
                        "expected \(expectedAccept ? "accept" : "reject"), got \(result)."
                    )
                } else if floor == 3, fixture.id == "fx-sub-content-de-wagen-wagt" {
                    XCTAssertTrue(
                        result,
                        "floor=3 must WRONGLY accept Wagen/wagt (stem 'wag' is 3 chars, 3 < 3 is " +
                        "false) — this is the calibration proof that floor=3 is disqualified."
                    )
                } else if floor == 5, fixture.id == "fx-sub-content-en-inflection-accept" {
                    XCTAssertFalse(
                        result,
                        "floor=5 must WRONGLY reject want/wants (stem 'want' is 4 chars, 4 < 5) — " +
                        "this is the calibration proof that floor=5 loses real repairs."
                    )
                }
            }
        }
    }

    /// Hand-picked (not parsed from prose) substituted word pair for every
    /// fixture in `substituteContentWordDe` + `substituteContentWordEn`,
    /// matching `ClosedListTests.Precondition`'s convention of exact,
    /// reviewable per-fixture mappings rather than inferred diffing.
    private static func substitutedWordPair(_ fixture: EditGuardFixtures.Fixture) -> (String, String) {
        switch fixture.id {
        case "fx-sub-content-de-personflip-verb": return ("wohnst", "wohne")
        case "fx-sub-content-de-typo-introduced": return ("Führungsrhythmus", "Führungsrythmus")
        case "fx-sub-content-de-inflection-beinhalten": return ("beinhalten", "beinhaltet")
        case "fx-sub-content-de-format-formats": return ("Format", "Formats")
        case "fx-sub-content-de-messer-messe": return ("Messer", "Messe")
        case "fx-sub-content-de-wagen-wagt": return ("Wagen", "wagt")
        case "fx-sub-content-de-hunde-hund": return ("Hunde", "Hund")
        case "fx-sub-content-de-tolles-toll": return ("tolles", "toll")
        case "fx-sub-content-de-handhabe-handhabung": return ("Handhabe", "Handhabung")
        case "fx-sub-content-de-krankheit-kraenkung": return ("Krankheit", "Kränkung")
        case "fx-sub-content-de-beobachter-beobachtung": return ("Beobachter", "Beobachtung")
        case "fx-sub-content-de-lauft-umlaut": return ("lauft", "läuft")
        case "fx-sub-content-de-singen-ablaut": return ("singen", "sang")
        case "fx-sub-content-en-identity-reject": return ("scheduled", "planned")
        case "fx-sub-content-en-inflection-accept": return ("want", "wants")
        default:
            XCTFail("Unmapped fixture id '\(fixture.id)' in substitutedWordPair — add a case.")
            return ("", "")
        }
    }

    /// Drift lock: every fixture in the content-word substitution cluster
    /// must have a mapping in `substitutedWordPair`, and vice versa — keeps
    /// the calibration test honest as `EditGuardFixtures` evolves.
    func testSubstitutedWordPairCoversEveryContentWordSubstitutionFixture() {
        let mappedIDs: Set<String> = [
            "fx-sub-content-de-personflip-verb", "fx-sub-content-de-typo-introduced",
            "fx-sub-content-de-inflection-beinhalten", "fx-sub-content-de-format-formats",
            "fx-sub-content-de-messer-messe", "fx-sub-content-de-wagen-wagt",
            "fx-sub-content-de-hunde-hund", "fx-sub-content-de-tolles-toll",
            "fx-sub-content-de-handhabe-handhabung", "fx-sub-content-de-krankheit-kraenkung",
            "fx-sub-content-de-beobachter-beobachtung", "fx-sub-content-de-lauft-umlaut",
            "fx-sub-content-de-singen-ablaut", "fx-sub-content-en-identity-reject",
            "fx-sub-content-en-inflection-accept"
        ]
        let actualIDs = Set(
            (EditGuardFixtures.substituteContentWordDe + EditGuardFixtures.substituteContentWordEn).map(\.id)
        )
        XCTAssertEqual(mappedIDs, actualIDs, "substitutedWordPair's coverage has drifted from EditGuardFixtures.")
    }
}
