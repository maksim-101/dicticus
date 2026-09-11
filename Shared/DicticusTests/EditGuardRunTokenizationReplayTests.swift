import XCTest
@testable import Dicticus

/// Phase 49.5 (Wave 0 capture, Wave 3 re-baseline): a PERMANENT byte-identity
/// replay golden pinning `EditGuard.apply(...)`'s POST-FIX output for every
/// anonymized production record — a CI-runnable lock that outlives the local
/// DebugRecorder logs (D-02). Zero allowance, permanently: any future change
/// to any of these records' output must show up as a diff here.
///
/// Three records were re-baselined from their Wave-0 pre-fix values (see
/// 49.5-GATE-DIFF.md for the full live-corpus evidence and adjudication):
/// - `record-2026-09-01T17-17-59-197Z` — the designated glued-ellipsis-
///   remnant defect (see `testKnownDefectStringsNeverReturn` for the exact
///   defect string), now fixed.
/// - `record-2026-08-24T04-00-00-733Z` — the designated stray-space-before-
///   em-dash defect, now fixed.
/// - `record-2026-08-30T04-54-30-157Z` — NOT one of the two designated
///   defects, but its output legitimately changed as a side effect of
///   run-atomic tokenization. `EditGuardDanglingPunctuationTests
///   .testNoSplicedPunctuation_langweiligUnd_2026_08_30` (quick task
///   260830-dc4, pre-dates this phase) already tolerates EITHER of two
///   outputs for this exact record as equally acceptable; the fix simply
///   shifted which of those two the guard now produces. Re-baselined here so
///   the permanent lock reflects current, verified-correct behavior rather
///   than perpetually failing on a non-regression.
///
/// `testKnownDefectStringsNeverReturn` keeps the two designated defects'
/// exact-string assertions alive independently of this golden, so a future
/// re-baseline can never quietly re-legalize either one.
///
/// Phase 49.6 (D-14): re-baselined a SECOND time — "post-49.6 lock". Seven
/// entries changed, all legitimate REVERT-TO-RAW consequences of the new
/// `applySentenceCoupledRevert` pass (EDITGUARD-03) and/or this phase's
/// D-09/D-11 classifier rejections: a content-bearing rejection elsewhere
/// in the same raw sentence now takes an independently-accepted repair
/// down with it, per D-01/D-02/D-03. Zero REGRESSION among these seven
/// (verified via `debugEG`, cross-checked against the live-corpus rows
/// where the same `ts` exists). Full evidence: `49.6-GATE-DIFF.md` §1c.
/// - `record-260723-rif-offorheartrate` — REVERT-TO-RAW: contentWordDeletion
///   (×4: "what","was","of","the"), contentWordIdentityChange ("instance"→
///   ","), atomicGroupRevert (move "heartrate") revert 3 punctuation
///   inserts + a casing substitute ("so"→"So"); AFTER = raw.
/// - `record-2026-08-24T04-00-00-733Z` — REVERT-TO-RAW: matches the live
///   corpus row at ts `2026-08-24T04:00:00.733Z` in `49.6-GATE-DIFF.md` §1
///   (contentWordDeletion×3, contentWordIdentityChange×2 revert
///   punctuationOrCasing×2, functionWordInsertion×1,
///   functionWordSubstitution×1); AFTER = raw. Also the record
///   `testKnownDefectStringsNeverReturn`'s 49.5 em-dash block targets —
///   see that test's own 49.6 note below.
/// - `record-260723-rif-itsis` — REVERT-TO-RAW: pronounPersonChange×1
///   ("it's"→"it"), contentWordIdentityChange×1 ("referring"→"refers"),
///   contentWordDeletion×1 ("to") revert 1 punctuationOrCasing comma
///   insert; AFTER = raw.
/// - `record-260724-j96-havingseeking` — REVERT-TO-RAW:
///   contentWordIdentityChange×3, contentWordInsertion×1,
///   pronounPersonChange×1, contentWordDeletion×2 revert a tense
///   substitute, a comma insert, a period-delete sentence merge and a
///   casing substitute; AFTER = raw.
/// - `record-260723-rif-wannato` — REVERT-TO-RAW: contentWordIdentityChange
///   ×1 ("wanna"→"want") reverts the accepted leading-dash delete
///   (punctuationOrCasing); AFTER = raw (leading "- " restored).
/// - `record-2026-08-30T04-54-30-157Z` — REVERT-TO-RAW, re-baselined a
///   SECOND time (see the 49.5 note above for its first re-baseline):
///   matches the live corpus row at ts `2026-08-30T04:54:30.157Z` in
///   `49.6-GATE-DIFF.md` §1 (contentWordDeletion×2,
///   contentWordIdentityChange×2 revert punctuationOrCasing×5,
///   wordOrderRepair×1, functionWordInsertion×1; a self-contained
///   punctuationOrCasing comma survives, D-02). Under this file's
///   `TestSpellLexicon.allKnown` (every token counts as a known word,
///   unlike the live corpus's real OS checker) the "Resistancetraining"→
///   "Resistenztraining" substitute no longer qualifies as `nonWordRepair`
///   (its source is no longer "unknown" under an all-known lexicon), so it
///   is independently rejected too — AFTER = raw exactly for this record.
/// - `record-2026-07-29T03-47-35-149Z` — REVERT-TO-RAW: sentence 2
///   (contentWordIdentityChange×1 "matches"→"match", pronounDeleted×1
///   "it") reverts 1 comma insert; sentence 3 (contentWordInsertion×7:
///   "down" plus the stray, correctly-rejected-both-ways
///   `</corrected_text>` tag) reverts the "only" word-order move and 2
///   comma inserts; sentence 1's em-dash insert is untouched (no trigger
///   there). AFTER = raw for sentences 2 and 3.
///
/// The other 8 golden entries stayed byte-identical this phase.
@MainActor
final class EditGuardRunTokenizationReplayTests: XCTestCase {

    /// Copied verbatim from `EditGuardMaterializeInvariantTests` so the
    /// golden is captured under identical conditions (same entry point, same
    /// lexicon).
    private func guardOut(_ baseline: String, _ candidate: String, _ language: String) -> String {
        EditGuard.apply(rulesCleaned: baseline, llmOutput: candidate, language: language, lexicon: TestSpellLexicon.allKnown).text
    }

    // MARK: - Golden

    /// POST-FIX values. Values are ANONYMIZED production records from
    /// `EditGuardFixtures.productionRecords` — no live dictation text is
    /// committed.
    private static let preChangeGolden: [String: String] = [
        "record-2026-08-30T04-54-30-157Z":
            "Also ich möchte, dass du noch einmal genau recherchierst und mir einen Nahrungsergänzungsmittel sowie beispielhaften Trainingsplan zusammenstellst. Wie viel Resistancetraining braucht es wirklich? Ich bin zum Beispiel auch kein Fitnessstudio-Gänger. Ich finde das zu langweilig und, wenn nicht unbedingt notwendig dann möchte ich auch nicht einfach nur 30 minuten resistance training machen normalerweise mache ich so fünf minuten pro tag mit dem eigenen körpergewicht oder mit dem Tension Strap. Ich bin aber offen für Veränderung.",
        "record-2026-08-24T04-00-00-733Z":
            "please look for news from this year and if possible as recently as possible about failed or delayed projects either in government in Switzerland on either of the three levels of government, meaning federal, cantonal and municipal, as well as from the social sector.",
        "record-260831-gd9-in-clawed":
            "Check also in.clawed directory for the file.",
        "record-2026-07-29T03-47-35-149Z":
            "So, help me adjust the feedback email—or however it's labeled. So it matches these new states because I haven't sent it yet. I only was in contact with Pearcom support and now I want to go that separate lane as well because this is not acceptable anymore.",
        "record-260724-j96-checkfact":
            "No, the corporate style-guide convention is not about writing something like \"situation\" or \"assessment\" in capital letters. It's about geographic names and also entities, I believe. But fact check that.",
        "record-260724-j96-havingseeking":
            "The title at the top meaning when was this report generated or what time period is this referring to can be a little bit more prominent. So as not to having to seek what time period this report is about.",
        "record-260723-rif-offorheartrate":
            "She wants to be able to click in a dial and move the finger around to see individual data points. Like what was the value at any given time of heartrate for instance and then also along the way lost the info about the workouts so when I click on the workouts a small pop-up should show up",
        "record-260723-rif-itsis":
            "Also in the current layout it's unclear to what time period this report is referring to.",
        "record-260723-rif-wannato":
            "- Yes, we can go ahead, but first I wanna clear the context window because it's already 75% full.",
        "record-260723-rif-rightsolostquestionmark":
            "For the sections, what kind of structure are you following now? Because I would like to have a clear structure that's also kind of visible, right? So facts and figures first, then development possibilities, likelihoods and whatnot, confidentiality.",
        "record-260723-rif-esundzwardanglinges":
            "Und dann gibt es, ich glaube es ist eine Folie mit einer Tabelle, doch hierfür würde ich tatsächlich ein anderes Folienlayout nehmen. Und zwar eines, das oberhalb der Tabelle nicht noch einen Text enthält, weil jetzt in diesem Fall wurde auch tatsächlich nichts oben hingeschrieben und damit bleibt ein grosser Anteil des Platzes auf der Folie ungenutzt.",
        "record-2026-09-01T17-17-59-197Z":
            "And as for 999.2, what's going through my mind when I read your explanation of what this is about? I mean, I see two possible points of contact where this kind of enrollment and also discernment of how well a user of Dicticus can pronounce certain words. That is, at first, maybe at the ASR level or right after, kind of more deterministically, which has its own drawbacks, I assume, because it's not clear signs here. And then at AI Cleanup level, where we would give the LLM the context of, oh, this user is actually struggling with breathing and breathing, meaning we should make sure that whenever these words appear, that it actually makes sense within the context of the sentence that it's placed in.",
        // introduced by 49.5, therefore post-fix by construction (no pre-49.5 value exists)
        "record-495-invented-ellipsis-hesitation-en":
            "I need to follow up with Haldenwerk Informatik regarding the rollout schedule.",
        // introduced by 49.5, therefore post-fix by construction (no pre-49.5 value exists)
        "record-495-invented-ellipsis-inplace-de":
            "Ich bin mir nicht sicher. Die Firnwald Logistik AG hat noch nicht geantwortet.",
        // introduced by 49.5, therefore post-fix by construction (no pre-49.5 value exists)
        "record-495-invented-exclamation-run-de":
            "Das ist grossartig! Haldenwerk Informatik wird begeistert sein.",
    ]

    // MARK: - Replay

    /// Zero-allowance, permanent byte-identity lock: EVERY golden entry is a
    /// hard equality check. No improvement allowance exists any more — the
    /// two records that legitimately changed during this phase (plus the
    /// third, `record-2026-08-30`, per its own doc comment above) were
    /// re-baselined to their post-fix values, so a future regression on any
    /// of them fails here exactly like any other record would.
    func testProductionRecordsMatchPreChangeGolden_orImprove() {
        XCTAssertEqual(Self.preChangeGolden.count, EditGuardFixtures.productionRecords.count,
                       "the golden must cover every production record")

        var checkedCount = 0

        for (id, golden) in Self.preChangeGolden {
            guard let record = EditGuardFixtures.productionRecords.first(where: { $0.id == id }) else {
                XCTFail("golden references unknown production record id \(id)")
                continue
            }

            let out = guardOut(record.baseline, record.candidate, record.language)
            XCTAssertEqual(out, golden, "byte-identity regression on \(id)")
            checkedCount += 1
        }

        print("[eg495 replay] checkedCount=\(checkedCount) (of \(Self.preChangeGolden.count) golden entries)")
        XCTAssertGreaterThan(checkedCount, 0, "the replay must not be vacuous")
    }

    /// Keeps the two designated defects' exact-string acceptance criteria
    /// alive INDEPENDENTLY of `preChangeGolden` — so a future re-baseline of
    /// the golden (e.g. after a legitimate, unrelated change to one of these
    /// two records) can never quietly re-legalize either defect by simply
    /// updating its stored golden value.
    ///
    /// 49.6 note on block 2 (em-dash): `record-2026-08-24T04-00-00-733Z`'s
    /// output changed again this phase — its raw sentence also carries an
    /// independent content-bearing rejection (`contentWordDeletion`×3,
    /// `contentWordIdentityChange`×2; see `49.6-GATE-DIFF.md` §1, ts
    /// `2026-08-24T04:00:00.733Z`, labelled REVERT-TO-RAW), so
    /// `applySentenceCoupledRevert` now legitimately reverts the WHOLE
    /// sentence — including the LLM's otherwise-correctly-bound em-dash —
    /// to raw. The positive "well-formed em-dash ships" claim can no
    /// longer hold for this specific record; only the negative
    /// "stray-space defect never returns" guarantee survives below,
    /// unconditionally.
    func testKnownDefectStringsNeverReturn() {
        if let r = EditGuardFixtures.productionRecords.first(where: { $0.id == "record-2026-09-01T17-17-59-197Z" }) {
            let out = guardOut(r.baseline, r.candidate, r.language)
            XCTAssertFalse(out.contains("possible.points"),
                           "the restored ellipsis remnant must not glue to the following word")
            XCTAssertTrue(out.contains("two possible points of contact"),
                          "the phrase must read as one of the two inputs actually wrote it")
        } else {
            XCTFail("record-2026-09-01T17-17-59-197Z missing from EditGuardFixtures.productionRecords")
        }

        if let r = EditGuardFixtures.productionRecords.first(where: { $0.id == "record-2026-08-24T04-00-00-733Z" }) {
            let out = guardOut(r.baseline, r.candidate, r.language)
            XCTAssertFalse(out.contains("municipal —"),
                           "no stray space may survive in front of the em-dash")
        } else {
            XCTFail("record-2026-08-24T04-00-00-733Z missing from EditGuardFixtures.productionRecords")
        }
    }

    /// 49.6 D-14 third block — extends `testKnownDefectStringsNeverReturn`
    /// (above) with this phase's synthetic defect strings, pinned
    /// independently of `preChangeGolden` (same discipline as the two 49.5
    /// blocks). Each pair is copied inline from
    /// `EditGuardCoupledRevertTests.swift` /
    /// `EditGuardClassifierRuleTests.swift` (D-12: invented sentences, no
    /// live dictation text) with the exact substring that identified the
    /// defect in that fixture's RED run (`49.6-01-SUMMARY.md` /
    /// `49.6-03-SUMMARY.md`). Kept as a separate test function (not more
    /// code appended to `testKnownDefectStringsNeverReturn` itself) so a
    /// single assertion failure in either block reports independently.
    ///
    /// `testD09_polarityKeinemToEinem_RED` is intentionally NOT pinned
    /// here: its RED was a rejectClass LABEL mismatch
    /// (`contentWordIdentityChange` vs `negationChange`) with IDENTICAL
    /// output text pre- and post-fix — there is no defect substring to pin
    /// against a text regression that never occurred. The label itself is
    /// already pinned directly by
    /// `EditGuardClassifierRuleTests.testD09_polarityKeinemToEinem_RED`.
    func testKnownDefectStringsNeverReturn_49_6() {
        // Shape A (08-30:16 shape): the accepted "Der"->"Den" function
        // substitute must never ship alongside its rejected "denke"
        // partner in the same sentence.
        XCTAssertFalse(
            guardOut("Der Bericht denke ich morgen an die Firnwald Logistik AG",
                      "Den Bericht schicke ich morgen an die Firnwald Logistik AG.",
                      "de").contains("Den Bericht denke ich"),
            "the uncoupled function-substitute must not ship with a rejected content-substitute in the same sentence")

        // Shape B (08-20:10 shape): the accepted pronoun move must never
        // ship without its rejected verb-insert partner — a verbless
        // inverted clause.
        XCTAssertFalse(
            guardOut("Also du kannst Berichte und im Englischen Reports.",
                      "Also kannst du Berichte und im Englischen Reports schreiben.",
                      "de").contains("kannst du Berichte"),
            "the verb-second move must not ship without its coupled, rejected verb insert")

        // Shape C (08-30:27 shape): the accepted "dass" subordinator (with
        // its casing promotion) must never ship without the rejected
        // verb-final partner it needs.
        XCTAssertFalse(
            guardOut("man sagt beim Schwimmen etwa 70 Prozent der Muskeln beansprucht",
                      "Man sagt, dass beim Schwimmen etwa 70 Prozent der Muskeln beansprucht werden.",
                      "de").contains("Man sagt, dass beim Schwimmen"),
            "the subordinator insert + casing promotion must not ship without its rejected verb-final partner")

        // Shape D (08-20:21 shape): the accepted relative pronoun + comma
        // must never ship without the rejected clause-closing verb insert
        // they depend on — a dangling relative clause.
        XCTAssertFalse(
            guardOut("Es nervt mich ehrlich gesagt schon seit Wochen dieses Banner jetzt kaufen",
                      "Es nervt mich ehrlich gesagt schon seit Wochen dieses Banner, das jetzt kaufen anzeigt.",
                      "de").contains("Banner, das jetzt kaufen"),
            "the relative pronoun + comma must not ship without its rejected clause-closing verb insert")

        // Shape E (08-20:13 shape): the pause-split period delete must
        // never ship without its compensating comma — the "Erfahrung dass
        // ich" run-on defect (period lost, no comma).
        XCTAssertFalse(
            guardOut("Mir fehlt dafür die Zeit oder Erfahrung. dass ich das allein schaffe glaube ich nicht.",
                      "Mir fehlt dafür die Zeit oder Kapazität dass ich das allein schaffe, glaube ich nicht.",
                      "de").contains("Erfahrung dass ich"),
            "the pause-split period must not be deleted without its compensating comma")

        // Shape F (09-03:25 shape): the sentence-initial casing accept
        // must never promote a dropout fragment whose own rewrite was
        // rejected.
        XCTAssertFalse(
            guardOut("Das Datum ist abgelaufen. nicht stimmen kann das. Ist das ein Fehler?",
                      "Das Datum ist abgelaufen. Nicht stimmen kann das nicht sein. Ist das ein Fehler?",
                      "de").contains("abgelaufen. Nicht stimmen"),
            "the casing accept must not promote a dropout fragment whose rewrite was rejected")

        // Shape G (far-repair accepted-cost case): a correct verb-second
        // move must never ship alone when a rejected content substitute
        // shares its raw sentence — the whole sentence must fully revert,
        // not partially resolve.
        XCTAssertFalse(
            guardOut("Gestern ich habe den Bericht an die Agentur Haldenwerk geschickt weil der Termin knapp war",
                      "Gestern habe ich den Bericht an die Agentur Haldenwerk gesendet, weil der Termin knapp war.",
                      "de").contains("Gestern habe ich den Bericht"),
            "an accepted far-repair move must not ship alone; the whole raw sentence must revert")

        // D-09 substitute (testD09_substituteAndToOr_RED shape): a
        // coordinator swap must never ship — it flips the logical relation
        // between clauses.
        XCTAssertFalse(
            guardOut("check for logic and necessity", "check for logic or necessity", "en")
                .contains("logic or necessity"),
            "a coordinator substitute must not ship as content-bearing")

        // D-09 substitute (testD09_substituteKeinToNicht_RED shape): a
        // negator-to-negator swap must never ship.
        XCTAssertFalse(
            guardOut("Zucker esse ich kein und Salz auch nicht", "Zucker esse ich nicht und Salz auch nicht", "de")
                .contains("Zucker esse ich nicht und"),
            "a negator-to-negator substitute must not ship as content-bearing")

        // D-09 insert (testD09_insertAnd_RED shape): an inserted
        // coordinator must never ship — it asserts a relation the speaker
        // never said.
        XCTAssertFalse(
            guardOut("we test the parser the linter", "we test the parser and the linter", "en")
                .contains("the parser and the linter"),
            "an inserted coordinator must not ship as content-bearing")

        // D-09 insert (testD09_insertSondern_RED shape): an inserted
        // negator-coordinator must never ship, and the coupled comma
        // insert in the same sentence must revert with it.
        XCTAssertFalse(
            guardOut("nicht heute morgen", "nicht heute, sondern morgen", "de")
                .contains("heute, sondern morgen"),
            "an inserted 'sondern' must not ship as content-bearing, nor its coupled comma")

        // D-11 (testD11_hyphenInsertWordThenDigit_RED shape): a hyphen
        // fused between a word and a digit must never ship — it changes
        // an identifier.
        XCTAssertFalse(
            guardOut("we compared it against Fable 5 yesterday", "we compared it against Fable-5 yesterday", "en")
                .contains("Fable-5"),
            "a word-then-digit hyphen insert must not ship as prosodic punctuation")
    }

    // MARK: - D-04: per-sentence divergence gate window

    /// Mirrors `EditGuard.classifyInsert`'s per-sentence divergence gate
    /// filter (`EditGuard.swift` ~line 957) — a later phase extracts it into a
    /// helper and repoints this test at it.
    func testPerSentenceDivergenceGateWindowIsOneSentence_D04() {
        let baseline = EditGuardTokenizer.tokenize("Ich weiss nicht... Vielleicht spaeter melde ich mich noch einmal bei dir")
        let candidate = EditGuardTokenizer.tokenize("Ich weiss nicht. Vielleicht spaeter melde ich mich noch einmal bei dir.")

        XCTAssertTrue(baseline.contains { $0.text == "..." }, "the ellipsis must be ONE run token")

        guard let b = candidate.first(where: { $0.text == "Vielleicht" }) else {
            XCTFail("the candidate tokenization must contain a 'Vielleicht' token")
            return
        }

        XCTAssertEqual(
            EditGuardTokenizer.rebuild(EditGuard.candidateSentenceWindow(candidate, sentenceIndex: b.sentenceIndex)),
            "Vielleicht spaeter melde ich mich noch einmal bei dir."
        )

        XCTAssertEqual(baseline.first(where: { $0.text == "Vielleicht" })?.sentenceIndex,
                       candidate.first(where: { $0.text == "Vielleicht" })?.sentenceIndex)
    }
}
