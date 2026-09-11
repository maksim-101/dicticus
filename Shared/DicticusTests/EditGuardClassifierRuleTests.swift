import XCTest
@testable import Dicticus

/// Phase 49.6 (CLASSIFY-01, CLASSIFY-02, CLASSIFY-03): regression net for
/// the three narrow classifier misfires from the 2026-09-10 audit (finding
/// 5) — D-09 (conjunctions/negators are content), D-11 (a hyphen fused
/// between a word and a digit changes an identifier), and D-10 (`nonWordRepair`
/// stays as is; its two audit residues are pinned as documented, not fixed).
///
/// Every fixture is an INVENTED sentence sharing the syntactic shape of the
/// audit's live evidence (`.planning/research/v2.6-log-audit-2026-09-10.md`,
/// finding 5) — different topic, invented names/orgs, no personal facts, no
/// health content. Cited only as `MM-DD:N` per D-12; no live dictation text
/// is quoted anywhere in this file.
///
/// `_RED` in a test's name means it fails on pre-fix code (post-plan-02
/// HEAD, before this plan's Task 2 lands) — six such tests, matching D-12's
/// "each synthetic fixture must be shown RED on pre-fix code" requirement.
/// Every other test is a GREEN pin: current behaviour this plan must NOT
/// change, asserted so Task 2's predicates cannot accidentally widen.
@MainActor
final class EditGuardClassifierRuleTests: XCTestCase {

    private func guardOut(_ baseline: String, _ llm: String, _ lang: String = "en") -> String {
        EditGuard.apply(rulesCleaned: baseline, llmOutput: llm, language: lang, lexicon: TestSpellLexicon.allKnown).text
    }

    private func guardResult(_ baseline: String, _ llm: String, _ lang: String = "en") -> EditGuard.GuardResult {
        EditGuard.apply(rulesCleaned: baseline, llmOutput: llm, language: lang, lexicon: TestSpellLexicon.allKnown)
    }

    /// D-10 variant: an explicit injected lexicon, modelling the OS
    /// checker's measured KNOWN verdicts for the two residue pairs
    /// (`TestSpellLexicon(known:)`, not `.allKnown` — criterion A needs
    /// `known(a) == false`, which `.allKnown` can never satisfy).
    private func guardResult(_ baseline: String, _ llm: String, lang: String, lexicon: TestSpellLexicon) -> EditGuard.GuardResult {
        EditGuard.apply(rulesCleaned: baseline, llmOutput: llm, language: lang, lexicon: lexicon)
    }

    private func assertNoNeitherSourceViolation(_ out: String, _ a: String, _ b: String, file: StaticString = #filePath, line: UInt = #line) {
        let v = EditGuardMergeAtomicityTests.neitherSourceViolations(output: out, sourceA: a, sourceB: b)
        XCTAssertTrue(v.tier1.isEmpty, "tier-1 neither-source violation(s) \(v.tier1) in: \(out)", file: file, line: line)
    }

    // MARK: - D-09 (CLASSIFY-01): substitute — coordinator/negator swap is content

    /// Audit 08-23:52 shape: a coordinator swapped for another coordinator
    /// ("and" -> "or") flips the logical relation between two clauses.
    /// RED: today accepted as `functionWordSubstitution` (both sides are
    /// in `englishSubstitutable` via `englishInsertable`); after Task 2,
    /// the coordinator lock rejects it before step 6 can accept.
    func testD09_substituteAndToOr_RED() {
        let baseline = "check for logic and necessity"
        let llm = "check for logic or necessity"
        let out = guardOut(baseline, llm)
        XCTAssertEqual(out, baseline)
        let result = guardResult(baseline, llm)
        guard let edit = result.edits.first(where: { $0.from == "and" }) else {
            return XCTFail("expected a substitute edit from 'and'")
        }
        XCTAssertFalse(edit.accepted)
        XCTAssertEqual(edit.rejectClass, EditGuard.RejectionClass.contentWordIdentityChange.rawValue)
        assertNoNeitherSourceViolation(out, baseline, llm)
    }

    /// Audit 08-30:16 shape: a negator swapped for ANOTHER negator
    /// (`kein` -> `nicht`) — D-09 explicitly includes negator-to-negator
    /// swaps as content-bearing, even though both sides pass the existing
    /// `aIsNegation != bIsNegation` polarity check unchanged (both are
    /// negation, so that check alone would still accept it). RED: today
    /// accepted as `functionWordSubstitution`.
    func testD09_substituteKeinToNicht_RED() {
        let baseline = "Zucker esse ich kein und Salz auch nicht"
        let llm = "Zucker esse ich nicht und Salz auch nicht"
        let out = guardOut(baseline, llm, "de")
        XCTAssertEqual(out, baseline)
        let result = guardResult(baseline, llm, "de")
        guard let edit = result.edits.first(where: { $0.from == "kein" }) else {
            return XCTFail("expected a substitute edit from 'kein'")
        }
        XCTAssertFalse(edit.accepted)
        XCTAssertEqual(edit.rejectClass, EditGuard.RejectionClass.contentWordIdentityChange.rawValue)
        assertNoNeitherSourceViolation(out, baseline, llm)
    }

    /// The polarity flip itself must still classify `negationChange` — the
    /// carve-out D-09 explicitly keeps. GREEN pin (no code change touches
    /// this path): step 6's `aIsNegation != bIsNegation` check already
    /// fires before the new coordinator/negator lock is ever reached
    /// (that lock sits after it, per the plan's placement).
    func testD09_polarityCarveOutStillNegationChange() {
        let baseline = "there is no way to end it"
        let llm = "there is a way to end it"
        let out = guardOut(baseline, llm)
        XCTAssertEqual(out, baseline)
        let result = guardResult(baseline, llm)
        guard let edit = result.edits.first(where: { $0.from == "no" }) else {
            return XCTFail("expected a substitute edit from 'no'")
        }
        XCTAssertFalse(edit.accepted)
        XCTAssertEqual(edit.rejectClass, EditGuard.RejectionClass.negationChange.rawValue)
        assertNoNeitherSourceViolation(out, baseline, llm)
    }

    /// D-09's `keinem` -> `einem` polarity case: `keinem` is not yet in
    /// `germanNegation` pre-fix, so this pair reaches step 9's fail-closed
    /// path and classifies `contentWordIdentityChange` today — the SAME
    /// verdict (rejected, output == baseline) the fix will also produce,
    /// but under a DIFFERENT label (`negationChange`, once `keinem` joins
    /// `germanNegation` and the existing polarity check at step 6 fires).
    /// RED on the label only — `plan 04's rejected_by_class` counts the
    /// label, so the distinction matters even though the text never
    /// changes either way.
    func testD09_polarityKeinemToEinem_RED() {
        let baseline = "Das gehört keinem Team."
        let llm = "Das gehört einem Team."
        let out = guardOut(baseline, llm, "de")
        XCTAssertEqual(out, baseline)
        let result = guardResult(baseline, llm, "de")
        guard let edit = result.edits.first(where: { $0.from == "keinem" }) else {
            return XCTFail("expected a substitute edit from 'keinem'")
        }
        XCTAssertFalse(edit.accepted)
        XCTAssertEqual(edit.rejectClass, EditGuard.RejectionClass.negationChange.rawValue)
        assertNoNeitherSourceViolation(out, baseline, llm)
    }

    // MARK: - D-09 (CLASSIFY-01): insert — coordinator/negator insertion is content

    /// Audit shape: a missing coordinator inserted asserts a relation the
    /// speaker never said. RED: today accepted as `functionWordInsertion`
    /// (`"and"` is in `englishInsertable`); after Task 2, the coordinator
    /// lock rejects it before `isInsertable` is ever consulted.
    func testD09_insertAnd_RED() {
        let baseline = "we test the parser the linter"
        let llm = "we test the parser and the linter"
        let out = guardOut(baseline, llm)
        XCTAssertEqual(out, baseline)
        let result = guardResult(baseline, llm)
        guard let edit = result.edits.first(where: { $0.to == "and" }) else {
            return XCTFail("expected an insert edit of 'and'")
        }
        XCTAssertFalse(edit.accepted)
        XCTAssertEqual(edit.rejectClass, EditGuard.RejectionClass.contentWordInsertion.rawValue)
        assertNoNeitherSourceViolation(out, baseline, llm)
    }

    /// DE analogue with `sondern` (already in `germanInsertable` pre-fix).
    /// The sentence also carries an accepted comma insert — pre-fix both
    /// insertions accept, so the candidate ships whole; post-fix, the
    /// `sondern` insert is a D-03 trigger and plan 02's sentence-coupled
    /// revert takes the comma insert down with it, so the WHOLE sentence
    /// reverts to baseline (the D-09/D-01 interaction cost the plan's own
    /// action step names). RED: today the candidate ships unmodified.
    func testD09_insertSondern_RED() {
        let baseline = "nicht heute morgen"
        let llm = "nicht heute, sondern morgen"
        let out = guardOut(baseline, llm, "de")
        XCTAssertEqual(out, baseline)
        let result = guardResult(baseline, llm, "de")
        guard let edit = result.edits.first(where: { $0.to == "sondern" }) else {
            return XCTFail("expected an insert edit of 'sondern'")
        }
        XCTAssertFalse(edit.accepted)
        XCTAssertEqual(edit.rejectClass, EditGuard.RejectionClass.contentWordInsertion.rawValue)
        assertNoNeitherSourceViolation(out, baseline, llm)
    }

    /// A negator insert was ALREADY rejected pre-fix (negation was never in
    /// `germanInsertable`) — GREEN pin, no code change touches this path;
    /// it falls to `classifyInsert`'s final `contentWordInsertion`
    /// fail-closed return today and will continue to (the new lock is a
    /// no-op for tokens that were already rejected).
    func testD09_negatorInsertAlreadyRejected() {
        let baseline = "das ist richtig"
        let llm = "das ist nicht richtig"
        let out = guardOut(baseline, llm, "de")
        XCTAssertEqual(out, baseline)
        let result = guardResult(baseline, llm, "de")
        guard let edit = result.edits.first(where: { $0.to == "nicht" }) else {
            return XCTFail("expected an insert edit of 'nicht'")
        }
        XCTAssertFalse(edit.accepted)
        XCTAssertEqual(edit.rejectClass, EditGuard.RejectionClass.contentWordInsertion.rawValue)
        assertNoNeitherSourceViolation(out, baseline, llm)
    }

    // MARK: - D-09 (CLASSIFY-01): delete — untouched, pinned as documented non-fix

    /// `classifyDelete` already rejects a plain negator delete as
    /// `contentWordDeletion` (its existing fall-through, no exception
    /// list) — GREEN pin, `classifyDelete` is out of scope for this plan.
    func testD09_deleteNicht() {
        let baseline = "das stimmt nicht ganz"
        let llm = "das stimmt ganz"
        let out = guardOut(baseline, llm, "de")
        XCTAssertEqual(out, baseline)
        let result = guardResult(baseline, llm, "de")
        guard let edit = result.edits.first(where: { $0.from == "nicht" }) else {
            return XCTFail("expected a delete edit of 'nicht'")
        }
        XCTAssertFalse(edit.accepted)
        XCTAssertEqual(edit.rejectClass, EditGuard.RejectionClass.contentWordDeletion.rawValue)
        assertNoNeitherSourceViolation(out, baseline, llm)
    }

    /// An adjacent-duplicate coordinator delete ("and and then" -> "and
    /// then") stays ACCEPTED — meaning is unchanged, so D-09's criterion
    /// (a substitution/insertion/deletion that changes the logical
    /// relation between clauses or the polarity of a claim) does not
    /// apply; this is deliberately NOT blocked. GREEN pin. Verified via
    /// `debugEG`: the delete is classified `disfluencyCollapse` (the
    /// adjacent-duplicate-block pass runs before the plain-repetition
    /// check in `classifyDelete`), not `repetitionDeletion` — same
    /// "meaning-preserving collapse" accept-class family either way, and
    /// outside D-09's scope regardless of which of the two fires.
    func testD09_deleteRepetitionAndAnd() {
        let baseline = "and and then"
        let llm = "and then"
        let out = guardOut(baseline, llm)
        XCTAssertEqual(out, llm)
        let result = guardResult(baseline, llm)
        guard let edit = result.edits.first(where: { $0.kind == "delete" && $0.from == "and" }) else {
            return XCTFail("expected a delete edit of 'and'")
        }
        XCTAssertTrue(edit.accepted)
        XCTAssertEqual(edit.acceptClass, EditGuard.AcceptClass.disfluencyCollapse.rawValue)
        assertNoNeitherSourceViolation(out, baseline, llm)
    }

    // MARK: - D-11 (CLASSIFY-03): hyphen insert of shape word-then-digit only

    /// Audit 08-22:65 shape: a hyphen fused onto a word-then-digit
    /// identifier changes the identifier ("Fable 5" -> "Fable-5"). RED:
    /// today the `-` insert is unconditionally prosodic and accepted;
    /// after Task 2 it rejects under `digitValueChange`.
    func testD11_hyphenInsertWordThenDigit_RED() {
        let baseline = "we compared it against Fable 5 yesterday"
        let llm = "we compared it against Fable-5 yesterday"
        let out = guardOut(baseline, llm)
        XCTAssertEqual(out, baseline)
        let result = guardResult(baseline, llm)
        guard let edit = result.edits.first(where: { $0.kind == "insert" && $0.to == "-" }) else {
            return XCTFail("expected an insert edit of '-'")
        }
        XCTAssertFalse(edit.accepted)
        XCTAssertEqual(edit.rejectClass, EditGuard.RejectionClass.digitValueChange.rawValue)
        assertNoNeitherSourceViolation(out, baseline, llm)
    }

    /// Digit-then-word stays accepted ("5 Tage Woche" -> "5-Tage-Woche") —
    /// correct, often mandatory, German hyphenation. GREEN pin: verified
    /// via `debugEG` that `EditDiff` pairs this as TWO `hyphenCompoundJoin`
    /// substitutes (`Tage`->`Tage-Woche`, `Woche`->`-`), never touching
    /// `classifyInsert`'s hyphen branch at all — D-11's predicate is scoped
    /// to `.insert` edits and is structurally unreachable here regardless
    /// of code changes.
    func testD11_digitThenWordHyphenInsertStaysAccepted() {
        let baseline = "eine 5 Tage Woche ist normal"
        let llm = "eine 5-Tage-Woche ist normal"
        let out = guardOut(baseline, llm, "de")
        XCTAssertEqual(out, llm)
        assertNoNeitherSourceViolation(out, baseline, llm)
    }

    /// Hyphen DELETE stays accepted ("Fable-5" -> "Fable 5") — the LLM
    /// removing a wrong hyphen still works. GREEN pin: `classifyDelete`'s
    /// unconditional punctuation accept is untouched (D-11 says deletes
    /// are untouched, code lives only in `classifyInsert`).
    func testD11_hyphenDeleteStaysAccepted() {
        let baseline = "we compared it against Fable-5 yesterday"
        let llm = "we compared it against Fable 5 yesterday"
        let out = guardOut(baseline, llm)
        XCTAssertEqual(out, llm)
        assertNoNeitherSourceViolation(out, baseline, llm)
    }

    // MARK: - D-10 (CLASSIFY-02): documented residue pins, no code

    /// Audit 08-30:10: `Resistenztraining` is a real German compound word
    /// by the OS spell-checker oracle (accepted by decomposition); the
    /// substitution is a one-instance loanword-translation judgment call,
    /// not a defect `nonWordRepair` can or should distinguish. Documented
    /// residue, not a target — a future change that makes this WORSE (a
    /// neither-source string) must fail here.
    func testD10_residueResistenztrainingNonWordRepair() {
        let baseline = "Wie viel Resistancetraining braucht es wirklich"
        let llm = "Wie viel Resistenztraining braucht es wirklich"
        let lexicon = TestSpellLexicon(known: ["resistenztraining"])
        let result = guardResult(baseline, llm, lang: "de", lexicon: lexicon)
        XCTAssertEqual(result.text, llm)
        guard let edit = result.edits.first(where: { $0.from == "Resistancetraining" }) else {
            return XCTFail("expected a substitute edit from 'Resistancetraining'")
        }
        XCTAssertTrue(edit.accepted)
        XCTAssertEqual(edit.acceptClass, "nonWordRepair")
        assertNoNeitherSourceViolation(result.text, baseline, llm)
    }

    /// Audit 09-03:23's residue: the true failure is the clipped brand
    /// `Polyt` (fixed by Phase 49.7's dictionary entry `Polyt -> PolitMonitor`
    /// upstream of the LLM); `Polyton` is itself a real German word by the
    /// OS checker oracle. Documented residue, not a target.
    func testD10_residuePolytonNonWordRepair() {
        let baseline = "Der Polyt Monitor ist offen"
        let llm = "Der Polyton Monitor ist offen"
        let lexicon = TestSpellLexicon(known: ["polyton", "der", "monitor", "ist", "offen"])
        let result = guardResult(baseline, llm, lang: "de", lexicon: lexicon)
        XCTAssertEqual(result.text, llm)
        guard let edit = result.edits.first(where: { $0.from == "Polyt" }) else {
            return XCTFail("expected a substitute edit from 'Polyt'")
        }
        XCTAssertTrue(edit.accepted)
        XCTAssertEqual(edit.acceptClass, "nonWordRepair")
        assertNoNeitherSourceViolation(result.text, baseline, llm)
    }
}
