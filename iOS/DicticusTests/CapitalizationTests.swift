import XCTest
@testable import Dicticus

/// CapitalizationTests (Phase 42 Plan 07 / MLANG-01) — deterministic post-gate
/// capitalization: the first alphabetic character of pasted output, plus the
/// standalone English pronoun "I" and its contractions.
///
/// Locks the exact production contract of
/// `TextProcessingService.applyFinalCapitalization(_:language:)`, which runs
/// AFTER the Step 3a divergence gate (and NumberRevert) in `process(...)` so a
/// gate revert to the (often lowercase ASR) rules baseline can never leave the
/// pasted output uncapitalized — the 42-05 UAT #21/#26/#15 failures ("of
/// course…", "and also…", "what did i do" all landed lowercase because the
/// gate reverted the LLM's own capitalization).
///
/// `applyFinalCapitalization` is `nonisolated static` — a pure,
/// MainActor-independent transform — so these tests call it directly without
/// any actor hop or service instantiation, matching the style of
/// `SelfCorrectionResolverTests`.
///
/// Per `feedback_cleanup_cross_platform_parity`: this file is byte-identical
/// to `iOS/DicticusTests/CapitalizationTests.swift`.
final class CapitalizationTests: XCTestCase {

    // MARK: - First-letter capitalization (the 42-05 UAT gate-revert failures)

    func testOfCourseCapitalizesFirstLetter() {
        XCTAssertEqual(
            TextProcessingService.applyFinalCapitalization("of course, that makes sense.", language: "en"),
            "Of course, that makes sense.",
            "42-05 UAT #21: gate-reverted lowercase 'of course…' must be capitalized post-gate"
        )
    }

    func testAndAlsoCapitalizesFirstLetter() {
        XCTAssertEqual(
            TextProcessingService.applyFinalCapitalization("and also this happened.", language: "en"),
            "And also this happened.",
            "42-05 UAT #26: gate-reverted lowercase 'and also…' must be capitalized post-gate"
        )
    }

    func testGermanFirstLetterCapitalized() {
        XCTAssertEqual(
            TextProcessingService.applyFinalCapitalization("ich bin da", language: "de"),
            "Ich bin da"
        )
    }

    func testLeadingQuoteSkippedToFirstLetter() {
        XCTAssertEqual(
            TextProcessingService.applyFinalCapitalization("\"hello,\" she said.", language: "en"),
            "\"Hello,\" she said.",
            "leading punctuation/quotes are skipped; the first ALPHABETIC character is capitalized"
        )
    }

    func testAlreadyCapitalizedTextUnchanged() {
        let text = "Already correct."
        XCTAssertEqual(
            TextProcessingService.applyFinalCapitalization(text, language: "en"),
            text,
            "idempotent: already-correct text must pass through byte-identical"
        )
    }

    func testEmptyStringUnchanged() {
        XCTAssertEqual(TextProcessingService.applyFinalCapitalization("", language: "en"), "")
    }

    func testNoAlphabeticCharacterUnchanged() {
        let text = "42 3.14 99"
        XCTAssertEqual(TextProcessingService.applyFinalCapitalization(text, language: "de"), text)
    }

    // MARK: - English standalone "I" + contractions (42-05 UAT #15)

    func testWhatDidICapitalizesBothFirstLetterAndPronoun() {
        // 42-05 UAT #15: both the sentence-initial capital AND the standalone
        // "i" fire together on real production output — that IS the shipped
        // contract (the two rules are not mutually exclusive).
        XCTAssertEqual(
            TextProcessingService.applyFinalCapitalization("what did i do", language: "en"),
            "What did I do"
        )
    }

    func testEnglishIContractions() {
        XCTAssertEqual(TextProcessingService.applyFinalCapitalization("i'm here", language: "en"), "I'm here")
        XCTAssertEqual(TextProcessingService.applyFinalCapitalization("i've done it", language: "en"), "I've done it")
        XCTAssertEqual(TextProcessingService.applyFinalCapitalization("i'll go", language: "en"), "I'll go")
        XCTAssertEqual(TextProcessingService.applyFinalCapitalization("i'd like that", language: "en"), "I'd like that")
    }

    func testStandaloneIMidSentenceCapitalized() {
        XCTAssertEqual(
            TextProcessingService.applyFinalCapitalization("She said i was right.", language: "en"),
            "She said I was right."
        )
    }

    func testAlreadyCapitalizedIUnchanged() {
        let text = "I already start with I"
        XCTAssertEqual(
            TextProcessingService.applyFinalCapitalization(text, language: "en"),
            text,
            "idempotent: an already-capitalized 'I' must not be touched again"
        )
    }

    // MARK: - Guards: never mid-word, never German "ich", English-only

    func testIInsideWordNotCapitalized() {
        XCTAssertEqual(
            TextProcessingService.applyFinalCapitalization("She said i sit and kim waits.", language: "en"),
            "She said I sit and kim waits.",
            "'sit' and 'kim' must NOT have their internal 'i' touched — only the standalone token is"
        )
    }

    func testTypoWithoutApostropheNotTreatedAsPronoun() {
        XCTAssertEqual(
            TextProcessingService.applyFinalCapitalization("She said im not sure.", language: "en"),
            "She said im not sure.",
            "'im' (no apostrophe) is not a recognized pronoun token — only the sentence-initial rule may fire, and it doesn't apply here since the sentence starts with 'She'"
        )
    }

    func testGermanIchNeverTouchedByEnglishPronounRule() {
        let text = "ich weiß nicht, ob ich das kann."
        // First-letter rule still fires (capitalizes the leading "i" of "ich"
        // as any German sentence-initial letter would be), but the
        // English-"I" pronoun pass must NEVER run for German — "ich" stays
        // "ich" everywhere else in the sentence.
        let result = TextProcessingService.applyFinalCapitalization(text, language: "de")
        XCTAssertEqual(result, "Ich weiß nicht, ob ich das kann.")
        XCTAssertTrue(result.contains("ob ich das"), "German 'ich' mid-sentence must never be capitalized")
    }

    func testGermanTextUnaffectedByEnglishIRuleEvenWithStandaloneI() {
        // Guards against a language-detection edge case: even if the German
        // text happens to contain a lone "i"-shaped token, the EN-only pass
        // must not fire for language == "de".
        let text = "isolierte Wörter i wie in einer Liste"
        let result = TextProcessingService.applyFinalCapitalization(text, language: "de")
        XCTAssertTrue(result.contains(" i "), "the EN pronoun pass must not run for German text")
    }

    // MARK: - Multi-sentence sentence-initial capitalization (D-10)

    func testMultiSentenceEnglishCapitalizesEverySentence() {
        XCTAssertEqual(
            TextProcessingService.applyFinalCapitalization("hello. how are you? fine.", language: "en"),
            "Hello. How are you? Fine."
        )
    }

    func testMultiSentenceGermanCapitalizesEverySentence() {
        XCTAssertEqual(
            TextProcessingService.applyFinalCapitalization("hallo. wie geht es dir? gut.", language: "de"),
            "Hallo. Wie geht es dir? Gut."
        )
    }

    func testMultiSentenceAlreadyCorrectIsIdempotent() {
        let text = "Hello. How are you? Fine."
        XCTAssertEqual(
            TextProcessingService.applyFinalCapitalization(text, language: "en"),
            text,
            "idempotent: already-correct multi-sentence text must pass through byte-identical"
        )
    }

    func testAbbreviationPmNotTreatedAsSentenceBoundary() {
        let text = "We met at 3 p.m. and left."
        XCTAssertEqual(
            TextProcessingService.applyFinalCapitalization(text, language: "en"),
            text,
            "'p.m.' must never be treated as a sentence boundary"
        )
    }

    func testAbbreviationEgNotTreatedAsSentenceBoundary() {
        let text = "See e.g. this example."
        XCTAssertEqual(
            TextProcessingService.applyFinalCapitalization(text, language: "en"),
            text,
            "'e.g.' must never be treated as a sentence boundary"
        )
    }

    func testGermanAbbreviationZbNotTreatedAsSentenceBoundary() {
        let text = "Siehe z.B. das Beispiel."
        XCTAssertEqual(
            TextProcessingService.applyFinalCapitalization(text, language: "de"),
            text,
            "'z.B.' must never be treated as a sentence boundary"
        )
    }

    func testAbbreviationDrNotTreatedAsSentenceBoundary() {
        let text = "Dr. Meier ist hier."
        XCTAssertEqual(
            TextProcessingService.applyFinalCapitalization(text, language: "de"),
            text,
            "'Dr.' must never be treated as a sentence boundary"
        )
    }

    func testDecimalNotTreatedAsSentenceBoundary() {
        let text = "Opus 4.8 is out."
        XCTAssertEqual(
            TextProcessingService.applyFinalCapitalization(text, language: "en"),
            text,
            "a decimal/version dot has no whitespace after it and must never be treated as a sentence boundary"
        )
    }

    func testEllipsisNotTreatedAsSentenceBoundary() {
        let text = "Wait... really?"
        XCTAssertEqual(
            TextProcessingService.applyFinalCapitalization(text, language: "en"),
            text,
            "a run of dots is not a sentence boundary"
        )
    }

    // MARK: - Quick 261010-8do: a leading number keeps the next word's case

    func testLeadingNumberKeepsNextWordCase_RED() {
        let de = "4 oder 5 genügen sicher."
        XCTAssertEqual(
            TextProcessingService.applyFinalCapitalization(de, language: "de"),
            de,
            "a number before the first letter means the word after it keeps the case it was dictated with"
        )
        let en = "3 apples were left on the shelf."
        XCTAssertEqual(TextProcessingService.applyFinalCapitalization(en, language: "en"), en)
    }

    func testLeadingNumberBehindLineBreakOrQuoteKeepsNextWordCase_RED() {
        let de = "\n6 und 7 fehlen noch."
        XCTAssertEqual(TextProcessingService.applyFinalCapitalization(de, language: "de"), de)
        let en = "\"8 of them,\" she said."
        XCTAssertEqual(TextProcessingService.applyFinalCapitalization(en, language: "en"), en)
    }

    func testLeadingNumberTokenNotCapitalizedMidToken_RED() {
        let ordinal = "1st round starts at noon."
        XCTAssertEqual(
            TextProcessingService.applyFinalCapitalization(ordinal, language: "en"),
            ordinal,
            "a number-led token must not get a capital inside the word ('1St')"
        )
        let clock = "10am suits everyone."
        XCTAssertEqual(TextProcessingService.applyFinalCapitalization(clock, language: "en"), clock)
    }

    func testLeadingNumberStillCapitalizesNextSentence_RED() {
        XCTAssertEqual(
            TextProcessingService.applyFinalCapitalization("3 apples were left. then we went home.", language: "en"),
            "3 apples were left. Then we went home."
        )
        XCTAssertEqual(
            TextProcessingService.applyFinalCapitalization("4 oder 5 genügen. danach sehen wir weiter.", language: "de"),
            "4 oder 5 genügen. Danach sehen wir weiter."
        )
    }

    func testNumberedSentenceStartStillCapitalized() {
        XCTAssertEqual(
            TextProcessingService.applyFinalCapitalization("3. dann prüfen wir das.", language: "de"),
            "3. Dann prüfen wir das.",
            "a numbered start is capitalized by the sentence-initial pass once the first-letter pass skips the digit"
        )
        XCTAssertEqual(
            TextProcessingService.applyFinalCapitalization("5. next we sort the list.", language: "en"),
            "5. Next we sort the list."
        )
    }

    func testSentenceStartingWithNumberMidTextKeepsNextWordCase() {
        let de = "Das war gut. 4 bis 6 kommen morgen."
        XCTAssertEqual(TextProcessingService.applyFinalCapitalization(de, language: "de"), de)
        let en = "We counted twice. 2 of them were empty."
        XCTAssertEqual(TextProcessingService.applyFinalCapitalization(en, language: "en"), en)
    }

    func testLeadingDigitAcronymUnchanged() {
        let de = "2FA ist jetzt aktiv."
        XCTAssertEqual(TextProcessingService.applyFinalCapitalization(de, language: "de"), de)
        let en = "3D models load slowly."
        XCTAssertEqual(TextProcessingService.applyFinalCapitalization(en, language: "en"), en)
    }

    func testLeadingSymbolSkippedToFirstLetter() {
        XCTAssertEqual(
            TextProcessingService.applyFinalCapitalization("→ next the lid closes.", language: "en"),
            "→ Next the lid closes.",
            "a leading symbol is skipped like leading punctuation; only a number stops the first-letter pass"
        )
    }
}
