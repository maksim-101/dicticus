import XCTest
@testable import Dicticus

/// Quick task 260825-q1w (D-C in the plan): scopes the mood-lock revert
/// (`RejectionClass.moodLockSentenceInitialVerb`) to violations actually
/// CAUSED BY A REORDER. `EditGuard.rebuild`'s mood-lock loop compares
/// `firstWordToken(baseline, sentenceIndex:)` against
/// `firstWordToken(tokens, sentenceIndex:)` by SENTENCE INDEX — a
/// candidate-side sentence SPLIT shifts every later candidate sentence
/// index by one, so a pure split (no reordering) can silently compare two
/// different sentences and misfire as a mood flip (landmine 5, the
/// 2026-08-23 false positive).
///
/// POSITIVE (RED before the guard exists, GREEN after) is the real, live
/// record. NEGATIVES pin the German/mood-protection proof — including a new
/// adversarial split+reorder case, per
/// `feedback_spike_corpus_adversarial_breadth`: a split must not give a
/// genuine verb-fronting reorder a free pass.
@MainActor
final class EditGuardMoodLockSplitTests: XCTestCase {

    private func guardOut(_ baseline: String, _ llm: String, _ lang: String = "en") -> EditGuard.GuardResult {
        EditGuard.apply(rulesCleaned: baseline, llmOutput: llm, language: lang, lexicon: TestSpellLexicon.allKnown)
    }

    private func assertMoodLockFired(_ result: EditGuard.GuardResult, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(result.edits.contains { $0.rejectClass == "moodLockSentenceInitialVerb" },
            "expected a moodLockSentenceInitialVerb rejection — got: \(result.edits)", file: file, line: line)
    }

    private func assertMoodLockDidNotFire(_ result: EditGuard.GuardResult, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(result.edits.contains { $0.rejectClass == "moodLockSentenceInitialVerb" },
            "expected no moodLockSentenceInitialVerb rejection — got: \(result.edits)", file: file, line: line)
    }

    // MARK: - Positive: live cleanup-2026-08-23.jsonl #11 — a no-reorder split

    func testPositive_noReorderSplitSurvivesMoodLock_en() {
        let baseline = "Because I suppose this is more uncertain in practice right because outsourcing upward is about time budget does the junior lead reviewer Have to do all the lifting? No."
        let candidate = "Because I suppose this is more uncertain in practice, right, because outsourcing upward is about time budget. Does the junior lead reviewer have to do all the lifting? No."
        let result = guardOut(baseline, candidate)
        XCTAssertTrue(result.text.contains("time budget. Does the junior lead reviewer have to do all the lifting?"),
            "expected the split + both casing fixes to survive — got: \(result.text)")
        assertMoodLockDidNotFire(result)
    }

    // MARK: - Negatives: verb-fronting reorders still reject

    /// fx-mov-func-en-moodlock pair.
    ///
    /// UPDATED (Phase 49.6, D-01, deviation — see 49.6-02-SUMMARY.md
    /// "Deviations"): this single-sentence utterance ALSO carries an
    /// independent `contentWordDeletion` trigger ("do" deleted), so
    /// `applySentenceCoupledRevert` — which runs immediately after the
    /// FIRST `applyAtomicGroupCoupling` call, before the mood-lock loop
    /// ever executes — already reverts the fronting move + "Can"
    /// substitute as `sentenceCoupledRevert`. The mood-lock loop then finds
    /// nothing left to violate (the rebuilt first word is already back to
    /// baseline order) and never fires its own `moodLockSentenceInitialVerb`
    /// label. The load-bearing property this test guards — a genuine
    /// verb-fronting reorder reverts to baseline — still holds
    /// (`XCTAssertEqual(result.text, baseline)` below); only the SPECIFIC
    /// rejection class differs.
    func testNegative_verbFrontingEn() {
        let baseline = "You can send the patches and then I'm asking where do we stand."
        let candidate = "Can you send the patches and then I'm asking where we stand."
        let result = guardOut(baseline, candidate)
        XCTAssertEqual(result.text, baseline)
        XCTAssertTrue(
            result.edits.contains { $0.rejectClass == "moodLockSentenceInitialVerb" || $0.rejectClass == "sentenceCoupledRevert" },
            "expected the reorder to revert via moodLockSentenceInitialVerb or (49.6) sentenceCoupledRevert — got: \(result.edits)"
        )
    }

    /// fx-mov-func-de-moodlock pair.
    func testNegative_verbFrontingDe() {
        let baseline = "Er kommt morgen."
        let candidate = "Kommt er morgen?"
        let result = guardOut(baseline, candidate, "de")
        XCTAssertEqual(result.text, baseline)
        assertMoodLockFired(result)
    }

    /// New adversarial negative: a genuine verb-fronting reorder coexists
    /// with an UNRELATED, benign sentence split elsewhere in the same
    /// utterance. The split must not buy the reorder a free pass — "kommt"
    /// lost its baseline left-neighbour "er", so the first sentence is a
    /// genuine fronting, independent of whatever splitting happens later.
    /// The later split (no reorder, no mood-mark change) is legitimately
    /// accepted on its own merits — see the positive fixture above — so
    /// only the reordered sentence's reversion is asserted here.
    func testNegative_splitPlusReorderStillRejectsDe() {
        let baseline = "Er kommt morgen. Das Update ist fertig und wir sind bereit."
        let candidate = "Kommt er morgen. Das Update ist fertig. Und wir sind bereit."
        let result = guardOut(baseline, candidate, "de")
        XCTAssertTrue(result.text.hasPrefix("Er kommt morgen."),
            "expected the genuine verb-fronting reorder to revert to baseline order — got: \(result.text)")
        assertMoodLockFired(result)
    }
}

/// Quick task 261030-orz (spike 021): a German word-order move that puts the
/// finite verb in front of the subject directly after a sentence-opening
/// particle (`Also ich habe` -> `Also habe ich`) turns "well, I have" into
/// "therefore I have", and `classifyMove` accepted it as `wordOrderRepair`.
/// EditGuard now rejects those moves as `particleInversion`.
///
/// `_RED` in a name means the test fails at the start commit; every other test
/// is a pin that must hold before and after the change. The mutation that
/// turns every RED test red is an empty `particleInversionLeaders` set.
///
/// The leader list is the owner's 2026-10-30 list minus `dann` and `so`: as
/// sentence-initial adverbs they require verb-second order in standard
/// German, so blocking them would reject correct repairs.
///
/// Every fixture is an invented sentence about an allotment garden; spike
/// items are cited by number only.
@MainActor
final class EditGuardParticleInversionTests: XCTestCase {

    private func run(_ lang: String, _ baseline: String, _ llm: String) -> EditGuard.GuardResult {
        let r = EditGuard.apply(rulesCleaned: baseline, llmOutput: llm, language: lang, lexicon: TestSpellLexicon.allKnown)
        let v = EditGuardMergeAtomicityTests.neitherSourceViolations(output: r.text, sourceA: baseline, sourceB: llm)
        XCTAssertTrue(v.tier1.isEmpty, "tier-1 neither-source violation(s) \(v.tier1) in: \(r.text)")
        return r
    }

    private func hasReject(_ r: EditGuard.GuardResult, _ cls: String) -> Bool {
        r.edits.contains { $0.rejectClass == cls }
    }

    private func assertInversionRejected(
        _ baseline: String, _ llm: String, expected: String? = nil, message: String = "",
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let r = run("de", baseline, llm)
        XCTAssertEqual(r.text, expected ?? baseline, message, file: file, line: line)
        XCTAssertTrue(hasReject(r, "particleInversion"), "\(message) \(r.edits)", file: file, line: line)
        XCTAssertFalse(hasReject(r, "moodLockSentenceInitialVerb"), "\(message) \(r.edits)", file: file, line: line)
    }

    // MARK: - RED: the nine spike-021 shapes

    func testR1_pronounSubject_RED() {
        assertInversionRejected(
            "Also ich habe die Tomaten heute früh gegossen.",
            "Also habe ich die Tomaten heute früh gegossen.")
    }

    func testR2_demonstrativeSubject_RED() {
        assertInversionRejected(
            "Also das war die zweite Ernte von den Bohnen.",
            "Also war das die zweite Ernte von den Bohnen.")
    }

    func testR3_oneTokenSubject_RED() {
        assertInversionRejected(
            "Also Regen ist für morgen angekündigt.",
            "Also ist Regen für morgen angekündigt.")
    }

    func testR4_fullVerbOverThreeWordSubject_RED() {
        assertInversionRejected(
            "Also die neue Regentonne scheint dicht zu sein, auch wenn sie gestern noch tropfte.",
            "Also scheint die neue Regentonne dicht zu sein, auch wenn sie gestern noch tropfte.")
    }

    func testR5_chainedParticlesWithComma_RED() {
        assertInversionRejected(
            "Ja, also die vorderen Beete sollst du vor dem Frost abdecken.",
            "Ja, also sollst du die vorderen Beete vor dem Frost abdecken.")
    }

    func testR6_secondSentenceKeepsFirstSentenceRepair_RED() {
        assertInversionRejected(
            "Der Zaun braucht ein neuen Anstrich. Also wir wollen heute nicht alles auf einmal streichen.",
            "Der Zaun braucht einen neuen Anstrich. Also wollen wir heute nicht alles auf einmal streichen.",
            expected: "Der Zaun braucht einen neuen Anstrich. Also wir wollen heute nicht alles auf einmal streichen.")
    }

    func testR7_doch_RED() {
        assertInversionRejected(
            "Der Schlauch schien geflickt. Doch ich bin noch einmal zum Wasserhahn gegangen.",
            "Der Schlauch schien geflickt. Doch bin ich noch einmal zum Wasserhahn gegangen.")
    }

    func testR8_passiveAuxiliary_RED() {
        assertInversionRejected(
            "Also das Saatgut wird erst am Freitag geliefert.",
            "Also wird das Saatgut erst am Freitag geliefert.")
    }

    func testR9_afterAnotherSentence_RED() {
        assertInversionRejected(
            "Die Pumpe läuft nicht mehr. Also ich kann heute kein Beet mehr wässern.",
            "Die Pumpe läuft nicht mehr. Also kann ich heute kein Beet mehr wässern.")
    }

    /// `meine` tests finite by suspicion in `FiniteVerbCues`; the rule must not
    /// require a non-finite subject word.
    func testR10_determinerSubjectEndingInE_RED() {
        assertInversionRejected(
            "Also meine Erdbeeren sind dieses Jahr früh dran.",
            "Also sind meine Erdbeeren dieses Jahr früh dran.")
    }

    /// Spike item 19 shape: a subject token holding a digit is not tokenized as
    /// a word, and the pass must still see it as the dictated word behind the
    /// particle.
    func testR12_digitBearingSubject_RED() {
        assertInversionRejected(
            "Also Beet3 ist wieder frei für die Setzlinge.",
            "Also ist Beet3 wieder frei für die Setzlinge.")
    }

    /// Spike item 99 shape: the LLM splits an earlier sentence, so its
    /// sentence indices run one ahead of the dictation's from there on. The
    /// pass pairs sentences by content, not by index.
    func testR13_earlierSentenceSplitShiftsIndices_RED() {
        let baseline = "Ich habe gestern die Beete gegossen und dann kam der Regen. Also ich kann heute nicht mehr jäten."
        let r = run("de", baseline, "Ich habe gestern die Beete gegossen. Dann kam der Regen. Also kann ich heute nicht mehr jäten.")
        XCTAssertTrue(hasReject(r, "particleInversion"), "\(r.edits)")
        XCTAssertFalse(r.text.contains("Also kann ich"), r.text)
        XCTAssertTrue(r.text.contains("Also ich kann heute nicht mehr jäten."), r.text)
    }

    // MARK: - RED: each listed particle

    func testR11_also_RED() { particle("Also") }
    func testR11_ja_RED() { particle("Ja") }
    func testR11_doch_RED() { particle("Doch") }
    func testR11_und_RED() { particle("Und") }
    func testR11_aber_RED() { particle("Aber") }

    private func particle(_ p: String, file: StaticString = #filePath, line: UInt = #line) {
        assertInversionRejected(
            "\(p) ich habe den Rasen gemäht.",
            "\(p) habe ich den Rasen gemäht.",
            message: "particle \(p):", file: file, line: line)
    }

    // MARK: - Pins

    /// A comma the LLM inserts after the particle is not a word-order change.
    func testP1_commaAfterParticleShips() {
        let llm = "Also, das war die zweite Ernte von den Bohnen."
        let r = run("de", "Also das war die zweite Ernte von den Bohnen.", llm)
        XCTAssertEqual(r.text, llm)
        XCTAssertFalse(hasReject(r, "particleInversion"), "\(r.edits)")
    }

    /// OD-3: a verb-second repair with no leading particle stays accepted.
    func testP2_noParticleRepairShips() {
        let llm = "Heute habe ich die Beete gegossen."
        let r = run("de", "Heute ich habe die Beete gegossen.", llm)
        XCTAssertEqual(r.text, llm)
        XCTAssertFalse(hasReject(r, "particleInversion"), "\(r.edits)")
        XCTAssertTrue(r.edits.contains { $0.acceptClass == "wordOrderRepair" }, "\(r.edits)")
    }

    /// The word after the particle stays in place, so the pass does not fire.
    func testP3_wordAfterParticleUnchangedShips() {
        let llm = "Aber im Herbst ernten wir die Kürbisse."
        let r = run("de", "Aber im Herbst wir ernten die Kürbisse.", llm)
        XCTAssertEqual(r.text, llm)
        XCTAssertFalse(hasReject(r, "particleInversion"), "\(r.edits)")
        XCTAssertTrue(r.edits.contains { $0.acceptClass == "wordOrderRepair" }, "\(r.edits)")
    }

    func testP4_englishIsUntouched() {
        let r = run("en", "So I have watered the beds.", "So have I watered the beds.")
        XCTAssertFalse(hasReject(r, "particleInversion"), "\(r.edits)")
    }

    /// An accepted inflection repair right after the particle puts a word the
    /// dictation does not hold in that slot; the pass fires only on a dictated
    /// word moved forward.
    func testP5_inflectionRepairAfterParticleShips() {
        let llm = "Also eine Frage habe ich noch zum Kompost."
        let r = run("de", "Also ein Frage habe ich noch zum Kompost.", llm)
        XCTAssertEqual(r.text, llm)
        XCTAssertFalse(hasReject(r, "particleInversion"), "\(r.edits)")
    }

    /// `dann` and `so` are not leaders: after them standard German requires the
    /// verb in second position, so this repair is correct and ships.
    func testP6_dannIsNotALeader() {
        let llm = "Dann gehe ich morgen zum Baumarkt."
        let r = run("de", "Dann ich gehe morgen zum Baumarkt.", llm)
        XCTAssertFalse(hasReject(r, "particleInversion"), "\(r.edits)")
        XCTAssertEqual(r.text, llm)
    }

    func testP7_soIsNotALeader() {
        let llm = "So habe ich die Beete angelegt."
        let r = run("de", "So ich habe die Beete angelegt.", llm)
        XCTAssertFalse(hasReject(r, "particleInversion"), "\(r.edits)")
        XCTAssertEqual(r.text, llm)
    }
}
