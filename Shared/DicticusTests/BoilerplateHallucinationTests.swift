import XCTest
@testable import Dicticus

/// Quick task 260827-81z Task 2: RED-first tests for
/// `BoilerplateHallucination`, the narrow whole-utterance closed-list discard
/// for Whisper's confident pause hallucinations (measured: 10 of 959 raw
/// decodes over 14 days, 1.04%; 9 of those 10 were the exact whole utterance
/// "Thank you."). Single copy in `Shared/DicticusTests/`, compiled into both
/// the macOS and iOS test targets via `project.yml`'s
/// `- path: ../Shared/DicticusTests` entry.
///
/// Matching semantics under test: trim leading/trailing whitespace and
/// newlines, then compare for EXACT string equality against a five-entry
/// closed list. Case-sensitive. No substring, prefix, or suffix matching. No
/// confidence/logprob/no-speech-probability/threshold term anywhere — this is
/// a string comparison and nothing else (spike 260805-qx7 measured and
/// rejected general confidence gating).
final class BoilerplateHallucinationTests: XCTestCase {

    // MARK: - Positives: exact ship-list entries MUST be discarded

    func testPrimaryPhraseIsDiscarded() {
        XCTAssertEqual(BoilerplateHallucination.match("Thank you."), "Thank you.")
    }

    func testPrimaryPhraseWithSurroundingWhitespaceAndNewlineIsDiscarded() {
        XCTAssertEqual(BoilerplateHallucination.match("  Thank you. \n"), "Thank you.")
    }

    func testThanksForWatchingIsDiscarded() {
        XCTAssertEqual(BoilerplateHallucination.match("Thanks for watching!"), "Thanks for watching!")
    }

    func testThankYouForWatchingIsDiscarded() {
        XCTAssertEqual(BoilerplateHallucination.match("Thank you for watching."), "Thank you for watching.")
    }

    func testPleaseSubscribeIsDiscarded() {
        XCTAssertEqual(BoilerplateHallucination.match("Please subscribe to my channel."), "Please subscribe to my channel.")
    }

    func testVielenDankFuersZuschauenIsDiscarded() {
        XCTAssertEqual(BoilerplateHallucination.match("Vielen Dank fürs Zuschauen."), "Vielen Dank fürs Zuschauen.")
    }

    // MARK: - Negatives: the adversarial set is the point of this task

    func testGenuineDictationBeginningWithThePhraseIsNotDiscarded() {
        XCTAssertNil(BoilerplateHallucination.match("Thank you so much for the help."))
    }

    func testPhraseAsMidSubstringIsNotDiscarded() {
        XCTAssertNil(BoilerplateHallucination.match("I just wanted to thank you."))
    }

    func testPhraseAsLeadingSentenceOfLongerUtteranceIsNotDiscarded() {
        XCTAssertNil(BoilerplateHallucination.match("Thank you. Can you re-run the suite?"))
    }

    func testPlausibleGermanVielenDankIsNotDiscarded() {
        XCTAssertNil(BoilerplateHallucination.match("Vielen Dank."))
    }

    func testPlausibleGermanDankeIsNotDiscarded() {
        XCTAssertNil(BoilerplateHallucination.match("Danke."))
    }

    func testAllLowercaseFormIsNotDiscardedCaseSensitivity() {
        XCTAssertNil(BoilerplateHallucination.match("thank you."))
    }

    func testPrimaryPhraseWithoutTerminalPeriodIsNotDiscarded() {
        XCTAssertNil(BoilerplateHallucination.match("Thank you"))
    }

    func testEmptyStringReturnsNoMatch() {
        XCTAssertNil(BoilerplateHallucination.match(""))
    }

    func testWhitespaceOnlyStringReturnsNoMatch() {
        XCTAssertNil(BoilerplateHallucination.match("   "))
    }

    // MARK: - Ship-list lock (ClosedListTests.swift convention)

    /// Asserts the EXACT expected set, so widening the list later is a
    /// deliberate, reviewed edit rather than silent drift.
    func testShipListIsExactlyFiveEntries() {
        let expected: Set<String> = [
            "Thank you.",
            "Thanks for watching!",
            "Thank you for watching.",
            "Please subscribe to my channel.",
            "Vielen Dank fürs Zuschauen."
        ]
        XCTAssertEqual(BoilerplateHallucination.shipList, expected)
    }

    // MARK: - Short stock words (260930-s1g)
    //
    // Closed set {you, and, -} discarded when the whole decode is one of them
    // AND (clip < 1.5 s OR the Layer-2 gate heard no voice). Positives are the
    // five measured live records, cited by discard-log timestamp only.

    private func short(_ text: String, _ duration: Float, voice: Bool) -> String? {
        BoilerplateHallucination.matchShortStock(text, durationSeconds: duration, voiceDetected: voice)
    }

    // Duration arm (voiceDetected: true is the only state a sub-2.0 s clip reaches the guard in)

    func testShortStockDurationArm_0928T164929_you() {
        XCTAssertEqual(short("you", 1.3, voice: true), "you")
    }

    func testShortStockDurationArm_0926T031841_And() {
        XCTAssertEqual(short("And", 1.1, voice: true), "And")
    }

    func testShortStockDurationArm_0920T130717_dash() {
        XCTAssertEqual(short("-", 1.2, voice: true), "-")
    }

    func testShortStockDurationArmTrimsWhitespace() {
        XCTAssertEqual(short("  you \n", 1.0, voice: true), "you")
    }

    func testShortStockDurationArmComparesLowercased() {
        XCTAssertEqual(short("You", 1.0, voice: true), "You")
    }

    func testShortStockDurationArmJustInsideBound() {
        XCTAssertEqual(
            short("you", BoilerplateHallucination.shortStockMaxDurationSeconds.nextDown, voice: true),
            "you")
    }

    // No-voice arm

    func testShortStockNoVoiceArm_0920T081506_you() {
        XCTAssertEqual(short("you", 12.8, voice: false), "you")
    }

    func testShortStockNoVoiceArm_0926T053103_you() {
        XCTAssertEqual(short("you", 2.9, voice: false), "you")
    }

    // Negatives, duration arm (voiceDetected: true)

    func testShortStockBoundIsExclusive() {
        XCTAssertNil(short("you", BoilerplateHallucination.shortStockMaxDurationSeconds, voice: true))
    }

    func testShortStockLongClipWithVoiceHeardPassesThrough() {
        XCTAssertNil(short("you", 2.9, voice: true))
    }

    func testShortStockApprovedPassesThrough() {
        XCTAssertNil(short("Approved.", 1.1, voice: true))
    }

    func testShortStockSingleLetterIPassesThrough() {
        XCTAssertNil(short("I", 1.1, voice: true))
    }

    func testShortStockSoEllipsisPassesThrough() {
        XCTAssertNil(short("So...", 1.2, voice: true))
    }

    func testShortStockPunctuatedYouPassesThrough() {
        XCTAssertNil(short("You.", 1.2, voice: true))
    }

    func testShortStockPunctuatedAndPassesThrough() {
        XCTAssertNil(short("and.", 1.2, voice: true))
    }

    func testShortStockMultiTokenPassesThrough() {
        XCTAssertNil(short("you know", 1.2, voice: true))
    }

    func testShortStockThankYouIsNotInShortList() {
        XCTAssertNil(short("Thank you.", 1.2, voice: true))
    }

    func testShortStockEmptyPassesThrough() {
        XCTAssertNil(short("", 1.0, voice: true))
    }

    func testShortStockWhitespaceOnlyPassesThrough() {
        XCTAssertNil(short("   ", 1.0, voice: true))
    }

    // Negatives, no-voice arm (voiceDetected: false)

    func testShortStockNoVoiceOutOfSetMultiTokenPassesThrough() {
        XCTAssertNil(short("we should ship it", 3.5, voice: false))
    }

    func testShortStockNoVoicePunctuatedYouPassesThrough() {
        XCTAssertNil(short("You.", 2.9, voice: false))
    }

    func testShortStockNoVoiceWhitespaceOnlyPassesThrough() {
        XCTAssertNil(short("   ", 2.9, voice: false))
    }

    // Unconditional list untouched

    func testUnconditionalMatchStillRejectsBareYou() {
        XCTAssertNil(BoilerplateHallucination.match("you"))
    }

    // Locks

    func testShortStockListIsExactlyThreeEntries() {
        XCTAssertEqual(BoilerplateHallucination.shortStockList, ["you", "and", "-"])
    }

    func testShortStockMaxDurationIsOnePointFiveSeconds() {
        XCTAssertEqual(BoilerplateHallucination.shortStockMaxDurationSeconds, 1.5)
    }

    // MARK: - Quick 261008-gb2: per-chunk boilerplate drop (F1)
    //
    // A long clip is decoded as several chunks. A chunk that is only a ship-list phrase
    // next to other chunks is a pause phantom; a sole chunk is left to the whole-clip
    // `match`; a phrase inside a longer chunk is never touched.

    private func drops(_ chunks: [(String, String)]) -> [BoilerplateHallucination.ChunkDropReason?] {
        BoilerplateHallucination.chunkDropReasons(chunks.map { (text: $0.0, language: $0.1) })
    }

    func testChunkDropTrailingThankYouChunk_RED() {
        let r = drops([("We moved the review to the second floor and booked the lamp room", "en"), ("Thank you.", "en")])
        XCTAssertEqual(r, [nil, .boilerplateSegment])
    }

    func testChunkDropLeadingDashThankYouChunk_RED() {
        let r = drops([
            ("The ferry leaves earlier on Sundays", "en"),
            ("Der Kaffee ist leider schon kalt geworden", "de"),
            ("- Thank you.", "en")
        ])
        XCTAssertEqual(r, [nil, nil, .boilerplateSegment])
    }

    func testChunkDropEveryChunkIsPhantom_RED() {
        let r = drops([("Thank you.", "en"), ("Thank you.", "en")])
        XCTAssertEqual(r, [.boilerplateSegment, .boilerplateSegment])
    }

    func testChunkDropSoleChunkIsLeftToWholeClipMatch() {
        XCTAssertEqual(drops([("Thank you.", "en")]), [nil])
    }

    func testChunkDropPhraseInsideLongerChunkIsKept() {
        let r = drops([
            ("Thank you. The garden gate needs a new hinge", "en"),
            ("The tomatoes are almost ready. Thank you.", "en"),
            ("Thank you. Thank you.", "en")
        ])
        XCTAssertEqual(r, [nil, nil, nil])
    }

    func testChunkDropGermanThanksStaysExcluded() {
        XCTAssertEqual(drops([("Der Zug hat Verspätung", "de"), ("Vielen Dank.", "de")]), [nil, nil])
        XCTAssertEqual(drops([("Der Zug hat Verspätung", "de"), ("Danke.", "de")]), [nil, nil])
    }

    func testChunkDropCaseAndPunctuationStayExact() {
        XCTAssertEqual(drops([("The ferry leaves early", "en"), ("thank you.", "en")]), [nil, nil])
        XCTAssertEqual(drops([("The ferry leaves early", "en"), ("Thank you", "en")]), [nil, nil])
    }

    func testChunkDropEmptyListGivesEmptyArray() {
        XCTAssertEqual(drops([]).count, 0)
    }

    // MARK: - Quick 261008-gb2: per-chunk language drop (F2)

    func testChunkDropPolishLookingChunkAfterGerman_RED() {
        let r = drops([("Wir sehen uns heute am Fluss", "de"), ("Zaplamy toki mase.", "pl")])
        XCTAssertEqual(r, [nil, .nonDeEnLanguage])
    }

    func testChunkDropSoleSpanishLookingChunk_RED() {
        XCTAssertEqual(drops([("Las mesas verdes cantan.", "es")]), [.nonDeEnLanguage])
    }

    func testChunkDropGermanAndEnglishChunksAreKept() {
        XCTAssertEqual(drops([("Das Boot liegt am Steg", "de"), ("The boat is at the pier", "en")]), [nil, nil])
    }

    func testChunkDropShipListChunkTaggedOtherLanguageIsBoilerplateFirst() {
        let r = drops([("The kettle is on the left shelf", "en"), ("Thank you.", "pl")])
        XCTAssertEqual(r, [nil, .boilerplateSegment])
    }

    func testChunkLanguagesAreExactlyGermanAndEnglish() {
        XCTAssertEqual(BoilerplateHallucination.chunkLanguages, ["de", "en"])
    }
}
