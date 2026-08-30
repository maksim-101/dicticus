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
}
