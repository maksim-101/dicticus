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
}
