import XCTest
@testable import Dicticus

/// Quick task 260930-s1a: regression net for punctuation before a name that
/// starts with a dot. The audit record (ts 2026-09-28T04:01:36.829Z) lost the
/// colon in front of a dotted name: `EditGuard.collapseDanglingPunctuation`
/// read the name's leading `.` as a second mark after `: ` and kept only the
/// terminal one, so the pasted text glued the preceding word to the name.
/// The pass now treats a mark as dangling only when whitespace, the end of the
/// string, or a closing quote/bracket follows it.
///
/// Every string is invented or an anonymized shape-preserving copy (the dotted
/// name is a dot plus letters). No dictation text is quoted. The privacy
/// checker in the quick task directory verifies no 5-word shingle overlap with
/// the frozen corpus.
///
/// D1-D3, U1 and U2 are RED before the fix (actual = expected with the mark and
/// space before the dotted name deleted); U3 and U4 are GREEN before and after
/// and pin the collapse shapes the lookahead must keep.
@MainActor
final class EditGuardDottedNameCollapseTests: XCTestCase {

    private func guardResult(_ baseline: String, _ llm: String, _ lang: String = "en") -> EditGuard.GuardResult {
        EditGuard.apply(rulesCleaned: baseline, llmOutput: llm, language: lang, lexicon: TestSpellLexicon.allKnown)
    }

    private let frame = "Fine, the sync daemon is up on the test box. Now set up the remaining two packages"

    // MARK: - End to end

    /// Audit shape: baseline has a glued `,.Name`, the LLM turns the comma into
    /// a colon and spaces the name.
    func testD1_commaToColonBeforeDottedName() {
        let baseline = frame + ",.Vornet and Kelda CLI."
        let llm = frame + ": .Vornet and Kelda CLI."
        let result = guardResult(baseline, llm)
        XCTAssertEqual(result.text, llm, "edits: \(result.edits)")
        XCTAssertFalse(result.failedClosed)
        XCTAssertNil(result.failClosedReason)
        let accepted = result.edits.filter { $0.accepted && $0.kind == "substitute" }
        XCTAssertEqual(accepted.count, 1, "edits: \(result.edits)")
        XCTAssertEqual(accepted.first?.from, ",")
        XCTAssertEqual(accepted.first?.to, ":")
        XCTAssertEqual(accepted.first?.acceptClass, "punctuationOrCasing")
        XCTAssertFalse(result.edits.contains { !$0.accepted }, "edits: \(result.edits)")
    }

    /// Comma kept, the LLM only adds the space before the dotted name.
    func testD2_commaKeptSpaceAddedBeforeDottedName() {
        let baseline = frame + ",.Vornet and Kelda CLI."
        let llm = frame + ", .Vornet and Kelda CLI."
        let result = guardResult(baseline, llm)
        XCTAssertEqual(result.text, llm, "edits: \(result.edits)")
        XCTAssertFalse(result.failedClosed)
        XCTAssertNil(result.failClosedReason)
    }

    /// Identical inputs: a dotted name after a sentence end survives untouched.
    func testD3_dottedNameAfterSentenceEndIdenticalInputs() {
        let text = "Open the settings folder. .Travrc holds the defaults."
        let result = guardResult(text, text)
        XCTAssertEqual(result.text, text, "edits: \(result.edits)")
        XCTAssertFalse(result.failedClosed)
        XCTAssertNil(result.failClosedReason)
    }

    // MARK: - collapseDanglingPunctuation unit shapes

    func testU1_markThenDottedNameUnchanged() {
        XCTAssertEqual(EditGuard.collapseDanglingPunctuation("packages: .Vornet and more"), "packages: .Vornet and more")
    }

    func testU2_markThenDotDigitUnchanged() {
        XCTAssertEqual(EditGuard.collapseDanglingPunctuation("a ratio of: .5 works"), "a ratio of: .5 works")
    }

    func testU3_endOfStringStillCollapses() {
        XCTAssertEqual(EditGuard.collapseDanglingPunctuation("done , ."), "done.")
    }

    func testU4_closingQuoteAfterSecondMarkStillCollapses() {
        XCTAssertEqual(EditGuard.collapseDanglingPunctuation("he said , .\""), "he said.\"")
    }
}
