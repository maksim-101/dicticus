import XCTest
@testable import Dicticus

// Phase 36.1 Wave 0 RED scaffolding.
// Tests call NumberRevert.apply(baseline:output:language:).text — the symbol
// Plan 36.1-05 creates in Shared/Utilities/NumberRevert.swift.
// Until that plan lands, these tests will not compile — that is the intended RED state.

final class NumberRevertTests: XCTestCase {

    // MARK: - word→digit revert

    func testNumberRevert_wordToDigit_revertsLLMSpelling() {
        // Baseline has the digit form "3" (ITN already promoted it).
        // LLM spelled it back to "three" — revert must restore "3".
        let result = NumberRevert.apply(
            baseline: "I have 3 items",
            output: "I have three items",
            language: "en"
        ).text
        XCTAssertEqual(result, "I have 3 items",
            "Phase 36.1: NumberRevert must revert LLM re-spelling 3→three back to 3")
    }

    // MARK: - digit→word revert

    func testNumberRevert_digitToWord_revertsLLMPromotion() {
        // Baseline keeps number-words (ITN left them spelled — baseline is authoritative).
        // LLM promoted them to digits — revert must restore the words.
        let result = NumberRevert.apply(
            baseline: "one, two, three",
            output: "1, 2, 3",
            language: "en"
        ).text
        XCTAssertEqual(result, "one, two, three",
            "Phase 36.1: NumberRevert must revert LLM digit-promotion 1,2,3 back to words")
    }

    // MARK: - budget / duplicate number-words

    func testNumberRevert_budget_handlesDuplicateNumberWords() {
        // "three" appears twice in the baseline (both as words).
        // LLM promoted both occurrences to "3".
        // Count budget must handle both occurrences without over-rewriting.
        let result = NumberRevert.apply(
            baseline: "three things, all three",
            output: "3 things, all 3",
            language: "en"
        ).text
        XCTAssertEqual(result, "three things, all three",
            "Phase 36.1: NumberRevert budget — both 'three' occurrences must revert correctly")
    }

    // MARK: - German language gating

    func testNumberRevert_deGating_ordinalsRevert() {
        // German baseline has a spelled ordinal "vierten"; LLM promoted to "4.".
        // DE map includes "vierten" → "4." — revert must restore "vierten".
        let result = NumberRevert.apply(
            baseline: "das vierten Quartal",
            output: "das 4. Quartal",
            language: "de"
        ).text
        XCTAssertEqual(result, "das vierten Quartal",
            "Phase 36.1: NumberRevert DE — vierten→4. must revert using DE ordinal map")
    }

    // MARK: - no-op when no number mismatch

    func testNumberRevert_noOp_returnsOutputUnchanged() {
        // Baseline and output agree on number forms — revert must return output unchanged.
        let output = "I have 5 meetings today"
        let result = NumberRevert.apply(
            baseline: "I have 5 meetings today",
            output: output,
            language: "en"
        ).text
        XCTAssertEqual(result, output,
            "Phase 36.1: NumberRevert no-op — matching number forms must return output unchanged")
    }

    // MARK: - sentence-final number revert (CR-01)

    func testNumberRevert_sentenceFinal_wordToDigit_revertsWithPeriod() {
        // Baseline has sentence-final word "eight." (period is sentence punctuation).
        // LLM emitted "8." (terminal period attached — systematic in v20 few-shots).
        // cardinalCore must expose "8." as cardinal "8" so Case B reverts to "eight."
        let result = NumberRevert.apply(
            baseline: "no actually eight.",
            output: "no actually 8.",
            language: "en"
        ).text
        XCTAssertEqual(result, "no actually eight.",
            "Phase 36.1 CR-01: sentence-final digit '8.' must revert to baseline word 'eight.' with period preserved")
    }

    func testNumberRevert_sentenceFinal_digitToWord_revertsWithPeriod() {
        // Baseline has sentence-final digit "8." (period is sentence punctuation).
        // LLM re-spelled it to "eight." — Case C must revert to digit "8." with period.
        let result = NumberRevert.apply(
            baseline: "no actually 8.",
            output: "no actually eight.",
            language: "en"
        ).text
        XCTAssertEqual(result, "no actually 8.",
            "Phase 36.1 CR-01: sentence-final word 'eight.' must revert to baseline digit '8.' with period preserved")
    }

    // MARK: - German N. token (260930-s1b)

    /// 260930-s1b, logged record ts 2026-09-29T17:30:15.605Z. A German baseline `3.` is
    /// both a sentence-final cardinal and an ordinal key, so it lives in the ordinal
    /// budget. The LLM's `drei.` must revert to that exact baseline token.
    func testNumberRevert_de_sentenceFinalCardinalWord_revertsToBaselineDigitWithPeriod() {
        let result = NumberRevert.apply(
            baseline: "Der Faktor lautet hoch 3.",
            output: "Der Faktor lautet hoch drei.",
            language: "de"
        ).text
        XCTAssertEqual(result, "Der Faktor lautet hoch 3.")
    }

    /// 260930-s1b: a true ordinal re-spelled as an ordinal word reverts to the baseline `N.`.
    func testNumberRevert_de_ordinalWord_revertsToBaselineOrdinalDigit() {
        let result = NumberRevert.apply(
            baseline: "Wir sehen uns am 3. Oktober im Büro.",
            output: "Wir sehen uns am dritten Oktober im Büro.",
            language: "de"
        ).text
        XCTAssertEqual(result, "Wir sehen uns am 3. Oktober im Büro.")
    }

    /// 260930-s1b: the cardinal `3` and the ordinal `3.` of the same value keep separate budgets.
    func testNumberRevert_de_cardinalAndOrdinalOfSameValue_useSeparateBudgets() {
        let result = NumberRevert.apply(
            baseline: "Es kommen 3 Gäste am 3. Oktober zum Essen.",
            output: "Es kommen drei Gäste am dritten Oktober zum Essen.",
            language: "de"
        ).text
        XCTAssertEqual(result, "Es kommen 3 Gäste am 3. Oktober zum Essen.")
    }

    /// 260930-s1b: a bare cardinal word for a baseline ordinal is ambiguous (`3` would drop
    /// the ordinal marker), so NumberRevert leaves it and FactPreservationGuard restores the baseline.
    func testNumberRevert_de_bareCardinalWordForOrdinalDigit_isLeftForFactPreservationGuard() {
        let result = NumberRevert.apply(
            baseline: "Wir sehen uns am 3. Oktober im Büro.",
            output: "Wir sehen uns am drei Oktober im Büro.",
            language: "de"
        ).text
        XCTAssertEqual(result, "Wir sehen uns am drei Oktober im Büro.")
    }

    /// 260930-s1b: a re-spelling that lost its own period is left alone (emitting `3.` would print `3.,`).
    func testNumberRevert_de_cardinalWordThatLostItsPeriod_isLeftForFactPreservationGuard() {
        let result = NumberRevert.apply(
            baseline: "Der Faktor lautet hoch 3.",
            output: "Der Faktor lautet hoch drei, und mehr.",
            language: "de"
        ).text
        XCTAssertEqual(result, "Der Faktor lautet hoch drei, und mehr.")
    }
}
