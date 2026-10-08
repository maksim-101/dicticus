import XCTest
@testable import Dicticus

/// Quick task 261008-gb4: five EditGuard defects that shipped harm to the cursor.
///
/// - F1 mood lock: a statement opening with an interjection and a comma
///   (`Ja,` / `Yes,`) shipped with question word order, because the lock read
///   only the sentence's first word.
/// - F2 punctuation seam: a rejected comma or period move left the seam where
///   the baseline's mark was deleted with no mark at all.
/// - F3 quotes: the mixed-provenance punctuation collapse dropped a restored
///   closing quotation mark next to a kept comma or period.
/// - F5 dictionary casing: step 1's casing-only accept ran before the
///   dictionary check, so a dictionary term shipped in capitals.
/// - NWR non-word repair: a word the platform spell checker lacks but the
///   bundled EN+DE word list holds was "repaired" into another word.
///
/// `_RED` in a name means the test fails at the start commit; every other test
/// is a pin that must hold before and after the change. The name prefix maps a
/// test to its sub-fix (testF1_, testF2_, testF3_, testF5_, testNWR_). Each
/// sub-fix has a mutation that turns its tests red: MF1 (empty interjection
/// set), MF2 (drop the `applySeamMarkCoupling` call), MF2r (drop its recase
/// flip), MF3 (drop the quote clause of the survivors filter), MF3b (drop the
/// even-count check), MF5 (drop the
/// `dictProtectedCasing` arm), MF5a (reject first-letter capitals too), MF5b (let the
/// rejection trigger atomic-group coupling), MNWRa (drop the `isListedWord` conjunct),
/// MNWRb (make `PlatformSpellLexicon.isListedWord` return false).
///
/// Every fixture is an invented sentence about a bicycle repair workshop.
@MainActor
final class EditGuardHarmFixesTests: XCTestCase {

    private struct ListedLexicon: SpellLexicon {
        let unknown: Set<String>
        let listed: Set<String>

        func isKnownWord(_ text: String, language: String) -> Bool {
            !unknown.contains(text.lowercased())
        }

        func isListedWord(_ text: String, language: String) -> Bool {
            listed.contains(text.lowercased())
        }
    }

    // MARK: - Helpers

    private func run(
        _ lang: String, _ baseline: String, _ llm: String, dictProtected: Set<String> = [],
        lexicon: any SpellLexicon = TestSpellLexicon.allKnown
    ) -> EditGuard.GuardResult {
        let r = EditGuard.apply(
            rulesCleaned: baseline, llmOutput: llm, language: lang, dictProtected: dictProtected, lexicon: lexicon)
        let v = EditGuardMergeAtomicityTests.neitherSourceViolations(output: r.text, sourceA: baseline, sourceB: llm)
        XCTAssertTrue(v.tier1.isEmpty, "tier-1 neither-source violation(s) \(v.tier1) in: \(r.text)")
        return r
    }

    private func hasReject(_ r: EditGuard.GuardResult, _ cls: String) -> Bool {
        r.edits.contains { $0.rejectClass == cls }
    }

    // MARK: - F1: mood lock reads past a leading interjection and its comma

    func testF1_germanStatementAfterJaKeepsVerbSecond_RED() {
        let baseline = "Ja, wir müssen den Schlauch heute noch flicken."
        let r = run("de", baseline, "Ja, müssen wir den Schlauch heute noch flicken.")
        XCTAssertEqual(r.text, baseline)
        XCTAssertTrue(hasReject(r, "moodLockSentenceInitialVerb"), "\(r.edits)")
    }

    func testF1_englishStatementAfterYesKeepsOrder_RED() {
        let baseline = "Yes, we can patch the tube before the ride starts."
        let r = run("en", baseline, "Yes, can we patch the tube before the ride starts.")
        XCTAssertEqual(r.text, baseline)
        XCTAssertTrue(hasReject(r, "moodLockSentenceInitialVerb"), "\(r.edits)")
    }

    /// The LLM also deletes the comma after the interjection: the rebuilt
    /// stream has no comma to skip, so the skip is keyed to the baseline.
    func testF1_llmDroppedCommaStillLocks_RED() {
        let r = run("de", "Ja, wir müssen den Schlauch heute noch flicken.", "Ja müssen wir den Schlauch heute noch flicken.")
        XCTAssertTrue(hasReject(r, "moodLockSentenceInitialVerb"), "\(r.edits)")
        XCTAssertTrue(r.text.contains("wir müssen den Schlauch"), "verb order restored: \(r.text)")
    }

    func testF1_dictatedQuestionAfterJaUnchanged() {
        let llm = "Ja, müssen wir den Schlauch heute noch flicken?"
        let r = run("de", "Ja, müssen wir den Schlauch heute noch flicken.", llm)
        XCTAssertEqual(r.text, llm)
        XCTAssertFalse(hasReject(r, "moodLockSentenceInitialVerb"), "\(r.edits)")
    }

    // MARK: - F2: a rejected punctuation move keeps the mark at its seam

    func testF2_rejectedCommaMoveKeepsSeamPeriod_RED() {
        let r = run(
            "en",
            "Replace the spoke on wheel 4. Next oil the chain, then adjust the saddle.",
            "Replace the spoke on wheel 4, next oil the chain; then adjust the saddle.")
        XCTAssertEqual(r.text, "Replace the spoke on wheel 4. Next oil the chain; then adjust the saddle.")
        XCTAssertTrue(hasReject(r, "punctuationSeamCoupling"), "\(r.edits)")
        // `applyAtomicGroupCoupling` would revert the recase anyway; the flip keeps its attribution (MF2r).
        XCTAssertTrue(
            r.edits.contains { $0.from == "Next" && $0.to == "next" && $0.rejectClass == "punctuationSeamCoupling" },
            "\(r.edits)")
    }

    func testF2_rejectedPeriodMoveKeepsSeamComma_RED() {
        let r = run(
            "en",
            "The frame was clean, a brief test lap followed and the brake, held fine for everyone today.",
            "The frame was clean. A brief test lap followed and the brake held fine for everyone today")
        XCTAssertEqual(r.text, "The frame was clean, a brief test lap followed and the brake held fine for everyone today.")
        XCTAssertTrue(hasReject(r, "punctuationSeamCoupling"), "\(r.edits)")
        XCTAssertTrue(
            r.edits.contains { $0.from == "a" && $0.to == "A" && $0.rejectClass == "punctuationSeamCoupling" },
            "\(r.edits)")
    }

    func testF2_plainPeriodToCommaSubstituteUnchanged() {
        let llm = "The chain is dry, we need fresh oil before noon."
        let r = run("en", "The chain is dry. We need fresh oil before noon.", llm)
        XCTAssertEqual(r.text, llm)
        XCTAssertFalse(hasReject(r, "punctuationSeamCoupling"), "\(r.edits)")
    }

    // MARK: - F3: a restored closing quotation mark survives next to a kept mark

    func testF3_restoredClosingQuoteSurvivesBeforeKeptComma_RED() {
        let baseline = "Die Kundin nannte es \"Schlauch\", und dann ging sie heim."
        let r = run("de", baseline, "Die Kundin nannte es Schlauch, und dann ging sie schnell heim.")
        XCTAssertEqual(r.text, baseline)
    }

    func testF3_restoredClosingQuoteSurvivesBeforeKeptPeriod_RED() {
        let baseline = "She named the bent part \"derailleur\"."
        let r = run("en", baseline, "She named the very bent part derailleur.")
        XCTAssertEqual(r.text, baseline)
    }

    /// The opening mark's delete is accepted while the closing mark's delete is
    /// reverted with its sentence: restoring only the closing quote would ship
    /// an orphan, so the old collapse (which drops it) stands. Mutation MF3b.
    func testF3_orphanClosingQuoteStaysDropped() {
        let r = run(
            "en",
            "The mechanic said, \"The rim is bent, the tire is flat.\" Fixing the rim takes time because the shop is busy and as well the part is late.",
            "The mechanic said, The rim is bent, the tire is flat. Fixing the rim takes long because the shop is busy, and the part is very late.")
        XCTAssertEqual(r.text.filter { $0 == "\"" }.count % 2, 0, "unbalanced quotes in: \(r.text)")
    }

    // MARK: - F5: a dictionary term keeps its exact casing

    func testF5_dictionaryTermAllCapsReverted_RED() {
        let baseline = "We cleaned the chain with zorbex before the ride today."
        let r = run("en", baseline, "We cleaned the chain with ZORBEX before the ride today.", dictProtected: ["zorbex"])
        XCTAssertEqual(r.text, baseline)
        XCTAssertTrue(hasReject(r, "dictProtectedCasing"), "\(r.edits)")
    }

    /// 261008-gb4 follow-up: a plain first-letter capital of the dictionary
    /// spelling is not rejected (a German noun, a sentence start). Mutation MF5a.
    func testF5_dictionaryTermFirstLetterCapitalAccepted_RED() {
        let llm = "We cleaned the chain with Zorbex before the ride today."
        let r = run("en", "We cleaned the chain with zorbex before the ride today.", llm, dictProtected: ["zorbex"])
        XCTAssertEqual(r.text, llm)
        XCTAssertFalse(hasReject(r, "dictProtectedCasing"), "\(r.edits)")
    }

    func testF5_dictionaryTermMixedCaseReverted() {
        let baseline = "We cleaned the chain with zorbex before the ride today."
        let r = run("en", baseline, "We cleaned the chain with ZorBex before the ride today.", dictProtected: ["zorbex"])
        XCTAssertEqual(r.text, baseline)
        XCTAssertTrue(hasReject(r, "dictProtectedCasing"), "\(r.edits)")
    }

    /// 261008-gb4 follow-up: the casing rejection reverts only the casing
    /// token; the article inserted beside it, within one edit cluster,
    /// still ships. Mutation MF5b.
    func testF5_dictCasingRejectionKeepsAdjacentInsert_RED() {
        let r = run(
            "en", "Next regarding zorbex lubricant the shop keeps two spare tins.",
            "Next, regarding the ZORBEX lubricant, the shop keeps two spare tins.", dictProtected: ["zorbex"])
        XCTAssertEqual(r.text, "Next, regarding the zorbex lubricant, the shop keeps two spare tins.")
        XCTAssertTrue(hasReject(r, "dictProtectedCasing"), "\(r.edits)")
    }

    /// The new class is not a sentence-revert trigger: the comma ships.
    func testF5_dictCasingRejectionKeepsSentenceComma_RED() {
        let r = run(
            "en", "We cleaned the chain with zorbex before the ride today and the brakes after.",
            "We cleaned the chain with ZORBEX before the ride today, and the brakes after.", dictProtected: ["zorbex"])
        XCTAssertEqual(r.text, "We cleaned the chain with zorbex before the ride today, and the brakes after.")
    }

    func testF5_nonDictionaryCasingStillAccepted() {
        let llm = "We cleaned the chain with ZORBEX before the ride today."
        let r = run("en", "We cleaned the chain with zorbex before the ride today.", llm)
        XCTAssertEqual(r.text, llm)
    }

    // MARK: - NWR: a bundled-list word is not a non-word

    func testNWR_listedSourceIsNotRepaired_RED() {
        let baseline = "The wheel has one spokke missing from the rear today."
        let lex = ListedLexicon(unknown: ["spokke"], listed: ["spokke"])
        let r = run("en", baseline, "The wheel has one spoke missing from the rear today.", lexicon: lex)
        XCTAssertEqual(r.text, baseline)
        XCTAssertFalse(r.edits.contains { $0.acceptClass == "nonWordRepair" }, "\(r.edits)")
    }

    func testNWR_unlistedNonWordStillRepaired() {
        let llm = "The wheel has one spoke missing from the rear today."
        let lex = ListedLexicon(unknown: ["spokke"], listed: [])
        let r = run("en", "The wheel has one spokke missing from the rear today.", llm, lexicon: lex)
        XCTAssertEqual(r.text, llm)
        XCTAssertTrue(r.edits.contains { $0.acceptClass == "nonWordRepair" }, "\(r.edits)")
    }

    func testNWR_platformLexiconListsBundledWords() {
        XCTAssertTrue(PlatformSpellLexicon.shared.isListedWord("bicycle", language: "en"))
        XCTAssertTrue(PlatformSpellLexicon.shared.isListedWord("Fahrrad", language: "de"))
        XCTAssertFalse(PlatformSpellLexicon.shared.isListedWord("zxqvbl", language: "en"))
    }
}
