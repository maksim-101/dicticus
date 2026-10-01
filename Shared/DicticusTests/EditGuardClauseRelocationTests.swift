import XCTest
@testable import Dicticus

/// Quick task 260930-s19: regression net for the EditGuard clause-relocation
/// bound. Per `.planning/debug/audit-2026-09-30/SYNTHESIS.md` item 1 and
/// `B2-meaning-structure.md`, the live record `2026-09-29T13:01:45.693Z`
/// (cited by ts only, no dictation text quoted) shows the LLM deleting the
/// period between two raw sentences and moving the main clause of the second
/// behind its subordinate clause; the gate accepted every word move as
/// `wordOrderRepair`, the period delete as `punctuationOrCasing` and two
/// inserted commas, and pasted a sentence that reads as nonsense. Fixed by
/// `EditGuard.clauseRelocationIndices` / `RejectionClass.clauseRelocation`:
/// a run of two or more word moves that is baseline-contiguous and either
/// spans a clause-boundary mark (A) or crosses a raw sentence-terminal mark
/// (B) is rejected, together with the sentence break the LLM removed to make
/// room for it.
///
/// Every fixture below is INVENTED: different topic, ordinary dictionary
/// words, no personal facts. `s19_privacy_check.py` in the quick task
/// directory verifies no 5-word shingle overlap with the frozen corpus. P1's
/// edit stream (a period delete, seven baseline-contiguous moves spanning
/// a kept comma, two comma inserts) has the same shape as the logged
/// `post_gate.edits` of the live record.
///
/// P1-P5 are RED before the fix (actual = the LLM candidate, proving the
/// fixture carries the defect shape per 49.6 D-12); N1-N6 are GREEN both
/// before and after and each pins one clause of the rule.
@MainActor
final class EditGuardClauseRelocationTests: XCTestCase {

    private func guardResult(_ baseline: String, _ llm: String, _ lang: String = "en") -> EditGuard.GuardResult {
        EditGuard.apply(rulesCleaned: baseline, llmOutput: llm, language: lang, lexicon: TestSpellLexicon.allKnown)
    }

    private func assertNeitherSource(_ out: String, _ baseline: String, _ llm: String, file: StaticString = #filePath, line: UInt = #line) {
        let v = EditGuardMergeAtomicityTests.neitherSourceViolations(output: out, sourceA: baseline, sourceB: llm)
        XCTAssertTrue(v.tier1.isEmpty, "tier-1 neither-source violation(s) \(v.tier1) in: \(out)", file: file, line: line)
    }

    private func moves(_ result: EditGuard.GuardResult) -> [EditGuard.ClassifiedEdit] {
        result.edits.filter { $0.kind == "move" }
    }

    // MARK: - P1: German twin of the live shape (criterion A plus the coupled period)

    /// Raw sentence 2 is carried, in two halves around a KEPT comma, behind
    /// its `damit` clause; the LLM also deletes the period and inserts two
    /// commas. Every move, the period delete and both comma inserts must be
    /// rejected and the output must be the raw text.
    func testP1_germanClauseRelocationAcrossKeptCommaAndMergedSentence() {
        let baseline = "Der Kurs ist freiwillig und kein Ersatz für die Prüfung, sondern eine verlässliche, allen Teilnehmern bekannte Vorbereitung. Vielleicht hilft sie dir, statt zu schaden, damit du den Stoff später ohne Hilfe verstehen kannst."
        let llm = "Der Kurs ist freiwillig und kein Ersatz für die Prüfung, sondern eine verlässliche, allen Teilnehmern bekannte Vorbereitung, vielleicht, damit du den Stoff später ohne Hilfe verstehen kannst, hilft sie dir, statt zu schaden."
        let result = guardResult(baseline, llm, "de")
        XCTAssertEqual(result.text, baseline, "edits: \(result.edits)")
        let mv = moves(result)
        XCTAssertEqual(mv.count, 7, "edits: \(result.edits)")
        XCTAssertTrue(mv.allSatisfy { !$0.accepted && $0.rejectClass == "clauseRelocation" }, "edits: \(result.edits)")
        guard let period = result.edits.first(where: { $0.kind == "delete" && $0.from == "." }) else {
            return XCTFail("no delete edit for '.'")
        }
        XCTAssertFalse(period.accepted)
        XCTAssertEqual(period.rejectClass, "clauseRelocation")
        XCTAssertTrue(result.edits.filter { $0.kind == "insert" && $0.to == "," }.allSatisfy { !$0.accepted }, "edits: \(result.edits)")
        assertNeitherSource(result.text, baseline, llm)
    }

    // MARK: - P2: criterion A inside one raw sentence; the far edit is reverted by SCR only

    /// One raw sentence. A nine-word run spans a kept comma and lands at the
    /// end; the LLM also capitalises the first word, four keeps away from the
    /// first run member and from every member destination, so no keep-bounded
    /// cluster links the casing fix to the run. Only the sentence-coupled
    /// revert (`clauseRelocation` is a trigger) can reject it.
    func testP2_criterionAWithinOneSentenceFarEditRevertedByScr() {
        let baseline = "we finished the plan early maybe this route saves fuel, instead of wasting time, so that drivers can learn the material later without any outside help from the team"
        let llm = "We finished the plan early, maybe, so that drivers can learn the material later without any outside help from the team, this route saves fuel, instead of wasting time"
        let result = guardResult(baseline, llm)
        XCTAssertEqual(result.text, baseline, "edits: \(result.edits)")
        XCTAssertFalse(moves(result).isEmpty)
        XCTAssertTrue(moves(result).allSatisfy { !$0.accepted && $0.rejectClass == "clauseRelocation" }, "edits: \(result.edits)")
        guard let casing = result.edits.first(where: { $0.kind == "substitute" && $0.from == "we" && $0.to == "We" }) else {
            return XCTFail("no casing substitute for 'we'")
        }
        XCTAssertFalse(casing.accepted)
        XCTAssertEqual(casing.rejectClass, "sentenceCoupledRevert")
        assertNeitherSource(result.text, baseline, llm)
    }

    // MARK: - P3: criterion B alone (no punctuation between run members, nothing deleted)

    func testP3_criterionBRunCrossesKeptPeriod() {
        let baseline = "We tested the new build. The results look good on every device."
        let llm = "We tested the new build on every device. The results look good."
        let result = guardResult(baseline, llm)
        XCTAssertEqual(result.text, baseline, "edits: \(result.edits)")
        let mv = moves(result)
        XCTAssertEqual(mv.map { $0.from ?? "" }, ["on", "every", "device"], "edits: \(result.edits)")
        XCTAssertTrue(mv.allSatisfy { !$0.accepted && $0.rejectClass == "clauseRelocation" }, "edits: \(result.edits)")
        XCTAssertFalse(result.edits.contains { $0.kind == "delete" }, "edits: \(result.edits)")
        assertNeitherSource(result.text, baseline, llm)
    }

    // MARK: - P4: criterion B with a merge and no interior punctuation

    /// The period sits inside the run's jumped span, so its delete is coupled.
    func testP4_criterionBWithMergedPeriodInsideJumpedSpan() {
        let baseline = "We tested the new build. The results look good on every device."
        let llm = "We tested the new build on every device the results look good."
        let result = guardResult(baseline, llm)
        XCTAssertEqual(result.text, baseline, "edits: \(result.edits)")
        guard let period = result.edits.first(where: { $0.kind == "delete" && $0.from == "." }) else {
            return XCTFail("no delete edit for '.'")
        }
        XCTAssertFalse(period.accepted)
        XCTAssertEqual(period.rejectClass, "clauseRelocation")
        XCTAssertTrue(moves(result).allSatisfy { !$0.accepted }, "edits: \(result.edits)")
        assertNeitherSource(result.text, baseline, llm)
    }

    // MARK: - P5: coupled period separated from the run by a kept word

    /// The second raw sentence opens with a name the LLM leaves untouched, so
    /// the deleted period sits alone between two keeps; atomic coupling would
    /// not flip it, only the explicit coupled-mark rule does.
    func testP5_coupledPeriodSeparatedFromRunByKeep() {
        let baseline = "Der Kurs ist freiwillig und kein Ersatz für die Prüfung, sondern eine verlässliche, allen Teilnehmern bekannte Vorbereitung. Maria hilft dir, statt zu schaden damit du den Stoff später ohne Hilfe verstehen kannst."
        let llm = "Der Kurs ist freiwillig und kein Ersatz für die Prüfung, sondern eine verlässliche, allen Teilnehmern bekannte Vorbereitung Maria, damit du den Stoff später ohne Hilfe verstehen kannst, hilft dir, statt zu schaden."
        let result = guardResult(baseline, llm, "de")
        XCTAssertEqual(result.text, baseline, "edits: \(result.edits)")
        guard let period = result.edits.first(where: { $0.kind == "delete" && $0.from == "." }) else {
            return XCTFail("no delete edit for '.'")
        }
        XCTAssertFalse(period.accepted)
        XCTAssertEqual(period.rejectClass, "clauseRelocation")
        assertNeitherSource(result.text, baseline, llm)
    }

    // MARK: - N1: single-word verb-final move stays accepted

    func testN1_singleWordVerbFinalMoveAccepted() {
        let baseline = "Ich weiss, dass er hat das Buch gestern gelesen."
        let llm = "Ich weiss, dass er das Buch gestern gelesen hat."
        let result = guardResult(baseline, llm, "de")
        XCTAssertEqual(result.text, llm, "edits: \(result.edits)")
        guard let hat = moves(result).first(where: { $0.from == "hat" }) else { return XCTFail("no move for 'hat'") }
        XCTAssertTrue(hat.accepted)
        XCTAssertEqual(hat.acceptClass, "wordOrderRepair")
        assertNeitherSource(result.text, baseline, llm)
    }

    // MARK: - N2: a lone move across a sentence boundary is never bounded

    func testN2_singleWordMoveAcrossKeptPeriodAccepted() {
        let baseline = "The crew finished the repair. They packed the tools afterwards."
        let llm = "The crew finished the repair afterwards. They packed the tools."
        let result = guardResult(baseline, llm)
        XCTAssertEqual(result.text, llm, "edits: \(result.edits)")
        guard let mv = moves(result).first(where: { $0.from == "afterwards" }) else { return XCTFail("no move for 'afterwards'") }
        XCTAssertTrue(mv.accepted)
        XCTAssertEqual(mv.acceptClass, "wordOrderRepair")
        assertNeitherSource(result.text, baseline, llm)
    }

    // MARK: - N3: multi-word move inside one clause, no punctuation

    func testN3_multiWordMoveWithinClauseAccepted() {
        let baseline = "we could quickly through the settings menu open a tab or restart it"
        let llm = "we could quickly open a tab through the settings menu or restart it"
        let result = guardResult(baseline, llm)
        XCTAssertEqual(result.text, llm, "edits: \(result.edits)")
        XCTAssertEqual(moves(result).map { $0.from ?? "" }, ["open", "a", "tab"], "edits: \(result.edits)")
        XCTAssertTrue(moves(result).allSatisfy { $0.accepted && $0.acceptClass == "wordOrderRepair" }, "edits: \(result.edits)")
        assertNeitherSource(result.text, baseline, llm)
    }

    // MARK: - N4: a merge alone never fires the bound

    /// The run moves inside its own raw sentence and the LLM deletes the
    /// period that ends that sentence (not a pause-split: the word before it
    /// is shorter than five characters). The period belongs to the run's own
    /// sentence, so no coupling is needed.
    func testN4_multiWordMoveWithOwnSentencePeriodMergeAccepted() {
        let baseline = "it showed me for this week many open tasks or I read the chart as such. according to the report."
        let llm = "it showed me many open tasks for this week, or I read the chart as such according to the report."
        let result = guardResult(baseline, llm)
        XCTAssertEqual(result.text, llm, "edits: \(result.edits)")
        XCTAssertEqual(moves(result).map { $0.from ?? "" }, ["for", "this", "week"], "edits: \(result.edits)")
        XCTAssertTrue(moves(result).allSatisfy { $0.accepted && $0.acceptClass == "wordOrderRepair" }, "edits: \(result.edits)")
        guard let period = result.edits.first(where: { $0.kind == "delete" && $0.from == "." }) else {
            return XCTFail("no delete edit for '.'")
        }
        XCTAssertTrue(period.accepted)
        XCTAssertEqual(period.acceptClass, "punctuationOrCasing")
        assertNeitherSource(result.text, baseline, llm)
    }

    // MARK: - N5: commas in a jumped span do not fire criterion A

    func testN5_parentheticalHopAccepted() {
        let baseline = "We know, obviously, the plan works."
        let llm = "Obviously, we know the plan works."
        let result = guardResult(baseline, llm)
        XCTAssertEqual(result.text, llm, "edits: \(result.edits)")
        XCTAssertEqual(moves(result).map { $0.from ?? "" }, ["We", "know"], "edits: \(result.edits)")
        XCTAssertTrue(moves(result).allSatisfy { $0.accepted && $0.acceptClass == "wordOrderRepair" }, "edits: \(result.edits)")
        assertNeitherSource(result.text, baseline, llm)
    }

    // MARK: - N6: a terminal mark with no word after it cannot be crossed

    /// A run moved to the end of a one-sentence dictation whose candidate
    /// drops the final period: its jumped span reaches the final period, but
    /// nothing follows it, so criterion B stays silent.
    func testN6_runMovedToUtteranceEndAccepted() {
        let baseline = "We reviewed on Friday the quarterly budget."
        let llm = "We reviewed the quarterly budget on Friday"
        let result = guardResult(baseline, llm)
        XCTAssertEqual(result.text, llm, "edits: \(result.edits)")
        XCTAssertEqual(moves(result).map { $0.from ?? "" }, ["on", "Friday"], "edits: \(result.edits)")
        XCTAssertTrue(moves(result).allSatisfy { $0.accepted && $0.acceptClass == "wordOrderRepair" }, "edits: \(result.edits)")
        assertNeitherSource(result.text, baseline, llm)
    }
}
