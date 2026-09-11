import XCTest
@testable import Dicticus

/// Phase 49.6 (EDITGUARD-03, D-01..D-06): regression net for coupled-edit
/// sentence-level atomic revert. Fixed by `EditGuard.applySentenceCoupledRevert`
/// (not yet implemented as of this file's RED commit — 260825-q1w landmine 10:
/// the `"sentenceCoupledRevert"` raw-string assertions below compile and run
/// today, evaluating to `false`, before the `RejectionClass` case exists).
///
/// Every fixture below is an INVENTED sentence sharing the syntactic shape of
/// one live audit record (`.planning/research/v2.6-log-audit-2026-09-10.md`,
/// finding 3) — different topic, invented names/orgs, no personal facts, no
/// health content. Cited only as `MM-DD:N` per D-12; no live dictation text
/// is quoted anywhere in this file.
///
/// Each fixture asserts, inline (not via a shared per-fixture helper, so
/// every assertion is traceable to its own test function):
///  1. The exact post-fix string (`XCTAssertEqual`) — the load-bearing,
///     RED-before-fix assertion.
///  2. `result.edits.contains { $0.rejectClass == "sentenceCoupledRevert" }`
///     — also RED before the enum case exists.
///  3. `EditGuardMergeAtomicityTests.neitherSourceViolations(...).tier1.isEmpty`
///     — must hold both before and after the fix; not itself a RED signal.
@MainActor
final class EditGuardCoupledRevertTests: XCTestCase {

    private func guardOut(_ baseline: String, _ llm: String, _ lang: String = "de") -> String {
        EditGuard.apply(rulesCleaned: baseline, llmOutput: llm, language: lang, lexicon: TestSpellLexicon.allKnown).text
    }

    private func guardResult(_ baseline: String, _ llm: String, _ lang: String = "de") -> EditGuard.GuardResult {
        EditGuard.apply(rulesCleaned: baseline, llmOutput: llm, language: lang, lexicon: TestSpellLexicon.allKnown)
    }

    // MARK: - Shape A: 08-30:16 — accepted function-word substitute + rejected content substitute, same sentence

    /// Shape of `08-30:16`: an accepted `functionWordSubstitution`
    /// (article/agreement pair, NOT in the D-09 conjunction/negator set) and
    /// a rejected `contentWordIdentityChange` substitute in the same raw
    /// sentence, separated by one `.keep` so `applyAtomicGroupCoupling` does
    /// not already cluster them together. Invented topic: a status report
    /// sent to a fictional agency.
    func testShapeA_functionSubstituteAcceptedContentSubstituteRejected() {
        let baseline = "Der Bericht denke ich morgen an die Firnwald Logistik AG"
        let llm = "Den Bericht schicke ich morgen an die Firnwald Logistik AG."
        let expected = baseline
        let out = guardOut(baseline, llm)
        let result = guardResult(baseline, llm)
        XCTAssertEqual(out, expected)
        XCTAssertTrue(result.edits.contains { $0.rejectClass == "sentenceCoupledRevert" })
        let v = EditGuardMergeAtomicityTests.neitherSourceViolations(output: out, sourceA: baseline, sourceB: llm)
        XCTAssertTrue(v.tier1.isEmpty, "tier-1 neither-source violation(s) \(v.tier1) in: \(out)")
    }

    // MARK: - Shape B: 08-20:10 — accepted word-order move + rejected content insert, same sentence

    /// Shape of `08-20:10`: an accepted `wordOrderRepair` `.move` of a
    /// pronoun and a rejected `contentWordInsertion` verb insert a few
    /// tokens later in the same raw sentence.
    func testShapeB_pronounMoveAcceptedVerbInsertRejected() {
        let baseline = "Also du kannst Berichte und im Englischen Reports."
        let llm = "Also kannst du Berichte und im Englischen Reports schreiben."
        let expected = baseline
        let out = guardOut(baseline, llm)
        let result = guardResult(baseline, llm)
        XCTAssertEqual(out, expected)
        XCTAssertTrue(result.edits.contains { $0.rejectClass == "sentenceCoupledRevert" })
        let v = EditGuardMergeAtomicityTests.neitherSourceViolations(output: out, sourceA: baseline, sourceB: llm)
        XCTAssertTrue(v.tier1.isEmpty, "tier-1 neither-source violation(s) \(v.tier1) in: \(out)")
    }

    // MARK: - Shape C: 08-30:27 — accepted subordinator insert + rejected verb-final insert, same sentence

    /// Shape of `08-30:27`: an accepted `functionWordInsertion` (`dass`)
    /// whose clause needs a rejected `contentWordInsertion` verb-final
    /// partner, in the same raw (single-sentence, no baseline period)
    /// utterance.
    func testShapeC_dassInsertAcceptedVerbInsertRejectedPlusCasing() {
        let baseline = "man sagt beim Schwimmen etwa 70 Prozent der Muskeln beansprucht"
        let llm = "Man sagt, dass beim Schwimmen etwa 70 Prozent der Muskeln beansprucht werden."
        let expected = baseline
        let out = guardOut(baseline, llm)
        let result = guardResult(baseline, llm)
        XCTAssertEqual(out, expected)
        XCTAssertTrue(result.edits.contains { $0.rejectClass == "sentenceCoupledRevert" })
        let v = EditGuardMergeAtomicityTests.neitherSourceViolations(output: out, sourceA: baseline, sourceB: llm)
        XCTAssertTrue(v.tier1.isEmpty, "tier-1 neither-source violation(s) \(v.tier1) in: \(out)")
    }

    // MARK: - Shape D: 08-20:21 — accepted relative pronoun + comma insert, rejected clause-closing verb insert

    /// Shape of `08-20:21`: accepted `functionWordInsertion` of a relative
    /// pronoun (`das`) plus an accepted comma insert, and a rejected verb
    /// insert closing the relative clause, all in the same raw sentence.
    func testShapeD_relativePronounKeptVerbRejected() {
        let baseline = "Es nervt mich ehrlich gesagt schon seit Wochen dieses Banner jetzt kaufen"
        let llm = "Es nervt mich ehrlich gesagt schon seit Wochen dieses Banner, das jetzt kaufen anzeigt."
        let expected = baseline
        let out = guardOut(baseline, llm)
        let result = guardResult(baseline, llm)
        XCTAssertEqual(out, expected)
        XCTAssertTrue(result.edits.contains { $0.rejectClass == "sentenceCoupledRevert" })
        let v = EditGuardMergeAtomicityTests.neitherSourceViolations(output: out, sourceA: baseline, sourceB: llm)
        XCTAssertTrue(v.tier1.isEmpty, "tier-1 neither-source violation(s) \(v.tier1) in: \(out)")
    }

    // MARK: - Shape E: 08-20:13 — accepted pause-split period delete, rejected content substitute, same sentence

    /// Shape of `08-20:13`: an accepted `pauseSplitMerge` period delete
    /// (all four `isPauseSplitPeriod` arms satisfied: exact `.`, empty own
    /// trailing that is whitespace on the next token, previous word >= 5
    /// chars, lowercase continuation) sitting in the same raw sentence as a
    /// rejected content substitute — the "period deleted without the
    /// compensating comma" defect. Constructed as a pure `.delete` (not a
    /// `.substitute`) so `EditDiff` does not pair the period-delete and a
    /// comma-insert into one punctuation substitute (which
    /// `applyAtomicGroupCoupling`'s punctuation-only-group handling would
    /// already revert, making this fixture vacuously green pre-fix).
    /// Pre-fix defect string this fixture exhibits: "Erfahrung dass ich"
    /// (period lost, no compensating punctuation).
    func testShapeE_pauseSplitPeriodDroppedCompensatingCommaReverted() {
        let baseline = "Mir fehlt dafür die Zeit oder Erfahrung. dass ich das allein schaffe glaube ich nicht."
        let llm = "Mir fehlt dafür die Zeit oder Kapazität dass ich das allein schaffe, glaube ich nicht."
        let expected = "Mir fehlt dafür die Zeit oder Erfahrung. dass ich das allein schaffe, glaube ich nicht."
        let out = guardOut(baseline, llm)
        let result = guardResult(baseline, llm)
        XCTAssertEqual(out, expected)
        XCTAssertTrue(result.edits.contains { $0.rejectClass == "sentenceCoupledRevert" })
        let v = EditGuardMergeAtomicityTests.neitherSourceViolations(output: out, sourceA: baseline, sourceB: llm)
        XCTAssertTrue(v.tier1.isEmpty, "tier-1 neither-source violation(s) \(v.tier1) in: \(out)")
    }

    // MARK: - Shape F: 09-03:25 — accepted casing promotes a dropout fragment, rejected rewrite in the same fragment sentence

    /// Shape of `09-03:25`: a raw dropout-fragment sentence (lowercase
    /// start) whose LLM rewrite (content substitute + insert) is rejected,
    /// while a sentence-initial casing substitute on the SAME fragment is
    /// accepted in a different keep-bounded run (cluster) of the SAME raw
    /// sentence — pre-fix the casing promotes the fragment into what reads
    /// as a standalone sentence.
    func testShapeF_casingPromotesDropoutFragmentAfterRejectedRewrite() {
        let baseline = "Das Datum ist abgelaufen. nicht stimmen kann das. Ist das ein Fehler?"
        let llm = "Das Datum ist abgelaufen. Nicht stimmen kann das nicht sein. Ist das ein Fehler?"
        let expected = baseline
        let out = guardOut(baseline, llm)
        let result = guardResult(baseline, llm)
        XCTAssertEqual(out, expected)
        XCTAssertTrue(result.edits.contains { $0.rejectClass == "sentenceCoupledRevert" })
        let v = EditGuardMergeAtomicityTests.neitherSourceViolations(output: out, sourceA: baseline, sourceB: llm)
        XCTAssertTrue(v.tier1.isEmpty, "tier-1 neither-source violation(s) \(v.tier1) in: \(out)")
    }

    // MARK: - Shape G: far-repair cost case — accepted verb-second move ~10 tokens from a rejected content substitute

    /// Not tied to a specific audit record — the D-01 "accepted cost" case:
    /// a correct verb-second `.move` and a rejected `contentWordIdentityChange`
    /// substitute roughly 10 tokens later in the same raw sentence. The
    /// sentence rule reverts the whole sentence, including the otherwise-
    /// correct move. The replay (plan 04) must count this as REVERT-TO-RAW,
    /// never REGRESSION (D-01, D-07) — this is the accepted cost the user
    /// signed off on, not a defect.
    func testShapeG_farVerbSecondRepairRevertsToRaw_acceptedCost() {
        let baseline = "Gestern ich habe den Bericht an die Agentur Haldenwerk geschickt weil der Termin knapp war"
        let llm = "Gestern habe ich den Bericht an die Agentur Haldenwerk gesendet, weil der Termin knapp war."
        let expected = baseline
        let out = guardOut(baseline, llm)
        let result = guardResult(baseline, llm)
        XCTAssertEqual(out, expected)
        XCTAssertTrue(result.edits.contains { $0.rejectClass == "sentenceCoupledRevert" })
        let v = EditGuardMergeAtomicityTests.neitherSourceViolations(output: out, sourceA: baseline, sourceB: llm)
        XCTAssertTrue(v.tier1.isEmpty, "tier-1 neither-source violation(s) \(v.tier1) in: \(out)")
    }

    // MARK: - D-15 boundary coupling (gap plan 06)

    /// Positive, substitute form — period form, ts-cited in
    /// `49.6-GATE-DIFF.md` §4. A restored terminal `.` at the end of raw
    /// sentence N must couple the `punctuationOrCasing` casing substitute on
    /// raw sentence N+1's first word token. Invented topic: a vendor status
    /// update. RED before the fix: the pre-fix actual string contains
    /// "today. which" (lowercase `which` surviving unreverted).
    func testD15_periodSubstituteMergeRevertsNextSentenceCasing() {
        let baseline = "We should confirm our vendor today. Which team is installing the update this week."
        let llm = "We should confirm our supplier today, which team is installing the update this week?"
        let expected = "We should confirm our vendor today. Which team is installing the update this week?"
        let out = guardOut(baseline, llm, "en")
        let result = guardResult(baseline, llm, "en")
        XCTAssertEqual(out, expected)
        XCTAssertTrue(result.edits.contains { $0.kind == "substitute" && $0.from == "Which" && $0.rejectClass == "sentenceCoupledRevert" })
        let v = EditGuardMergeAtomicityTests.neitherSourceViolations(output: out, sourceA: baseline, sourceB: llm)
        XCTAssertTrue(v.tier1.isEmpty, "tier-1 neither-source violation(s) \(v.tier1) in: \(out)")
    }

    /// Positive, delete form — period form, ts-cited in
    /// `49.6-GATE-DIFF.md` §4. A restored terminal `.` deleted by the LLM's
    /// merge must couple the casing substitute on raw sentence N+1's first
    /// word token. Invented topic: two routes to a destination. RED before
    /// the fix: the pre-fix actual string contains "begin. because"
    /// (lowercase `because` surviving unreverted).
    func testD15_periodDeleteMergeRevertsNextSentenceCasing() {
        let baseline = "It is rarely clear where to begin. Because both routes carry the same toll."
        let llm = "It is rarely obvious where to begin because both routes carry the same toll."
        let expected = baseline
        let out = guardOut(baseline, llm, "en")
        let result = guardResult(baseline, llm, "en")
        XCTAssertEqual(out, expected)
        XCTAssertTrue(result.edits.contains { $0.kind == "substitute" && $0.from == "Because" && $0.rejectClass == "sentenceCoupledRevert" })
        let v = EditGuardMergeAtomicityTests.neitherSourceViolations(output: out, sourceA: baseline, sourceB: llm)
        XCTAssertTrue(v.tier1.isEmpty, "tier-1 neither-source violation(s) \(v.tier1) in: \(out)")
    }

    /// Negative, ellipsis form — the shape of the two ellipsis-form rows
    /// exported in `49.6-AMBIGUOUS.md`. The restored `...` run is not a
    /// member of `sentenceTerminalMarks` (it is a single multi-character run
    /// token, not one of the three single-character marks), so it must NOT
    /// couple the next sentence's casing — the user's own REVERT-TO-RAW
    /// ruling on the two ellipsis rows, pinned. GREEN both before and after
    /// the fix.
    func testD15_ellipsisBoundaryKeepsNextSentenceCasing() {
        let baseline = "We worry the plan will let the whole team lose... Patience with the rollout plan."
        let llm = "We worry the plan will let the whole crew lose patience with the rollout plan."
        let expected = "We worry the plan will let the whole team lose... patience with the rollout plan."
        let out = guardOut(baseline, llm, "en")
        let result = guardResult(baseline, llm, "en")
        XCTAssertEqual(out, expected)
        XCTAssertTrue(result.edits.contains { $0.kind == "substitute" && $0.from == "Patience" && $0.accepted && $0.acceptClass == "punctuationOrCasing" })
        let v = EditGuardMergeAtomicityTests.neitherSourceViolations(output: out, sourceA: baseline, sourceB: llm)
        XCTAssertTrue(v.tier1.isEmpty, "tier-1 neither-source violation(s) \(v.tier1) in: \(out)")
    }

    /// Negative, N+1 carries its own trigger — the substitute-form pair
    /// above, with an additional rejected content substitute inside raw
    /// sentence N+1. The pre-49.6-06 sentence rule already fully reverts
    /// N+1 on its own trigger; this pins that the D-15 refinement adds
    /// nothing where the sentence rule already fires. GREEN both before and
    /// after the fix.
    func testD15_nextSentenceOwnTriggerByteIdentical() {
        let baseline = "We should confirm our vendor today. Which team is installing the update this week."
        let llm = "We should confirm our supplier today, which team is enabling the update this week?"
        let expected = baseline
        let out = guardOut(baseline, llm, "en")
        let result = guardResult(baseline, llm, "en")
        XCTAssertEqual(out, expected)
        XCTAssertTrue(result.edits.contains { $0.kind == "substitute" && $0.from == "installing" && $0.rejectClass != nil })
        let v = EditGuardMergeAtomicityTests.neitherSourceViolations(output: out, sourceA: baseline, sourceB: llm)
        XCTAssertTrue(v.tier1.isEmpty, "tier-1 neither-source violation(s) \(v.tier1) in: \(out)")
    }
}
