import XCTest
@testable import Dicticus

/// Quick task 260926-bbz: regression net for the utterance-final terminal
/// mark exemption. Per `.planning/debug/audit-2026-09-26/C-punctuation.md`,
/// 74 of 120 missing-final-mark records (09-12..09-26) are the LLM's
/// utterance-final `.`/`?`/`!` insert reverted as `sentenceCoupledRevert`
/// (or, for 2/120, `atomicGroupRevert`) when a rejected content edit
/// elsewhere in the same raw sentence fires the coupled revert. Fixed by
/// `EditGuard.isUtteranceFinalTerminalMarkInsert`, consulted by both
/// `applyAtomicGroupCoupling` and `applySentenceCoupledRevert`.
///
/// Every fixture is INVENTED — different topic, invented names, no personal
/// facts. The one live record cited is referenced only by ts
/// (`2026-09-26T03:59:07.087Z`, the P1 shape) per D-12; no dictation text is
/// quoted anywhere in this file. `bbz_privacy_check.py` in the quick task
/// directory verifies no 5-word shingle overlap with the staged corpus.
///
/// P1-P4 are RED before the fix (actual = expected minus the final mark);
/// N1-N4 are GREEN both before and after — each pins one clause of the
/// predicate.
@MainActor
final class EditGuardUtteranceFinalMarkTests: XCTestCase {

    private func guardOut(_ baseline: String, _ llm: String, _ lang: String = "en") -> String {
        EditGuard.apply(rulesCleaned: baseline, llmOutput: llm, language: lang, lexicon: TestSpellLexicon.allKnown).text
    }

    private func guardResult(_ baseline: String, _ llm: String, _ lang: String = "en") -> EditGuard.GuardResult {
        EditGuard.apply(rulesCleaned: baseline, llmOutput: llm, language: lang, lexicon: TestSpellLexicon.allKnown)
    }

    // MARK: - P1: run-on shape (2026-09-26T03:59:07.087Z shape) — interior splits + word->mark substitute + adjacent delete + derivational pair, final mark appended

    /// Invented 40+-word run-on with no raw marks. The LLM splits it into 4
    /// sentences via 2 interior `.` inserts, one word->mark substitute
    /// (`and`->`.`) paired with an adjacent `then` deletion, and one
    /// derivational pair (`loaded`->`loadment`, suffix `-ment`) — then
    /// appends a `.` after the last raw word (`quickly`). RED before the
    /// fix: the actual string equals `expected` minus its final `.`, and
    /// the LAST edit's `rejectClass` is `sentenceCoupledRevert`.
    func testP1_runOnWithInteriorSplitsAndFinalMarkAppended() {
        let baseline = "the manager called the client about the shipment and then the driver arrived early and then the team loaded the truck with boxes and then the client signed the delivery form and then everyone went home for the evening quickly"
        let llm = "The manager called the client about the shipment. And then the driver arrived early. The team loadment the truck with boxes. And then the client signed the delivery form and then everyone went home for the evening quickly."
        let expected = baseline + "."
        let out = guardOut(baseline, llm)
        let result = guardResult(baseline, llm)
        XCTAssertEqual(out, expected, "edits: \(result.edits)")
        guard let last = result.edits.last else { return XCTFail("no edits") }
        XCTAssertEqual(last.kind, "insert")
        XCTAssertEqual(last.to, ".")
        XCTAssertTrue(last.accepted)
        XCTAssertEqual(last.acceptClass, "punctuationOrCasing")
        // Guards against a too-broad predicate: an interior "." insert in
        // this same triggered raw sentence must still revert.
        XCTAssertTrue(result.edits.contains { $0.kind == "insert" && $0.to == "." && $0.rejectClass == "sentenceCoupledRevert" })
        // The word->mark substitute and the adjacent delete are present,
        // confirming the fixture carries the intended shape.
        XCTAssertTrue(result.edits.contains { $0.kind == "substitute" && $0.from == "and" && $0.to == "." && $0.rejectClass == "contentWordIdentityChange" })
        XCTAssertTrue(result.edits.contains { $0.kind == "delete" && $0.from == "then" && $0.rejectClass == "contentWordDeletion" })
        XCTAssertTrue(result.edits.contains { $0.kind == "substitute" && $0.from == "loaded" && $0.to == "loadment" && $0.rejectClass == "derivationalSuffixChange" })
        let v = EditGuardMergeAtomicityTests.neitherSourceViolations(output: out, sourceA: baseline, sourceB: llm)
        XCTAssertTrue(v.tier1.isEmpty, "tier-1 neither-source violation(s) \(v.tier1) in: \(out)")
    }

    // MARK: - P2: atomic neighbour — last raw word is a rejected content substitute directly before the mark

    /// The last raw word is replaced by a rejected content substitute
    /// (`report`->`assessment`) directly before the LLM's `.` insert.
    /// Pre-fix, the mark shares the substitute's keep-bounded cluster and
    /// its rejectClass is `atomicGroupRevert` (not `sentenceCoupledRevert`)
    /// — this fixture fails if only `applySentenceCoupledRevert` is fixed.
    func testP2_atomicNeighbourRejectedLastWordSubstitute() {
        let baseline = "she finished the report"
        let llm = "She finished the assessment."
        let expected = baseline + "."
        let out = guardOut(baseline, llm)
        let result = guardResult(baseline, llm)
        XCTAssertEqual(out, expected, "edits: \(result.edits)")
        guard let last = result.edits.last else { return XCTFail("no edits") }
        XCTAssertEqual(last.kind, "insert")
        XCTAssertEqual(last.to, ".")
        XCTAssertTrue(last.accepted)
        XCTAssertEqual(last.acceptClass, "punctuationOrCasing")
        XCTAssertTrue(result.edits.contains { $0.kind == "substitute" && $0.from == "report" && $0.to == "assessment" && $0.rejectClass == "contentWordIdentityChange" })
        let v = EditGuardMergeAtomicityTests.neitherSourceViolations(output: out, sourceA: baseline, sourceB: llm)
        XCTAssertTrue(v.tier1.isEmpty, "tier-1 neither-source violation(s) \(v.tier1) in: \(out)")
    }

    // MARK: - P3: multi-sentence — sentence 1 keeps an untriggered accepted comma, sentence 2 fully reverts then gets the final mark

    /// Raw sentence 1 ends in a raw `.` and carries an accepted LLM comma
    /// insert with no trigger of its own. Raw sentence 2 has a content
    /// trigger and no final mark; the LLM appends `.` after it. Expected:
    /// sentence 1 keeps its comma, sentence 2 reverts to raw, then `.`.
    func testP3_multiSentenceSecondSentenceRevertsWithFinalMark() {
        let baseline = "I called him yesterday. she never returned the call"
        let llm = "I called him, yesterday. She never returned the item."
        let expected = "I called him, yesterday. she never returned the call."
        let out = guardOut(baseline, llm)
        let result = guardResult(baseline, llm)
        XCTAssertEqual(out, expected, "edits: \(result.edits)")
        guard let last = result.edits.last else { return XCTFail("no edits") }
        XCTAssertEqual(last.kind, "insert")
        XCTAssertEqual(last.to, ".")
        XCTAssertTrue(last.accepted)
        XCTAssertEqual(last.acceptClass, "punctuationOrCasing")
        // Sentence 1's comma survives — no trigger in that raw sentence.
        XCTAssertTrue(result.edits.contains { $0.kind == "insert" && $0.to == "," && $0.accepted && $0.acceptClass == "punctuationOrCasing" })
        // Sentence 2's content trigger and casing revert.
        XCTAssertTrue(result.edits.contains { $0.kind == "substitute" && $0.from == "call" && $0.to == "item" && $0.rejectClass == "contentWordIdentityChange" })
        XCTAssertTrue(result.edits.contains { $0.kind == "substitute" && $0.from == "she" && $0.to == "She" && $0.rejectClass == "sentenceCoupledRevert" })
        let v = EditGuardMergeAtomicityTests.neitherSourceViolations(output: out, sourceA: baseline, sourceB: llm)
        XCTAssertTrue(v.tier1.isEmpty, "tier-1 neither-source violation(s) \(v.tier1) in: \(out)")
    }

    // MARK: - P4: question — content trigger, LLM appends `?`, no mood-lock

    /// A question-shaped raw clause without a mark, a content trigger
    /// inside, and an LLM-appended `?` with no `moodLockSentenceInitialVerb`
    /// anywhere in the result (the baseline is already modal-initial, so
    /// the mood lock never fires). Expected: baseline + `?`.
    func testP4_questionShapedClauseFinalMarkIsQuestionMark() {
        let baseline = "can you send the report"
        let llm = "Can you send the invoice?"
        let expected = baseline + "?"
        let out = guardOut(baseline, llm)
        let result = guardResult(baseline, llm)
        XCTAssertEqual(out, expected, "edits: \(result.edits)")
        guard let last = result.edits.last else { return XCTFail("no edits") }
        XCTAssertEqual(last.kind, "insert")
        XCTAssertEqual(last.to, "?")
        XCTAssertTrue(last.accepted)
        XCTAssertEqual(last.acceptClass, "punctuationOrCasing")
        XCTAssertFalse(result.edits.contains { $0.rejectClass == "moodLockSentenceInitialVerb" })
        let v = EditGuardMergeAtomicityTests.neitherSourceViolations(output: out, sourceA: baseline, sourceB: llm)
        XCTAssertTrue(v.tier1.isEmpty, "tier-1 neither-source violation(s) \(v.tier1) in: \(out)")
    }

    // MARK: - N1: no double mark — raw already ends in "." and the LLM keeps it

    /// Raw already ends in `.` and the LLM keeps it, with a trigger present
    /// elsewhere. Expected = baseline exactly, ending in exactly one `.`.
    /// GREEN both before and after — the final edit is a `.keep`, never
    /// reaching clause (a)'s `.insert` requirement.
    func testN1_rawAlreadyEndsInPeriodNoDoubleMark() {
        let baseline = "he fixed the printer."
        let llm = "He fixed the router."
        let expected = baseline
        let out = guardOut(baseline, llm)
        let result = guardResult(baseline, llm)
        XCTAssertEqual(out, expected, "edits: \(result.edits)")
        XCTAssertFalse(out.hasSuffix(".."))
        guard let last = result.edits.last else { return XCTFail("no edits") }
        XCTAssertEqual(last.kind, "keep")
        let v = EditGuardMergeAtomicityTests.neitherSourceViolations(output: out, sourceA: baseline, sourceB: llm)
        XCTAssertTrue(v.tier1.isEmpty, "tier-1 neither-source violation(s) \(v.tier1) in: \(out)")
    }

    // MARK: - N2: trailing insert after the mark — clause (b)

    /// An accepted content trigger elsewhere in the sentence, then a `.`
    /// insert directly after the last raw word, THEN a further accepted
    /// trailing function-word insert (`with`) after the mark. The mark
    /// looks locally like an exemption candidate (preceded by a keep of the
    /// last raw word) but is NOT the last edit in the array — clause (b)
    /// excludes it, so it reverts exactly as before. GREEN both before and
    /// after the fix.
    func testN2_trailingInsertAfterMarkDefeatsExemption() {
        let baseline = "he rejected the proposal and closed the ticket"
        let llm = "He declined the proposal and closed the ticket. with"
        let expected = baseline
        let out = guardOut(baseline, llm)
        let result = guardResult(baseline, llm)
        XCTAssertEqual(out, expected, "edits: \(result.edits)")
        XCTAssertTrue(result.edits.contains { $0.kind == "insert" && $0.to == "." && $0.rejectClass == "sentenceCoupledRevert" })
        XCTAssertTrue(result.edits.contains { $0.kind == "insert" && $0.to == "with" && $0.rejectClass == "sentenceCoupledRevert" })
        let v = EditGuardMergeAtomicityTests.neitherSourceViolations(output: out, sourceA: baseline, sourceB: llm)
        XCTAssertTrue(v.tier1.isEmpty, "tier-1 neither-source violation(s) \(v.tier1) in: \(out)")
    }

    // MARK: - N3: moved last word — clause (c)'s kind check

    /// The LLM moves the last raw word (`yesterday`) to the front of the
    /// sentence and appends `.` where it used to sit, with a content
    /// trigger (`closed`->`opened`) elsewhere. The edit immediately before
    /// the final insert is a `.move`, not a `.keep`/`.substitute` — clause
    /// (c) excludes it (this is what "also guards move ordering" means in
    /// the predicate's doc comment). Expected = baseline exactly. GREEN
    /// both before and after the fix.
    func testN3_movedLastWordDefeatsExemption() {
        let baseline = "he closed the report yesterday"
        let llm = "Yesterday he opened the report."
        let expected = baseline
        let out = guardOut(baseline, llm)
        let result = guardResult(baseline, llm)
        XCTAssertEqual(out, expected, "edits: \(result.edits)")
        XCTAssertTrue(result.edits.contains { $0.kind == "move" })
        XCTAssertTrue(result.edits.contains { $0.kind == "insert" && $0.to == "." && !$0.accepted })
        let v = EditGuardMergeAtomicityTests.neitherSourceViolations(output: out, sourceA: baseline, sourceB: llm)
        XCTAssertTrue(v.tier1.isEmpty, "tier-1 neither-source violation(s) \(v.tier1) in: \(out)")
    }

    // MARK: - N4: mood-locked "?" — clause (d), the mutation-tested clause

    /// `fx-mov-func-de-moodlock` (`EditGuardFixtures.swift`) minus its raw
    /// period: baseline `Er kommt morgen` (no mark), LLM `Kommt er
    /// morgen?`. Clauses (a)/(b)/(c) ALL hold for this fixture (the `?`
    /// insert is last, directly preceded by a keep of the last raw word
    /// `morgen`) — only clause (d)'s mood carve-out blocks the exemption.
    /// Expected = baseline exactly (no `?`). GREEN both before and after
    /// the fix; RED if clause (d) is removed (see the mutation check in the
    /// SUMMARY).
    func testN4_moodLockedQuestionMarkDefeatsExemption() {
        let baseline = "Er kommt morgen"
        let llm = "Kommt er morgen?"
        let expected = baseline
        let out = guardOut(baseline, llm, "de")
        let result = guardResult(baseline, llm, "de")
        XCTAssertEqual(out, expected, "edits: \(result.edits)")
        XCTAssertTrue(result.edits.contains { $0.rejectClass == "moodLockSentenceInitialVerb" })
        XCTAssertTrue(result.edits.contains { $0.kind == "insert" && $0.to == "?" && !$0.accepted })
        let v = EditGuardMergeAtomicityTests.neitherSourceViolations(output: out, sourceA: baseline, sourceB: llm)
        XCTAssertTrue(v.tier1.isEmpty, "tier-1 neither-source violation(s) \(v.tier1) in: \(out)")
    }
}
