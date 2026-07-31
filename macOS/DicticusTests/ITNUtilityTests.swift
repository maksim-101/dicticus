import XCTest
@testable import Dicticus

final class ITNUtilityTests: XCTestCase {

    // MARK: - Existing tests (must remain green)

    func testEnglishITN() {
        let input = "I have one hundred twenty three apples"
        let output = ITNUtility.applyITN(to: input, language: "en")
        XCTAssertEqual(output, "I have 123 apples")
    }

    func testEnglishHyphenatedITN() {
        let input = "The answer is forty-two"
        let output = ITNUtility.applyITN(to: input, language: "en")
        XCTAssertEqual(output, "The answer is 42")
    }

    func testGermanITN() {
        let input = "Ich habe einhundertdreiundzwanzig Äpfel"
        let output = ITNUtility.applyITN(to: input, language: "de")
        XCTAssertEqual(output, "Ich habe 123 Äpfel")
    }

    func testGermanComplexITN() {
        let input = "Das kostet viertausendfünfhundert Euro"
        let output = ITNUtility.applyITN(to: input, language: "de")
        XCTAssertEqual(output, "Das kostet 4500 Euro")
    }

    func testMixedText() {
        let input = "There are five birds and one cat"
        let output = ITNUtility.applyITN(to: input, language: "en")
        XCTAssertEqual(output, "There are five birds and one cat")
    }

    func testNoNumbers() {
        let input = "Hello world"
        let output = ITNUtility.applyITN(to: input, language: "en")
        XCTAssertEqual(output, "Hello world")
    }

    // MARK: - P0 regression tests (UAT record 134 — number concatenation bug)

    func testEnglishTwentyFiveNotConcatenated() {
        // NSNumberFormatter parsed "twenty five" (space) as 2005 because it tries
        // space-separated form first. Fix: try hyphenated form first.
        let output = ITNUtility.applyITN(to: "I have twenty five apples", language: "en")
        XCTAssertEqual(output, "I have 25 apples")
    }

    func testEnglishFortyOneNotConcatenated() {
        let output = ITNUtility.applyITN(to: "Page forty one", language: "en")
        XCTAssertEqual(output, "Page 41")
    }

    func testEnglishThirtySevenNotConcatenated() {
        let output = ITNUtility.applyITN(to: "thirty seven", language: "en")
        XCTAssertEqual(output, "37")
    }

    // MARK: - P3 structural word tests (numeric context conversion)

    func testEnglishPointBetweenDigits() {
        // "25 point 1" → "25.1"
        let output = ITNUtility.applyITN(to: "Version 25 point 1", language: "en")
        XCTAssertEqual(output, "Version 25.1")
    }

    func testEnglishDashBetweenDigits() {
        // "25 dash 06" → "25-06"
        let output = ITNUtility.applyITN(to: "25 dash 06", language: "en")
        XCTAssertEqual(output, "25-06")
    }

    func testEnglishHyphenBetweenDigits() {
        // "10 hyphen 3" → "10-3"
        let output = ITNUtility.applyITN(to: "10 hyphen 3", language: "en")
        XCTAssertEqual(output, "10-3")
    }

    func testEnglishPointAndDashVersionString() {
        // UAT record 134: "twenty five point one dash zero six" → "25.1-06"
        let output = ITNUtility.applyITN(to: "twenty five point one dash zero six", language: "en")
        XCTAssertEqual(output, "25.1-06")
    }

    func testGermanPunktBetweenDigits() {
        // "25 Punkt 1" → "25.1"
        let output = ITNUtility.applyITN(to: "25 Punkt 1", language: "de")
        XCTAssertEqual(output, "25.1")
    }

    func testGermanKommaBetweenDigits() {
        // "25 Komma 5" → "25,5"
        let output = ITNUtility.applyITN(to: "25 Komma 5", language: "de")
        XCTAssertEqual(output, "25,5")
    }

    func testEnglishPointNoFalsePositive() {
        // "the point is clear" — "point" NOT adjacent to digits, must not convert
        let output = ITNUtility.applyITN(to: "the point is clear", language: "en")
        XCTAssertEqual(output, "the point is clear")
    }

    func testGermanPunktNoFalsePositive() {
        // "Punkt eins" — left side has no digit, must not convert
        let output = ITNUtility.applyITN(to: "Punkt eins", language: "de")
        XCTAssertEqual(output, "Punkt eins")
    }

    func testEnglishZeroCollapseAfterDash() {
        // "1 dash zero 6" → "1-06"
        let output = ITNUtility.applyITN(to: "1 dash zero 6", language: "en")
        XCTAssertEqual(output, "1-06")
    }

    // MARK: - Phase 36.1 ITN guard fixtures (Wave 0 RED scaffolding)
    //
    // These fixtures assert behaviors that Plan 36.1-03 will implement.
    // Until that plan lands, these tests will fail — that is the intended RED state.

    func testITN_boundaryGuard_noCommaMerge() {
        // Boundary guard: a number-merge window must not span clause punctuation.
        // "one, two, three" must remain "one, two, three" — not collapse to "102, three".
        let output = ITNUtility.applyITN(to: "one, two, three", language: "en")
        XCTAssertEqual(output, "one, two, three",
            "Phase 36.1: boundary guard — comma must terminate merge window, no cross-comma merge")
    }

    func testITN_magnitudeGuard_twentyMillion() {
        // Magnitude guard: the count word converts but the magnitude word stays spelled.
        // "twenty million" → "20 million" (NOT "20000000").
        let output = ITNUtility.applyITN(to: "twenty million", language: "en")
        XCTAssertEqual(output, "20 million",
            "Phase 36.1: magnitude guard — twenty million must become 20 million, not 20000000")
    }

    func testITN_magnitudeGuard_lowCountStaysSpelled() {
        // Magnitude guard: counts < 10 stay fully spelled even with a magnitude word.
        // "four billion" stays "four billion".
        let output = ITNUtility.applyITN(to: "four billion", language: "en")
        XCTAssertEqual(output, "four billion",
            "Phase 36.1: magnitude guard — four billion must stay spelled (count < 10 threshold)")
    }

    func testITN_referenceNoun_findingNumberEN() {
        // Reference-noun promotion (EN): "finding number" prefix triggers digit promotion.
        // "finding number three" → "finding number 3".
        let output = ITNUtility.applyITN(to: "finding number three", language: "en")
        XCTAssertEqual(output, "finding number 3",
            "Phase 36.1: reference-noun promotion — finding number three must become finding number 3")
    }

    func testITN_referenceNoun_befundNummerDE() {
        // Reference-noun promotion (DE): "Befund Nummer" prefix triggers digit promotion.
        // "Befund Nummer drei" → "Befund Nummer 3".
        let output = ITNUtility.applyITN(to: "Befund Nummer drei", language: "de")
        XCTAssertEqual(output, "Befund Nummer 3",
            "Phase 36.1: reference-noun promotion DE — Befund Nummer drei must become Befund Nummer 3")
    }

    // MARK: - Phase 36.4 word-form decimal / version normalization (Wave 0 RED scaffolding)
    //
    // These fixtures assert behaviors that Plan 36.4-03 will implement by extending
    // ITNUtility.applyNumericStructuralWords to handle word-form decimals and versions.
    // Until that plan lands, these tests FAIL — that is the intended RED state (D-08/D-09).
    //
    // Called directly on applyNumericStructuralWords to pin the function-level contract
    // that Plan 03 must satisfy, without depending on the full applyITN chain.

    func testWordFormDecimalAndVersionNormalization() {
        // RED: "four point eight" — word-form decimal, no preceding digit/identifier.
        // applyNumericStructuralWords currently requires a digit on the left; Plan 03 adds word-form support.
        XCTAssertEqual(
            ITNUtility.applyNumericStructuralWords(to: "four point eight", language: "en"),
            "4.8",
            "Phase 36.4 D-08: word-form decimal 'four point eight' must become '4.8' (RED until Plan 03)"
        )
        // RED: "two point five point one" — pure word-form version chain.
        XCTAssertEqual(
            ITNUtility.applyNumericStructuralWords(to: "two point five point one", language: "en"),
            "2.5.1",
            "Phase 36.4 D-08: word-form version chain 'two point five point one' must become '2.5.1' (RED until Plan 03)"
        )
        // RED: "opus four point eight" — leading non-identifier word.
        // The ITN pass normalizes the NUMBER only; capitalization of 'opus' is the LLM's job.
        XCTAssertEqual(
            ITNUtility.applyNumericStructuralWords(to: "opus four point eight", language: "en"),
            "opus 4.8",
            "Phase 36.4 D-08: 'opus four point eight' — ITN must normalize number to '4.8', leave 'opus' unchanged (RED until Plan 03)"
        )
        // RED: "version two point five" — regression guard via applyNumericStructuralWords.
        // (Note: full chain via applyITN already produces 'version 2.5' via Pattern B;
        //  this test pins the applyNumericStructuralWords contract directly for Plan 03.)
        XCTAssertEqual(
            ITNUtility.applyNumericStructuralWords(to: "version two point five", language: "en"),
            "version 2.5",
            "Phase 36.4 D-08: 'version two point five' — applyNumericStructuralWords must produce 'version 2.5' (RED until Plan 03)"
        )
        // GREEN guard: date negative — month-name lookback must keep these unchanged (D-09).
        // The decimal normalizer must NOT fire when a month name precedes the pattern.
        XCTAssertEqual(
            ITNUtility.applyNumericStructuralWords(to: "January one point five hours", language: "en"),
            "January one point five hours",
            "Phase 36.4 D-09: month-name lookback guard — 'January one point five hours' must stay unchanged"
        )
        // GREEN guard: Pitfall 3 — existing decimal token '4.8' must not be split by further passes.
        XCTAssertEqual(
            ITNUtility.applyNumericStructuralWords(to: "4.8 version", language: "en"),
            "4.8 version",
            "Phase 36.4 Pitfall 3: '4.8 version' — decimal token must not be altered"
        )
    }
}

// MARK: - Phase 28 D-03 (Plan 28-02): Single-digit identifier-adjacent promotion tests

final class ITNUtilitySingleDigitTests: XCTestCase {

    // MARK: - Pattern A: Capitalized stem prefix (EN)

    func testEnglishCapitalStem_E_one_to_E1() {
        XCTAssertEqual(
            ITNUtility.applyITN(to: "working on E one and M three", language: "en"),
            "working on E1 and M3"
        )
    }

    func testEnglishMixedCaseStem_Gemini_three_point_one_to_3_1() {
        // "model" (Pattern B) fires on "model Gemini" is not the fixture;
        // this tests the chain: Pattern A on "Ge" stem + structural point pass.
        // R1 analysis: "Gemini" (6-char Title-Case) doesn't match stem regex.
        // Adjusted fixture: use "model" as Pattern B prefix for "three" conversion,
        // then structural pass converts "3 point one" -> "3.1".
        // Per plan requirement: the chain test demonstrates the ordering guarantee.
        XCTAssertEqual(
            ITNUtility.applyITN(to: "model three point one beats model two", language: "en"),
            "model 3.1 beats model 2"
        )
    }

    func testEnglishVersionWord_version_two_to_2() {
        XCTAssertEqual(
            ITNUtility.applyITN(to: "version two and option one", language: "en"),
            "version 2 and option 1"
        )
    }

    func testEnglishProse_three_preserved() {
        XCTAssertEqual(
            ITNUtility.applyITN(to: "I have three meetings today", language: "en"),
            "I have three meetings today"
        )
    }

    func testEnglishPronoun_one_preserved() {
        XCTAssertEqual(
            ITNUtility.applyITN(to: "one might think this is odd", language: "en"),
            "one might think this is odd"
        )
    }

    func testEnglishSentenceStart_Three_preserved() {
        XCTAssertEqual(
            ITNUtility.applyITN(to: "Three things matter here", language: "en"),
            "Three things matter here"
        )
    }

    func testEnglishCamelStem_iOS_seven_to_iOS7() {
        XCTAssertEqual(
            ITNUtility.applyITN(to: "running iOS seven on iPhone", language: "en"),
            "running iOS7 on iPhone"
        )
    }

    func testEnglishChain_Phase_one_of_E_three_release() {
        // Pattern B fires on "Phase one" -> "Phase 1"; Pattern A fires on "E three" -> "E3"
        XCTAssertEqual(
            ITNUtility.applyITN(to: "Phase one of E three release", language: "en"),
            "Phase 1 of E3 release"
        )
    }

    func testEnglishProsePrefix_Cat_one_preserved() {
        // "Cat" (3-char Title-Case) is excluded by R1 stem regex
        XCTAssertEqual(
            ITNUtility.applyITN(to: "Cat one of the breeds is friendly", language: "en"),
            "Cat one of the breeds is friendly"
        )
    }

    // MARK: - German tests

    func testGermanIdentifier_Version_zwei_to_2() {
        XCTAssertEqual(
            ITNUtility.applyITN(to: "Version zwei läuft", language: "de"),
            "Version 2 läuft"
        )
    }

    func testGermanInflected_einer_in_identifier_position() {
        XCTAssertEqual(
            ITNUtility.applyITN(to: "Modell einer", language: "de"),
            "Modell 1"
        )
    }

    func testGermanInflected_Modell_einer_mit_Schritt_zwoelf() {
        XCTAssertEqual(
            ITNUtility.applyITN(to: "Modell einer mit Schritt zwölf", language: "de"),
            "Modell 1 mit Schritt 12"
        )
    }

    func testGermanProse_einer_as_pronoun() {
        XCTAssertEqual(
            ITNUtility.applyITN(to: "einer von uns muss gehen", language: "de"),
            "einer von uns muss gehen"
        )
    }

    func testGermanProse_drei_Termine_preserved() {
        XCTAssertEqual(
            ITNUtility.applyITN(to: "ich habe drei Termine", language: "de"),
            "ich habe drei Termine"
        )
    }

    func testGermanSentenceStart_Drei_preserved() {
        XCTAssertEqual(
            ITNUtility.applyITN(to: "Drei Punkte sind wichtig", language: "de"),
            "Drei Punkte sind wichtig"
        )
    }

    // MARK: - Task 260723-qtb: eine-family article vs. identifier disambiguation

    func testGermanArticle_eine_beforeNounPhrase_notPromoted() {
        // Evidence sentence from .planning/debug/log-analysis-2026-07-23.md (defect D):
        // "eine" here is the indefinite article introducing "andere Organisationseinheit",
        // not an identifier value for "Schritt" — must round-trip unchanged.
        XCTAssertEqual(
            ITNUtility.applyITN(to: "in einem zweiten Schritt eine andere Organisationseinheit", language: "de"),
            "in einem zweiten Schritt eine andere Organisationseinheit"
        )
    }

    func testGermanIdentifier_eine_atUtteranceEnd_stillConverts() {
        // Nothing follows "eine" before the clause-final period — genuine identifier use.
        XCTAssertEqual(
            ITNUtility.applyITN(to: "Bitte gehe zu Schritt eine.", language: "de"),
            "Bitte gehe zu Schritt 1."
        )
    }

    func testGermanIdentifier_eine_beforeSafeContinuation_stillConverts() {
        // "für" is a safe-continuation preposition — genuine identifier use continuing
        // the same clause, not a new noun phrase.
        XCTAssertEqual(
            ITNUtility.applyITN(to: "Schritt eine für alle", language: "de"),
            "Schritt 1 für alle"
        )
    }

    // MARK: - Phase 28 CR-01 regression: 2-char Title-Case prose bigrams must not match Pattern A

    func testEnglishProseBigram_No_one_preserved() {
        // CR-01: "No one knows" must NOT become "No1 knows"
        XCTAssertEqual(
            ITNUtility.applyITN(to: "No one knows that.", language: "en"),
            "No one knows that."
        )
    }

    func testEnglishProseBigram_At_one_preserved() {
        // CR-01: "At one point" must NOT become "At1 point"
        XCTAssertEqual(
            ITNUtility.applyITN(to: "At one point we agreed", language: "en"),
            "At one point we agreed"
        )
    }

    func testEnglishProseBigram_In_one_preserved() {
        // CR-01: "In one hour" must NOT become "In1 hour"
        XCTAssertEqual(
            ITNUtility.applyITN(to: "In one hour we leave", language: "en"),
            "In one hour we leave"
        )
    }

    func testEnglishProseBigram_Go_five_preserved() {
        // CR-01: "Go five steps" must NOT become "Go5 steps"
        XCTAssertEqual(
            ITNUtility.applyITN(to: "Go five steps forward", language: "en"),
            "Go five steps forward"
        )
    }

    func testGermanProseBigram_Im_eins_preserved() {
        // CR-01 (DE parity): "Im Jahr eins" — the bigram "Im eins" would have
        // matched the old [A-Z][a-zäöüß]? pattern and produced "Im1 Jahr" style
        // mangling. Use a direct adjacency case to lock the regex behavior.
        XCTAssertEqual(
            ITNUtility.applyITN(to: "Im eins zwei drei Spiel", language: "de"),
            "Im eins zwei drei Spiel"
        )
    }
}

final class ITNUtilityAcronymCollapseTests: XCTestCase {

    func testNFSK_collapses() {
        XCTAssertEqual(ITNUtility.collapseAcronymRun(to: "The N F S K tool is great"), "The NFSK tool is great")
    }

    func testBrNAC_mixedCase_collapses() {
        XCTAssertEqual(ITNUtility.collapseAcronymRun(to: "Br N A C done"), "BrNAC done")
    }

    func testUSB_threeFragment_collapses() {
        XCTAssertEqual(ITNUtility.collapseAcronymRun(to: "U S B port"), "USB port")
    }

    func testIAmOK_notCollapsed() {
        XCTAssertEqual(ITNUtility.collapseAcronymRun(to: "I am O K"), "I am O K")
    }

    func testALowercaseB_notCollapsed() {
        XCTAssertEqual(ITNUtility.collapseAcronymRun(to: "a B test"), "a B test")
    }

    func testTwoFragmentRun_notCollapsed() {
        XCTAssertEqual(ITNUtility.collapseAcronymRun(to: "N F"), "N F")
    }

    func testTrailingComma_reattaches() {
        XCTAssertEqual(ITNUtility.collapseAcronymRun(to: "ran the N F S K, today"), "ran the NFSK, today")
    }

    func testZed_insideRun_resolvesToZ() {
        XCTAssertEqual(ITNUtility.collapseAcronymRun(to: "zed E D files"), "ZED files")
    }

    func testZee_insideRun_resolvesToZ() {
        XCTAssertEqual(ITNUtility.collapseAcronymRun(to: "zee E D"), "ZED")
    }

    func testAitch_insideRun_resolvesToH() {
        XCTAssertEqual(ITNUtility.collapseAcronymRun(to: "N aitch K S"), "NHKS")
    }

    func testDoubleU_insideRun_resolvesToW() {
        XCTAssertEqual(ITNUtility.collapseAcronymRun(to: "double-u W T F"), "WWTF")
    }

    func testZee_standalone_notSubstituted() {
        XCTAssertEqual(ITNUtility.collapseAcronymRun(to: "on zee street"), "on zee street")
    }
}

// MARK: - Phase 32 PUNCT-01/PUNCT-02: Spoken punctuation collapse tests
final class ITNUtilitySpokenPunctuationTests: XCTestCase {

    // MARK: - Unambiguous EN

    func testSlash_collapses() {
        XCTAssertEqual(ITNUtility.collapseSpokenPunctuation(to: "path slash home"), "path/home")
    }

    func testBackslash_collapses() {
        XCTAssertEqual(ITNUtility.collapseSpokenPunctuation(to: "C backslash Windows"), "C\\Windows")
    }

    func testUnderscore_collapses() {
        XCTAssertEqual(ITNUtility.collapseSpokenPunctuation(to: "foo underscore bar"), "foo_bar")
    }

    func testAsterisk_collapses() {
        XCTAssertEqual(ITNUtility.collapseSpokenPunctuation(to: "a asterisk b"), "a * b")
    }

    func testSemicolon_collapses() {
        XCTAssertEqual(ITNUtility.collapseSpokenPunctuation(to: "x semicolon y"), "x ; y")
    }

    func testAtSign_twoToken_collapses() {
        XCTAssertEqual(ITNUtility.collapseSpokenPunctuation(to: "my email at sign domain"), "my email @ domain")
    }

    func testHash_collapses() {
        XCTAssertEqual(ITNUtility.collapseSpokenPunctuation(to: "use hash tag"), "use # tag")
    }

    func testCaret_collapses() {
        XCTAssertEqual(ITNUtility.collapseSpokenPunctuation(to: "a caret b"), "a ^ b")
    }

    func testTilde_collapses() {
        XCTAssertEqual(ITNUtility.collapseSpokenPunctuation(to: "home tilde folder"), "home ~ folder")
    }

    func testHyphen_collapses() {
        XCTAssertEqual(ITNUtility.collapseSpokenPunctuation(to: "well hyphen known"), "well-known")
    }

    // MARK: - German seeds

    func testBindestrich_collapses() {
        XCTAssertEqual(ITNUtility.collapseSpokenPunctuation(to: "Bindestrich"), "-")
    }

    func testSchrägstrich_collapses() {
        XCTAssertEqual(ITNUtility.collapseSpokenPunctuation(to: "Schrägstrich"), "/")
    }

    func testUnterstrich_collapses() {
        XCTAssertEqual(ITNUtility.collapseSpokenPunctuation(to: "foo Unterstrich bar"), "foo_bar")
    }

    func testKlammeraffe_collapses() {
        XCTAssertEqual(ITNUtility.collapseSpokenPunctuation(to: "user Klammeraffe host"), "user @ host")
    }

    func testRaute_collapses() {
        XCTAssertEqual(ITNUtility.collapseSpokenPunctuation(to: "Raute tag"), "# tag")
    }

    func testSternchen_collapses() {
        XCTAssertEqual(ITNUtility.collapseSpokenPunctuation(to: "a Sternchen b"), "a * b")
    }

    // MARK: - Conditional positives

    func testMinus_identifierFlank_collapses() {
        XCTAssertEqual(ITNUtility.collapseSpokenPunctuation(to: "Claude minus ops"), "Claude-ops")
    }

    func testDot_identifierFlank_collapses() {
        XCTAssertEqual(ITNUtility.collapseSpokenPunctuation(to: "example dot com"), "example.com")
    }

    func testColon_identifierFlank_collapses() {
        XCTAssertEqual(ITNUtility.collapseSpokenPunctuation(to: "key colon value"), "key:value")
    }

    // MARK: - Decimal dot (numeric flank)

    func testDecimalDot_tenDotFive_collapses() {
        XCTAssertEqual(ITNUtility.collapseSpokenPunctuation(to: "ten dot five"), "10.5")
    }

    // MARK: - SC4 negative / prose guards

    func testMinus_proseFlanks_unchanged() {
        XCTAssertEqual(ITNUtility.collapseSpokenPunctuation(to: "five minus three"), "five minus three")
    }

    func testSixtyPlusRules_unchanged() {
        XCTAssertEqual(ITNUtility.collapseSpokenPunctuation(to: "the 60 plus rules"), "the 60 plus rules")
    }

    func testColonVsDash_unchanged() {
        XCTAssertEqual(ITNUtility.collapseSpokenPunctuation(to: "colon vs. dash"), "colon vs. dash")
    }

    func testDotProduct_unchanged() {
        XCTAssertEqual(ITNUtility.collapseSpokenPunctuation(to: "dot product"), "dot product")
    }

    func testDotDotDot_unchanged() {
        XCTAssertEqual(ITNUtility.collapseSpokenPunctuation(to: "dot dot dot"), "dot dot dot")
    }

    // MARK: - D-08 dollar / pipe

    func testDollar_proseFlank_unchanged() {
        XCTAssertEqual(ITNUtility.collapseSpokenPunctuation(to: "I earn one dollar"), "I earn one dollar")
    }

    func testDollar_identifierFlank_collapses() {
        XCTAssertEqual(ITNUtility.collapseSpokenPunctuation(to: "dollar PATH set"), "$ PATH set")
    }

    func testPipe_neverCollapses() {
        XCTAssertEqual(ITNUtility.collapseSpokenPunctuation(to: "cat pipe grep"), "cat pipe grep")
    }
}

// MARK: - Phase 32 PUNCT-02 extension: identifier–number collapse (post-ITN model names)

final class ITNUtilityIdentifierNumberPunctuationTests: XCTestCase {

    // MARK: Positives — model-name patterns (alpha identifier + digit number)

    func testMinus_shortStemAndNumber_collapses() {
        XCTAssertEqual(ITNUtility.collapseIdentifierNumberPunctuation(to: "mt minus 24"), "mt-24")
    }

    func testMinus_singleCapLetterAndNumber_collapses() {
        XCTAssertEqual(ITNUtility.collapseIdentifierNumberPunctuation(to: "H minus 100"), "H-100")
    }

    func testMinus_acronymAndNumber_collapses() {
        XCTAssertEqual(ITNUtility.collapseIdentifierNumberPunctuation(to: "GPT minus 4"), "GPT-4")
    }

    func testMinus_capitalizedWordAndNumber_collapses() {
        XCTAssertEqual(ITNUtility.collapseIdentifierNumberPunctuation(to: "Claude minus 4"), "Claude-4")
    }

    func testMinus_mixedStemWithDigitAndNumber_collapses() {
        XCTAssertEqual(ITNUtility.collapseIdentifierNumberPunctuation(to: "RTX minus 4090"), "RTX-4090")
    }

    func testMinus_inSentence_collapses() {
        XCTAssertEqual(
            ITNUtility.collapseIdentifierNumberPunctuation(to: "Would the mt minus 24 work"),
            "Would the mt-24 work"
        )
    }

    func testDot_shortStemAndNumber_collapses() {
        XCTAssertEqual(ITNUtility.collapseIdentifierNumberPunctuation(to: "v dot 2"), "v.2")
    }

    func testColon_shortStemAndNumber_collapses() {
        XCTAssertEqual(ITNUtility.collapseIdentifierNumberPunctuation(to: "key colon 5"), "key:5")
    }

    func testMinus_trailingPunctuationPreserved() {
        XCTAssertEqual(ITNUtility.collapseIdentifierNumberPunctuation(to: "the mt minus 24."), "the mt-24.")
    }

    // MARK: Negatives — prose subtraction and arithmetic must stay untouched

    func testMinus_proseNounAndNumber_unchanged() {
        XCTAssertEqual(ITNUtility.collapseIdentifierNumberPunctuation(to: "total minus 12"), "total minus 12")
    }

    func testMinus_proseNounAndNumber_budget_unchanged() {
        XCTAssertEqual(ITNUtility.collapseIdentifierNumberPunctuation(to: "budget minus 100"), "budget minus 100")
    }

    func testMinus_numberAndNumber_arithmetic_unchanged() {
        XCTAssertEqual(ITNUtility.collapseIdentifierNumberPunctuation(to: "24 minus 12"), "24 minus 12")
    }

    func testMinus_numberWords_unchanged() {
        XCTAssertEqual(ITNUtility.collapseIdentifierNumberPunctuation(to: "five minus three"), "five minus three")
    }

    func testMinus_stopwordStem_unchanged() {
        XCTAssertEqual(ITNUtility.collapseIdentifierNumberPunctuation(to: "a minus 5"), "a minus 5")
    }
}
