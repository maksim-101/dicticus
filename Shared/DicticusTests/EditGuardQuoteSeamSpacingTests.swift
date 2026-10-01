import XCTest
@testable import Dicticus

/// Quick task 261001-opz: regression net for the spacing of straight
/// quotation marks in `EditGuard.deriveSeamSpacing`.
///
/// Seam spacing is keyed by the normalized token pair. A straight `"` is the
/// same token whether it opens or closes a quotation, so one key covers two
/// seams that need opposite spacing and the key becomes contested. A contested
/// key falls through to the kind rule (glue before punctuation), or, when only
/// the candidate's key is contested, to the baseline's vote. Two failure
/// directions follow:
/// - Kind-rule direction: identical inputs come back with an opening quote
///   glued to the word before it (R1), or a closing quote spaced from the word
///   after it (R5). Live records 2026-09-20T07:26:56.014Z and
///   2026-08-26T04:10:22.307Z showed this once 260930-s1a's withheld quote
///   rule let dictated quotes reach the gate (R2 is the second record's shape).
/// - Baseline-fallback direction: the LLM turns `."` into `,"` and the
///   baseline's `,"` key occurs only before an opening quote, so the closing
///   quote renders spaced. Live records 2026-09-08T04:22:20.047Z (R3) and
///   2026-09-26T04:30:13.733Z (R4, German).
///
/// Every string is invented. The task's original reproducer was replaced
/// because it shares a 5-word shingle with a live record; R1 keeps its shape
/// (the word before the opening quote equals the last word inside it) with
/// different words. No dictation text is quoted.
///
/// R1-R5 are RED before the fix: each actual equals its expected string with
/// exactly one space inserted or removed next to a straight quote. N1-N4 are
/// GREEN before and after and pin shapes the role tagging must leave alone.
@MainActor
final class EditGuardQuoteSeamSpacingTests: XCTestCase {

    private func guardResult(_ baseline: String, _ llm: String, _ lang: String = "en") -> EditGuard.GuardResult {
        EditGuard.apply(rulesCleaned: baseline, llmOutput: llm, language: lang, lexicon: TestSpellLexicon.allKnown)
    }

    private func assertRenders(_ expected: String, _ result: EditGuard.GuardResult, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(result.text, expected, "edits: \(result.edits)", file: file, line: line)
        XCTAssertFalse(result.failedClosed, file: file, line: line)
        XCTAssertNil(result.failClosedReason, file: file, line: line)
    }

    // MARK: - Positives (RED before the fix)

    func testR1_identicalInputs_openingQuoteAfterRepeatedWord() {
        let text = "Then open \"Quick Open\" from the menu."
        assertRenders(text, guardResult(text, text))
    }

    func testR2_openingQuoteAfterComma_whileClosingQuotesFollowCommas() {
        let baseline = "The first part ran long and it was slow. She told the team, \"The build passed,\" and then she left."
        let llm = "The first part ran long, and it was slow. She told the team, \"The build passed,\" and then she left."
        let result = guardResult(baseline, llm)
        assertRenders(llm, result)
        let inserts = result.edits.filter { $0.accepted && $0.kind == "insert" }
        XCTAssertEqual(inserts.count, 1, "edits: \(result.edits)")
        XCTAssertEqual(inserts.first?.to, ",", "edits: \(result.edits)")
    }

    func testR3_closingQuoteAfterSubstitutedComma_en() {
        let baseline = "Later the lead can say, \"Fine, that is it.\" And she closes the ticket."
        let llm = "Later the lead can say, \"Fine, that is it,\" and she closes the ticket."
        let result = guardResult(baseline, llm)
        assertRenders(llm, result)
        XCTAssertTrue(
            result.edits.contains { $0.accepted && $0.kind == "substitute" && $0.from == "." && $0.to == "," },
            "edits: \(result.edits)")
    }

    func testR4_closingQuoteAfterSubstitutedComma_de() {
        let baseline = "Und wenn wir dann sagen, \"Das Angebot gilt bis Freitag.\" klingt das freundlich."
        let llm = "Und wenn wir dann sagen, \"Das Angebot gilt bis Freitag,\" klingt das freundlich."
        assertRenders(llm, guardResult(baseline, llm, "de"))
    }

    func testR5_identicalInputs_closingQuoteBeforeRepeatedWord() {
        let text = "The word \"now\" now means something else."
        assertRenders(text, guardResult(text, text))
    }

    // MARK: - Negatives (GREEN before and after)

    func testN1_singleWordQuote_identical() {
        let text = "The label \"stale\" appears after the reload."
        assertRenders(text, guardResult(text, text))
    }

    func testN2_germanCurlyPair_identical() {
        let text = "Er nannte den Entwurf „vorläufig“ und ging weiter."
        assertRenders(text, guardResult(text, text, "de"))
    }

    func testN3_closingQuoteBeforePeriod_identical() {
        let text = "In the end he only said \"done\"."
        assertRenders(text, guardResult(text, text))
    }

    /// The candidate stream holds an odd number of straight quotes, so its
    /// quote stays untagged and today's behaviour applies.
    func testN4_llmDropsOnlyTheOpeningQuote() {
        let baseline = "The lead said, \"Fine, that is it,\" and left the room."
        let llm = "The lead said, Fine, that is it,\" and left the room."
        assertRenders(llm, guardResult(baseline, llm))
    }

    // MARK: - Role units

    private func straightRoles(_ text: String) -> [EditGuard.QuoteRole] {
        let tokens = EditGuardTokenizer.tokenize(text)
        let roles = EditGuard.straightQuoteRoles(tokens)
        return tokens.filter { $0.text == "\"" }.compactMap { roles[$0.index] }
    }

    func testU1_balancedStraightQuotesAlternate() {
        XCTAssertEqual(
            straightRoles("He said \"go\" and \"stop\" twice."),
            [.opening, .closing, .opening, .closing])
    }

    func testU2_oddStraightQuoteCountGetsNoRoles() {
        let tokens = EditGuardTokenizer.tokenize("He said \"go and stop twice.")
        XCTAssertTrue(EditGuard.straightQuoteRoles(tokens).isEmpty)
    }

    func testU3_curlyQuotesGetNoRoles() {
        let tokens = EditGuardTokenizer.tokenize("Er sagte „los“ und ging.")
        XCTAssertTrue(EditGuard.straightQuoteRoles(tokens).isEmpty)
    }
}
