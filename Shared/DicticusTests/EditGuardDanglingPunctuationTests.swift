import XCTest
@testable import Dicticus

/// Regression net for the dangling-double-punctuation guard bug (2026-07-15, real debug log).
/// When the LLM splits a run-on (comma→period) AND adds a comma elsewhere, EditDiff's LCS paired
/// the identical commas across the clause boundary and rebuild emitted ` , .`. Backstopped by
/// EditGuard.collapseDanglingPunctuation. The first two cases are actual corpus occurrences.
@MainActor
final class EditGuardDanglingPunctuationTests: XCTestCase {

    private func guardOut(_ baseline: String, _ llm: String, _ lang: String = "en") -> String {
        EditGuard.apply(rulesCleaned: baseline, llmOutput: llm, language: lang, lexicon: TestSpellLexicon.allKnown).text
    }

    /// Rejects a dangling doubled mark in EITHER form: the space-separated
    /// shape collapseDanglingPunctuation targets (" , .") AND the no-space
    /// shape (",.") that bindPunctuationLeft would otherwise produce by
    /// stripping the interior space before the collapse pass runs (the
    /// 2026-07-19 regression: "guide . ," -> "guide.," survived because the
    /// collapse needs the space to fire). These fixture inputs contain no
    /// legitimate abbreviation ("etc.,"), so any adjacent terminal+separator
    /// here is an artifact.
    private func assertNoDoubledPunct(_ out: String, _ file: StaticString = #file, _ line: UInt = #line) {
        for bad in [",.", ".,", ",?", ".?", ",;", ",:", ".;", " , .", " . ,", ". ,", ", ."] {
            XCTAssertFalse(out.contains(bad), "doubled punctuation '\(bad)' in: \(out)", file: file, line: line)
        }
    }

    func testNoDanglingPunctuation_workedSo() {
        let out = guardOut("Okay, that worked, so where does this leave us?",
                           "Okay, that worked. So, where does this leave us?")
        assertNoDoubledPunct(out)
    }

    func testNoDanglingPunctuation_connectedOtherwise() {
        let out = guardOut("make sure that it is connected, otherwise one, two and three.",
                           "make sure it is connected. Otherwise, one, two, and three.")
        assertNoDoubledPunct(out)
    }

    /// Regression for the bindPunctuationLeft x collapseDanglingPunctuation
    /// interaction (2026-07-19): a rejected sentence-final period substitute
    /// leaves a period + the candidate comma adjacent; the final output must
    /// not ship "guide.," / "guide . ,".
    func testNoDanglingPunctuation_userGuide() {
        let out = guardOut("It should just be a general user guide. Explaining the tech stack.",
                           "It should just be a general user guide, explaining the tech stack.")
        assertNoDoubledPunct(out)
    }

    func testCollapseUnit() {
        // Terminal beats non-terminal regardless of order; interior space is required.
        XCTAssertEqual(EditGuard.collapseDanglingPunctuation("worked , . So"), "worked. So")
        XCTAssertEqual(EditGuard.collapseDanglingPunctuation("guide . , explaining"), "guide. explaining")
        XCTAssertEqual(EditGuard.collapseDanglingPunctuation("that , ; maybe"), "that; maybe")
        // A run of three collapses fully; the terminal period wins over both comma and semicolon.
        XCTAssertEqual(EditGuard.collapseDanglingPunctuation("x , . ; y"), "x. y")
        // Legitimate no-interior-space sequences are untouched.
        XCTAssertEqual(EditGuard.collapseDanglingPunctuation("wait... really?!"), "wait... really?!")
        XCTAssertEqual(EditGuard.collapseDanglingPunctuation("see etc., and more"), "see etc., and more")
        XCTAssertEqual(EditGuard.collapseDanglingPunctuation("no change here."), "no change here.")
        // Deliberate non-behavior (260830-dc4): the unspaced mixed-source glued pair is NOT this
        // pass's job — it is structurally invisible to a string-level regex requiring interior
        // whitespace, and is owned upstream by `collapseMixedProvenancePunctuationRuns` at the
        // token level. This locks that this string-level pass was never, and is still not, the
        // owner of the unspaced case.
        XCTAssertEqual(EditGuard.collapseDanglingPunctuation("und., wenn"), "und., wenn")
    }

    // MARK: - Space-before-single-mark (2026-07-17 root-cause fix: bindPunctuationLeft)
    //
    // Root cause (distinct from the doubled-mark shape above): a KEPT/restored
    // token's trailing was calibrated against its SOURCE neighbor. When the
    // guard rejects an edit and restores a single punctuation mark in place of
    // a candidate word, the preceding word keeps the space it had before that
    // candidate word, producing "word , next". `collapseDanglingPunctuation`
    // only fires on TWO adjacent marks with interior whitespace, so it cannot
    // catch this single-mark shape.

    func testNoSpaceBeforeSingleMark_substituteRejection_en() {
        let out = guardOut(
            "Check the PDF, Word, Excel, PowerPoint files.",
            "Check the PDF, Word, Excel and PowerPoint files."
        )
        XCTAssertFalse(out.contains(" ,"), out)
    }

    func testNoSpaceBeforeSingleMark_excel_de() {
        let out = guardOut(
            "So dass MüraX mit PDF, Word, Excel, PowerPoint arbeiten kann.",
            "So dass MüraX mit PDF, Word, Excel und PowerPoint arbeiten kann.",
            "de"
        )
        XCTAssertFalse(out.contains(" ,"), out)
        XCTAssertTrue(out.contains("Excel, PowerPoint"), out)
    }

    func testNoSpaceBeforeSingleMark_austausch_de() {
        let out = guardOut(
            "Wir machen das für den internen Austausch, für die interne Auseinandersetzung.",
            "Wir machen das für den internen Austausch und die interne Auseinandersetzung.",
            "de"
        )
        XCTAssertFalse(out.contains(" ,"), out)
    }

    func testNoSpaceBeforePeriod_substituteRejection_en() {
        let out = guardOut(
            "We finished the sprint. Great work everyone.",
            "We finished the sprint however great work everyone."
        )
        XCTAssertFalse(out.contains(" ."), out)
    }

    func testNoSpaceBeforeQuestionMark_substituteRejection_en() {
        let out = guardOut(
            "Are you ready? Let's begin.",
            "Are you ready meanwhile let's begin."
        )
        XCTAssertFalse(out.contains(" ?"), out)
    }

    func testNoHarm_cleanMultiPunctBaseline_idempotent() {
        let baseline = "Okay, so first: check the PDF, then the Word doc, and finally the Excel sheet."
        let out = guardOut(baseline, baseline)
        XCTAssertFalse(out.contains(" ,"), out)
        XCTAssertFalse(out.contains(" ."), out)
        XCTAssertFalse(out.contains(" ?"), out)
    }

    func testEllipsisUntouched() {
        let out = guardOut("Wait... really?", "Wait... really?")
        XCTAssertTrue(out.contains("Wait..."), out)
    }

    // MARK: - Mixed-provenance punctuation-run splice (quick task 260830-dc4)
    //
    // Regression net for `.planning/todos/pending/editguard-splices-worse-than-both-inputs.md`
    // (now resolved). Production record 2026-08-30T04:54:30.157Z, mode=aiCleanup, lang=de,
    // prompt_version=v-transcriptionist. Root cause (traced against the live record, not
    // re-derived here): the dictated ellipsis "und..." is split by `EditDiff` across three
    // separate edit kinds. One dot is paired as a `.move` against a textually-identical `.`
    // elsewhere in the stream; `classifyMove` rejects every punctuation move unconditionally,
    // so that dot is RESTORED at its baseline anchor immediately after "und". A second dot's
    // substitute to "," is ACCEPTED, rendering the candidate's comma at the immediately
    // following slot. The two adjacent tokens — one baseline-restored, one candidate-accepted
    // — glue into "und.," in the shipped output, a two-mark sequence present in NEITHER the
    // baseline ("und...") nor the candidate ("und,"). `collapseDanglingPunctuation` does not
    // catch this: its interior-space requirement is deliberate (protects "...", "?!", "etc.,")
    // and the restored dot's own baseline trailing is empty (it sat directly against another
    // dot in "und..."), so no space is ever produced for the string-level pass to match.
    //
    // The trailing product name ("Resistance Band") is swapped for a same-shape invented token
    // ("Tension Strap") per the project's fixture-anonymization rule (memory
    // `reference_dicticus_release_publish`) — everything else is common-noun German with no
    // identifiers and is kept VERBATIM, because the defect depends on the global token stream
    // (`EditDiff.pairMovesFirst` pairs punctuation moves stream-globally; changing token counts
    // or sentence boundaries elsewhere can silently stop the defect from reproducing). The swap
    // was re-verified post-hoc to still reproduce the glued pair.
    func testNoSplicedPunctuation_langweiligUnd_2026_08_30() {
        let baseline = "Also ich möchte, dass du noch einmal genau recherchierst und mir einen Nahrungsergänzungsmittel sowie beispielhaften Trainingsplan zusammenstellst. Wie viel Resistancetraining braucht es wirklich? Ich bin zum Beispiel auch kein Fitnessstudio-Gänger. Ich finde das zu langweilig und... wenn nicht unbedingt notwendig dann möchte ich auch nicht einfach nur 30 minuten resistance training machen normalerweise mache ich so fünf minuten pro tag mit dem eigenen körpergewicht oder mit dem Tension Strap. Ich bin aber offen für Veränderung."
        let candidate = "Ich möchte, dass du noch einmal genau recherchierst und mir ein Nahrungsergänzungsmittel sowie einen beispielhaften Trainingsplan zusammenstellst. Wie viel Resistenztraining braucht es wirklich? Ich bin zum Beispiel auch kein Fitnessstudio-Gänger. Ich finde das zu langweilig und, wenn nicht unbedingt notwendig, möchte ich auch nicht einfach nur 30 Minuten Resistenztraining machen. Normalerweise mache ich so fünf Minuten pro Tag mit dem eigenen Körpergewicht oder mit dem Tension Strap. Ich bin aber offen für Veränderung."

        let out = guardOut(baseline, candidate, "de")
        assertNoDoubledPunct(out)

        guard let range = out.range(of: "langweilig und") else {
            XCTFail("expected 'langweilig und' to survive in the output verbatim: \(out)")
            return
        }
        let after = out[range.upperBound...]
        let baselineForm = "... wenn"
        let candidateForm = ", wenn"
        XCTAssertTrue(
            after.hasPrefix(baselineForm) || after.hasPrefix(candidateForm),
            "span immediately after 'langweilig und' is neither the baseline's ellipsis nor " +
            "the candidate's comma — a neither-input splice: '\(after.prefix(24))' — full output: \(out)"
        )
    }

    /// Minimal single-sentence reduction of the record above. Attempted per plan Task 1's
    /// instruction to reduce and delete if it does not reproduce — verified (RED-confirmed
    /// before the fix landed) that this single defect-carrying sentence, isolated from the rest
    /// of the record, still reproduces: the same `.move`-pairing shape only needs two textually-
    /// identical baseline "." tokens to pair against each other, and this sentence's own
    /// ellipsis supplies both, so the reduction does not depend on any other sentence's
    /// punctuation. Kept alongside the full-record test because it isolates the defect from the
    /// record's unrelated edits (Nahrungsergänzungsmittel, Resistenztraining casing, etc.).
    func testNoSplicedPunctuation_langweiligUnd_minimalReduction() {
        let baseline = "Ich finde das zu langweilig und... wenn nicht unbedingt notwendig dann möchte ich auch nicht einfach nur 30 minuten resistance training machen normalerweise mache ich so fünf minuten pro tag mit dem eigenen körpergewicht oder mit dem Tension Strap."
        let candidate = "Ich finde das zu langweilig und, wenn nicht unbedingt notwendig, möchte ich auch nicht einfach nur 30 Minuten Resistenztraining machen. Normalerweise mache ich so fünf Minuten pro Tag mit dem eigenen Körpergewicht oder mit dem Tension Strap."

        let out = guardOut(baseline, candidate, "de")
        assertNoDoubledPunct(out)

        guard let range = out.range(of: "langweilig und") else {
            XCTFail("expected 'langweilig und' to survive in the output verbatim: \(out)")
            return
        }
        let after = out[range.upperBound...]
        let baselineForm = "... wenn"
        let candidateForm = ", wenn"
        XCTAssertTrue(
            after.hasPrefix(baselineForm) || after.hasPrefix(candidateForm),
            "span immediately after 'langweilig und' is neither the baseline's ellipsis nor " +
            "the candidate's comma — a neither-input splice: '\(after.prefix(24))' — full output: \(out)"
        )
    }

    // MARK: - Comma-dash adjacency (quick task 260831-ad8)
    //
    // `.planning/quick/260831-ap7-editguard-accept-policy-measurement/260831-ap7-REPORT.md`
    // Q1: 909 accepted punctuation inserts across 548 August aiCleanup records included 13
    // em-dash acceptances, 12 genuine improvements and one corruption — a comma immediately
    // followed by an em-dash. Production record 2026-08-24T04:00:00.733Z, mode=aiCleanup,
    // lang=en (`~/Library/Application Support/Dicticus/DebugRecordings/cleanup-2026-08-24.jsonl`):
    // baseline has a trailing comma after "municipal" (`"...municipal, as well..."`); candidate
    // drops that comma and joins the clause with an em-dash instead
    // (`"...municipal—as well..."`). `EditDiff` pairs the baseline comma against a DIFFERENT
    // candidate comma elsewhere in the sentence as a `.move`; `classifyMove` rejects every
    // punctuation move unconditionally, so the baseline comma is RESTORED at its own anchor
    // (immediately after "municipal"). The em-dash is a SEPARATE, independently accepted
    // `.insert` (D-06 prosodic-punctuation, `punctuationOrCasing`) landing at the very next slot.
    // Two-token punctuation run, ONE restored-baseline token + ONE accepted-candidate token —
    // this is the SAME mixed-provenance shape `collapseMixedProvenancePunctuationRuns` (quick
    // task 260830-dc4, "und.," defect) already owns.
    //
    // NON-REPRODUCTION FINDING: this record is dated 2026-08-24, six days BEFORE 260830-dc4's
    // fix landed (commit 01f5ee7, 2026-08-30). Replayed against the CURRENT `EditGuard` — after
    // that fix — the record no longer corrupts: `collapseMixedProvenancePunctuationRuns` already
    // detects this exact mixed-source 2-token run and keeps only the candidate-sourced em-dash,
    // dropping the restored comma. A corpus-wide sweep of the ENTIRE August corpus for
    // `[,;:]\s*[—–]` in `post_gate.text` found exactly this one hit, and no others postdating
    // 2026-08-30 — the defect class this quick task was scoped to fix was ALREADY fixed by
    // yesterday's commit; nothing in `EditGuard.swift` changes as a result of this task. This
    // test is a LOCKING regression test (not a RED-then-GREEN fix): it proves, by direct
    // execution against the exact live strings, that the fix already covers this shape, and
    // guards against a future regression re-opening it.
    func testNoCommaDashAdjacency_governmentLevels_2026_08_24() {
        let baseline = "please look for news from this year and if possible as recently as possible about failed or delayed projects either in government in Switzerland on either of the three levels of government, meaning federal, cantonal and municipal, as well as from the social sector."
        let candidate = "Please look for news from this year, as recently as possible, about failed or delayed projects in the government in Switzerland at either of the three levels of government—federal, cantonal, and municipal—as well as from the social sector."

        let out = guardOut(baseline, candidate, "en")
        assertNoDoubledPunct(out)
        for bad in [", —", ",—", "; —", ";—", ": —", ":—"] {
            XCTAssertFalse(out.contains(bad), "comma/semicolon/colon immediately adjacent to a dash in: \(out)")
        }
    }

    // MARK: - Accept-controls (260831-ad8): the 12 GENUINE em-dash insertions from the Q1
    // measurement must survive completely untouched. Two are reproduced here from their own
    // production records — proof that no comma-dash fix (had one been needed) could be allowed
    // to strip a legitimate em-dash pair, and that the "already fixed, no code change" finding
    // above is not masking a regression on the good cases.

    /// Production record 2026-08-23T04:48:09.394Z — a genuine parenthetical em-dash pair the
    /// LLM inserted around "or whatever you were addressing before". No baseline comma competes
    /// for either dash's slot, so this exercises the guard's ordinary D-06 insert-accept path,
    /// not the mixed-provenance collapse.
    func testAcceptControl_migrationEmDash_2026_08_23() {
        let baseline = "But of course this needs to be mapped out as well as planned really well beforehand. And then I reckon that not much is going on as of yet in the Superbase database. So migration or whatever you were addressing before shouldn't be too much of an issue."
        let candidate = "But of course, this needs to be mapped out as well as planned really well beforehand. And then, I reckon that not much is going on as of yet in the Superbase database. So, migration—or whatever you were addressing before—shouldn't be too much of an issue."

        let out = guardOut(baseline, candidate, "en")
        XCTAssertTrue(
            out.contains("migration—or whatever you were addressing before—shouldn't"),
            "genuine em-dash parenthetical must survive verbatim: \(out)"
        )
    }

    /// Production record 2026-08-23T07:53:42.449Z — a genuine em-dash pair around
    /// "or, contrarily, getting worse", with a comma landing INSIDE the dash pair (not adjacent
    /// to either dash) — the shape this fix must not disturb even though it involves both a
    /// comma and dashes in the same short span.
    func testAcceptControl_contrarilyEmDash_2026_08_23() {
        let baseline = "I would say option 1 here and to your previous question another thought that crossed my mind if your own progress or data isn't deleted by yourself when you reset and you now have actually some kind of let's say track record or version you could see how you're improving or Contrarily getting worse over time. So not just how you're doing currently, but also in relation to your previous attempts. Because I can see this being something that you repeat yearly, for instance."
        let candidate = "I would say option 1 here. To your previous question, another thought that crossed my mind: if your own progress or data isn't deleted by yourself when you reset, and you now have actually some kind of track record or version, you could see how you're improving—or, contrarily, getting worse—over time. So not just how you're doing currently, but also in relation to your previous attempts. Because I can see this being something that you repeat yearly, for instance."

        let out = guardOut(baseline, candidate, "en")
        XCTAssertTrue(
            out.contains("improving—or, contrarily, getting worse—over time"),
            "genuine em-dash pair with an interior comma must survive verbatim: \(out)"
        )
    }

    /// Corpus-wide punctuation-run provenance invariant (quick task 260830-dc4, Task 3): for
    /// every fixture in `EditGuardFixtures.all` (87 fixtures, 50 German), plus the 2026-08-30
    /// production record above, every maximal punctuation-mark run of length >= 2 in the guard's
    /// output must occur as a punctuation run in EITHER the fixture's baseline OR its candidate.
    /// A run present in neither is the character-level-interleaving defect this quick task fixes.
    ///
    /// SCOPE (documented as a decision, not a convenience — see the plan's `<diagnosis>` "Why the
    /// invariant is scoped to punctuation runs, not to every span"): word-level interleaving is
    /// already prevented by `multisetInvariantHolds`, which excludes punctuation entirely — this
    /// sweep closes exactly that hole. It does NOT assert "every span equals one full input",
    /// which is false by design for `EditGuard` (D-01: the guard CONSTRUCTS output from baseline
    /// plus individually-approved edits, so any span with one accepted and one rejected edit
    /// equals neither input on purpose).
    ///
    /// Single-mark runs are deliberately not checked: a lone mark cannot be an interleaving of two
    /// sources, and checking it would flag ordinary punctuation normalisation (e.g. a baseline "."
    /// legitimately becoming a candidate "," is a length-1-vs-length-1 substitution, not a run).
    ///
    /// Non-vacuity (memory `feedback_gate_blind_to_firing_path`: this project has shipped a gate
    /// that reported "0 corruptions" against a corpus with 0 true positives): the sweep counts how
    /// many fixtures actually produced at least one length>=2 output run and asserts that count is
    /// greater than zero, so a corpus that never exercises this shape cannot pass vacuously.
    func testPunctuationRunsAreSingleSourced_acrossFixtureCorpus() {
        // Extracts every maximal run of 2+ adjacent punctuation-kind tokens from `text`, using
        // EditGuard's own tokenizer so "adjacent" matches the guard's own definition (interior
        // horizontal whitespace between two punctuation tokens does not break a run — the
        // tokenizer stores it as the PRECEDING token's `trailing`, not as a separate token, so
        // consecutive array entries are still "adjacent" regardless of interior spacing). Each run
        // is returned as its concatenated mark text (token `.text` never includes whitespace, so
        // this is already whitespace-free by construction).
        func punctuationRuns(_ text: String) -> [String] {
            let tokens = EditGuardTokenizer.tokenize(text)
            var runs: [String] = []
            var current = ""
            var count = 0
            for t in tokens {
                if t.kind == .punctuation {
                    current += t.text
                    count += 1
                } else {
                    if count >= 2 { runs.append(current) }
                    current = ""
                    count = 0
                }
            }
            if count >= 2 { runs.append(current) }
            return runs
        }

        struct SweepCase { let id: String; let language: String; let baseline: String; let candidate: String }

        // The two fixtures the plan flagged as most likely to interact (both combine pause-dot
        // runs with punctuation moves) were checked individually and are NOT exempted:
        // fx-mov-punct-en-goodshine-fullrecord-spuriousmove was a genuine second instance of this
        // defect (fixed in Task 2, its expectedText corrected — see EditGuardFixtures.swift's
        // updated note) and now passes this sweep with its corrected output;
        // fx-sub-punct-en-goodshine-pausedots-emdash also passes without modification. No fixture
        // exemption was needed.
        let exemptIDs: Set<String> = []

        var cases: [SweepCase] = EditGuardFixtures.all.map {
            SweepCase(id: $0.id, language: $0.language, baseline: $0.baseline, candidate: $0.candidate)
        }
        cases.append(SweepCase(
            id: "record-2026-08-30T04-54-30-157Z",
            language: "de",
            baseline: "Also ich möchte, dass du noch einmal genau recherchierst und mir einen Nahrungsergänzungsmittel sowie beispielhaften Trainingsplan zusammenstellst. Wie viel Resistancetraining braucht es wirklich? Ich bin zum Beispiel auch kein Fitnessstudio-Gänger. Ich finde das zu langweilig und... wenn nicht unbedingt notwendig dann möchte ich auch nicht einfach nur 30 minuten resistance training machen normalerweise mache ich so fünf minuten pro tag mit dem eigenen körpergewicht oder mit dem Tension Strap. Ich bin aber offen für Veränderung.",
            candidate: "Ich möchte, dass du noch einmal genau recherchierst und mir ein Nahrungsergänzungsmittel sowie einen beispielhaften Trainingsplan zusammenstellst. Wie viel Resistenztraining braucht es wirklich? Ich bin zum Beispiel auch kein Fitnessstudio-Gänger. Ich finde das zu langweilig und, wenn nicht unbedingt notwendig, möchte ich auch nicht einfach nur 30 Minuten Resistenztraining machen. Normalerweise mache ich so fünf Minuten pro Tag mit dem eigenen Körpergewicht oder mit dem Tension Strap. Ich bin aber offen für Veränderung."
        ))
        // Quick task 260831-ad8: the comma-dash adjacency record — widens this sweep's corpus so
        // the mixed-source restored-comma / accepted-dash shape stays covered by the general
        // invariant, not only by its own dedicated test above.
        cases.append(SweepCase(
            id: "record-2026-08-24T04-00-00-733Z",
            language: "en",
            baseline: "please look for news from this year and if possible as recently as possible about failed or delayed projects either in government in Switzerland on either of the three levels of government, meaning federal, cantonal and municipal, as well as from the social sector.",
            candidate: "Please look for news from this year, as recently as possible, about failed or delayed projects in the government in Switzerland at either of the three levels of government—federal, cantonal, and municipal—as well as from the social sector."
        ))

        var nonVacuousCount = 0
        for c in cases where !exemptIDs.contains(c.id) {
            let out = EditGuard.apply(rulesCleaned: c.baseline, llmOutput: c.candidate, language: c.language, lexicon: TestSpellLexicon.allKnown).text
            let outputRuns = punctuationRuns(out)
            guard !outputRuns.isEmpty else { continue }
            nonVacuousCount += 1
            let baselineRuns = Set(punctuationRuns(c.baseline))
            let candidateRuns = Set(punctuationRuns(c.candidate))
            for run in outputRuns {
                XCTAssertTrue(
                    baselineRuns.contains(run) || candidateRuns.contains(run),
                    "[\(c.id)] punctuation run '\(run)' in the guard's output occurs in NEITHER " +
                    "the baseline nor the candidate — a character-level interleaving of both " +
                    "sources. baseline runs: \(baselineRuns.sorted()), candidate runs: " +
                    "\(candidateRuns.sorted()) — full output: \(out)"
                )
            }
        }

        print("[260830-dc4 sweep] \(nonVacuousCount)/\(cases.count) cases produced a length>=2 output punctuation run")
        XCTAssertGreaterThan(
            nonVacuousCount, 0,
            "corpus sweep produced ZERO fixtures with a length>=2 output punctuation run — the " +
            "invariant above never fired on anything, so it is VACUOUS (memory " +
            "feedback_gate_blind_to_firing_path: this project has shipped exactly this kind of " +
            "blind gate before). Widen the corpus before trusting this test."
        )
    }

    // MARK: - Restored-punctuation fabricated-space splice (quick task 260831-gd9)
    //
    // Regression net for `.planning/quick/260831-gd9-glued-dot-spacing/`. Live record
    // `cleanup-2026-08-31.jsonl` @ 16:29:29.370Z, mode=aiCleanup, lang=en (context genericized
    // per the project's fixture-anonymization rule — the defect depends only on the glued
    // "in.clawed" shape, not on any surrounding identifier). The user dictated a directory
    // reference; ASR produced it glued to a preceding period with ZERO separator on either
    // side ("in.clawed", baseline trailing "" before AND after the dot). The LLM candidate
    // deleted the dot and inserted "the" ("in the clawed"). `EditDiff` pairs the baseline "."
    // against the candidate word "the" as a `.substitute`; `classifySubstitute` correctly
    // REJECTS it (`contentWordIdentityChange` — a content word can never replace punctuation),
    // and the baseline "." is restored at its own anchor. The restoration itself was correct;
    // only its RENDERED trailing whitespace was wrong — `materialize`'s rejected-`.substitute`
    // branch took the CANDIDATE's trailing (the space after "the") instead of the restored
    // token's OWN baseline trailing (empty), producing "in. clawed" — a fabricated space
    // present in NEITHER input. `collapseDanglingPunctuation` cannot catch this: it is a
    // single restored mark, not a doubled pair, so there is no second mark for its interior-
    // space-between-two-marks pattern to match against.
    //
    // This is the MIRROR of quick task 260801-9n7
    // (`testRestoredTerminalPunctuation_keepsInterSentenceSpace_labeledSo`,
    // EditGuardMergeAtomicityTests.swift): 9n7 found a restored mark inheriting an EMPTY
    // candidate trailing when its own baseline trailing was a genuine separator (dropping a
    // needed space, "labeled.So"); gd9 found the same mechanism failing the OTHER way — a
    // restored mark inheriting a NON-EMPTY candidate trailing when its own baseline trailing
    // was empty (fabricating a space that was never there, "in. clawed"). Both directions are
    // now covered by one rule: a restored punctuation token always renders with its own
    // baseline trailing, never the candidate's.
    func testNoFabricatedSpace_restoredDotBeforeGluedWord_260831gd9() {
        let baseline = "Check also in.clawed directory for the file."
        let candidate = "Check also in the clawed directory for the file."
        let out = guardOut(baseline, candidate, "en")
        XCTAssertTrue(
            out.contains("in.clawed directory"),
            "restored dot must render with its own (empty) baseline trailing, not a fabricated space: \(out)"
        )
        XCTAssertFalse(
            out.contains("in. clawed"),
            "restored dot must not carry the candidate's trailing space: \(out)"
        )
    }

    /// Accept-control (260831-gd9): a GENUINE end-of-sentence period the LLM inserts where no
    /// baseline mark competes for the slot — an ordinary ACCEPTED `.insert`, never touching the
    /// rejected-`.substitute` restore branch this quick task changed — must still get its space
    /// and, once `TextProcessingService.applyFinalCapitalization` runs (the guard's own
    /// downstream consumer, Step 3a.6), the next sentence must still capitalize. Proves the fix
    /// is scoped to the restore path and does not touch accepted-insert rendering.
    func testAcceptControl_genuineAcceptedPeriod_keepsSpaceAndCapitalizesDownstream_260831gd9() {
        let baseline = "we finished the sprint great work everyone"
        let candidate = "We finished the sprint. Great work everyone."
        let out = guardOut(baseline, candidate, "en")
        XCTAssertTrue(out.contains("sprint. "), "genuine accepted period insert must keep its space: \(out)")
        let capitalized = TextProcessingService.applyFinalCapitalization(out, language: "en")
        XCTAssertTrue(
            capitalized.contains("sprint. Great work"),
            "next sentence must capitalize downstream of a genuine accepted period: \(capitalized)"
        )
    }

    // MARK: - Quick task 260901-qyi: lone restored ellipsis remnant

    /// LIVE production bug, corpus 2026-09-01T17:17:59.197Z
    /// (`EditGuardFixtures.productionRecords`, record
    /// `record-2026-09-01T17-17-59-197Z`). Baseline carries a hesitation
    /// ellipsis (three `.` tokens) between "possible" and "points"; the LLM
    /// correctly deleted the whole ellipsis. `EditDiff` pairs one of the
    /// three baseline dots against an unrelated candidate period (elsewhere
    /// in the sentence) as a REJECTED `.move`; the other two dots are
    /// independently accepted deletes. The rejected move's dot is restored
    /// via `restorationTargets` with its own (empty, mid-ellipsis) baseline
    /// trailing — correct in isolation — but it is now the LONE surviving
    /// member of what was a 3-mark baseline run, so
    /// `collapseMixedProvenancePunctuationRuns`'s mixed-run pass (built for
    /// runs of length >= 2) passes it straight through untouched, and
    /// `bindPunctuationLeft` then clears "possible"'s trailing too (its
    /// own ellipsis guard requires the next TWO tokens to still be `.`,
    /// which they no longer are) — gluing the mark on both sides. This is
    /// the fifth member of the recurring "neither source" defect family
    /// (260801-9n7, 260830-dc4, 260831-ad8, 260831-gd9): a shape all four
    /// prior fixes are individually correct about but structurally blind to
    /// in combination. Fixed by a new arm in
    /// `collapseMixedProvenancePunctuationRuns` that drops a lone restored
    /// mark descended from a destroyed multi-mark baseline run, so the span
    /// renders exactly as the candidate did.
    func testNoGluedEllipsisRemnant_possiblePoints_260901qyi() {
        let record = EditGuardFixtures.productionRecords.first {
            $0.id == "record-2026-09-01T17-17-59-197Z"
        }!
        let out = guardOut(record.baseline, record.candidate, record.language)
        XCTAssertFalse(
            out.contains("possible" + "." + "points"),
            "lone restored ellipsis remnant must not glue onto the following word: \(out)"
        )
        XCTAssertTrue(
            out.contains("two possible points of contact"),
            "span must render exactly as the candidate did, with the deleted ellipsis gone: \(out)"
        )
    }

    /// Negative arm 1 of the new `collapseMixedProvenancePunctuationRuns`
    /// drop rule: a lone restored mark whose OWN baseline neighbour was NOT
    /// punctuation (a baseline run of length 1) must survive untouched —
    /// `WorkToken.restoredFromDestroyedBaselineRun` is false for exactly
    /// this shape, so the new arm never fires on it. Reuses 260831-gd9's own
    /// "in.clawed" production record: the SAME rejected-`.substitute`
    /// restore machinery this quick task also touches (the second
    /// construction site, lines ~2060-2063) must still restore this mark
    /// verbatim, not drop it — proven directly here, not merely inferred
    /// from gd9's own regression test staying green.
    func testNegativeArm_loneMarkFromSingleMarkBaselineRun_survives_260901qyi() {
        let baseline = "Check also in.clawed directory for the file."
        let candidate = "Check also in the clawed directory for the file."
        let out = guardOut(baseline, candidate, "en")
        XCTAssertTrue(
            out.contains("in.clawed directory"),
            "a restored mark from a baseline run of length 1 must render, never be dropped: \(out)"
        )
    }

    /// Negative arm 2 of the new `collapseMixedProvenancePunctuationRuns`
    /// drop rule: a restored mark that ends up ADJACENT to another
    /// punctuation token in the assembled output is a run of length >= 2,
    /// not length 1 — it can never reach the new lone-remnant arm (which is
    /// gated on `run.count == 1`) and stays owned by the pre-existing
    /// mixed-run arm this quick task leaves byte-unchanged. Reuses
    /// 260831-ad8's "government levels" production record.
    ///
    /// EXACT-STRING on purpose (260901-qyi correction): the original version
    /// of this test only asserted `assertFalse(out.contains(", —"))`-shaped
    /// negatives, which stay green even if the lone-remnant arm silently
    /// swallows the restored comma outright (dropping a mark can never
    /// produce the very substring being forbidden) — it could not fail in
    /// the direction it claims to guard. Asserting the full exact string
    /// means a regression that starts dropping this comma changes the
    /// output and the test fails.
    func testNegativeArm_markAdjacentToAnotherPunctuationToken_staysWithMixedRunPass_260901qyi() {
        let record = EditGuardFixtures.productionRecords.first {
            $0.id == "record-2026-08-24T04-00-00-733Z"
        }!
        let out = guardOut(record.baseline, record.candidate, record.language)
        XCTAssertEqual(
            out,
            "Please look for news from this year and if possible as recently as possible about failed or delayed projects either in the government in Switzerland at either of the three levels of government, meaning federal, cantonal and municipal —as well as from the social sector."
        )
    }

    // MARK: - Quick task 260901-qyi (follow-up correction): narrowed lone-remnant drop

    /// REGRESSION (found via independent review + orchestrator differential testing of commit
    /// `1751bc1`, same quick task 260901-qyi): the ORIGINAL `isPartOfMultiMarkBaselineRun`
    /// asked only `kind == .punctuation` of either baseline neighbour — since
    /// `EditGuardTokenizer` emits every non-alphanumeric character as its own punctuation
    /// token, MIXED pairs like `: "` also counted as a "multi-mark run". Baseline carries a
    /// colon immediately followed by an opening quote (`sagte: "komm her"`); the candidate
    /// strips both quotes and relocates the colon to the end of the sentence, so `EditDiff`
    /// pairs the baseline colon against the relocated candidate colon as a `.move`, which
    /// `classifyMove` rejects (all punctuation moves are rejected). The rejected colon is
    /// restored at its own baseline anchor — correctly, in isolation — but its baseline RIGHT
    /// neighbour (the opening quote, also `.punctuation`) satisfied the old broad predicate,
    /// so `WorkToken.restoredFromDestroyedBaselineRun` was wrongly set true and
    /// `collapseMixedProvenancePunctuationRuns`'s lone-remnant arm DELETED the colon outright
    /// — "Sie sagte komm her..." with no colon anywhere, a mark sequence present in NEITHER
    /// input. The narrowed `isPartOfDictatedEllipsisRun` requires the token itself to be "."
    /// (a colon never qualifies, regardless of neighbours), so this predicate short-circuits to
    /// false and the colon survives.
    func testNoDeletedColon_multiMarkQuotePairRelocated_260901qyi() {
        let baseline = "Sie sagte: \"komm her\" und wartete geduldig auf eine Antwort von ihm"
        let candidate = "Sie sagte komm her und wartete geduldig auf eine Antwort von ihm:"
        let out = guardOut(baseline, candidate, "de")
        XCTAssertEqual(out, "Sie sagte: komm her und wartete geduldig auf eine Antwort von ihm")
    }

    /// Same regression, mirror shape: baseline carries a closing quote immediately followed by
    /// a sentence-terminal period (`"the plan". Then`); the candidate strips the quotes and
    /// relocates the period to the end of the WHOLE utterance. The rejected-move period is
    /// restored at its own anchor, next to the (also punctuation, under the old predicate)
    /// closing quote — the old broad predicate flagged it as a destroyed-run remnant and
    /// dropped it, destroying the sentence boundary between "plan" and "Then"
    /// ("...the plan Then..." — two sentences glued with no terminal mark at all). The narrowed
    /// predicate requires baseline text "." on the actual run members (length >= 3), so a
    /// period next to a quote mark never qualifies and the sentence boundary survives.
    func testNoDeletedPeriod_quotePeriodPairRelocated_260901qyi() {
        let baseline = "She called it \"the plan\". Then we started working on it together today"
        let candidate = "She called it the plan Then we started working on it together today."
        let out = guardOut(baseline, candidate, "en")
        XCTAssertEqual(out, "She called it the plan. Then we started working on it together today")
    }

    /// Same regression, doubled-terminal shape: baseline carries "!?" (an exclamation
    /// immediately followed by a question mark — two DIFFERENT marks, not a same-text run).
    /// The candidate deletes the "!" outright (an accepted delete — D-05 accepts all
    /// punctuation deletes unconditionally) and relocates the "?" to the very end of the
    /// sentence. The rejected-move "?" is restored at its own baseline anchor, next to the
    /// (already-deleted, but still baseline-adjacent) "!" — the old broad predicate flagged the
    /// restored "?" as a destroyed-run remnant purely because its baseline neighbour was ALSO
    /// punctuation (a different mark, not a same-text run) and dropped it too, leaving NEITHER
    /// mark in the output ("That was amazing I could..." — a sentence rendered with no
    /// terminal punctuation at all). The narrowed predicate requires the token itself to be "."
    /// — a "?" never qualifies regardless of what neighbours it — so it is never even
    /// evaluated as a candidate for the drop and survives untouched.
    func testNoDeletedMark_doubledBangQuestionPairRelocated_260901qyi() {
        let baseline = "That was amazing!? I could not believe it happened so quickly today"
        let candidate = "That was amazing I could not believe it happened so quickly today?"
        let out = guardOut(baseline, candidate, "en")
        XCTAssertEqual(out, "That was amazing? I could not believe it happened so quickly today")
    }
}
