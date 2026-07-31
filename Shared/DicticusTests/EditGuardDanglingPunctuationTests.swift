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
}
