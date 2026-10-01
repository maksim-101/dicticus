import XCTest
@testable import Dicticus

/// Quick task 260930-s1a: dictated quotation marks must survive
/// `CleanupService.stripPreamble` so EditGuard sees them. The audit record
/// (ts 2026-09-27T11:17:22.677Z) lost both quotes around a dictated word:
/// Step 2 of `stripPreamble` removed every double quote from the LLM output
/// before the gate, so the gate faithfully logged two quote deletions. The
/// step now keeps quotes exactly when the LLM output carries the same
/// per-character counts of the six quote characters as the rules-cleaned
/// input it was given.
///
/// All strings are invented; no dictation text is quoted.
///
/// Q1-Q3 and E1 are RED before the rule (quotes missing from the actual);
/// N1-N5 are GREEN before and after and pin the clauses that keep stripping
/// model-added, extra and restyled quotes.
@MainActor
final class StripPreambleQuoteProvenanceTests: XCTestCase {

    private let q1Input = "So what does the label \"stale\" really signal after a reload? As far as I recall, the queue now has a cap of 40 jobs per minute or so."

    // MARK: - Dictated quotes kept

    func testQ1_straightPairKept() {
        let output = q1Input + "</corrected_text>"
        XCTAssertEqual(CleanupService.stripPreamble(output, input: q1Input), q1Input)
    }

    func testQ2_germanPairKept() {
        let s = "Er nannte den Entwurf „vorläufig“ und ging weiter."
        XCTAssertEqual(CleanupService.stripPreamble(s, input: s), s)
    }

    func testQ3_twoDictatedPairsKept() {
        let s = "The first key is \"alpha\" and the second key is \"beta\" in this sample."
        XCTAssertEqual(CleanupService.stripPreamble(s, input: s), s)
    }

    /// End to end: stripPreamble's output reaches EditGuard.apply; the gate
    /// must see quotes on both sides and delete none.
    func testE1_quotesSurviveStripPreambleAndGate() {
        let llm = CleanupService.stripPreamble(q1Input + "</corrected_text>", input: q1Input)
        let result = EditGuard.apply(rulesCleaned: q1Input, llmOutput: llm, language: "en", lexicon: TestSpellLexicon.allKnown)
        XCTAssertEqual(result.text, q1Input, "edits: \(result.edits)")
        XCTAssertFalse(result.failedClosed)
        XCTAssertNil(result.failClosedReason)
        XCTAssertFalse(result.edits.contains { $0.kind == "delete" && $0.from == "\"" }, "edits: \(result.edits)")
    }

    // MARK: - Model-added or restyled quotes still stripped

    func testN1_wholeOutputWrappedInQuotesStripped() {
        let input = "Please restart the worker after the deploy finishes."
        XCTAssertEqual(CleanupService.stripPreamble("\"" + input + "\"", input: input), input)
    }

    func testN2_modelQuotesOneWordStripped() {
        let input = "Please restart the worker after the deploy finishes."
        let out = "Please restart the \"worker\" after the deploy finishes."
        XCTAssertEqual(CleanupService.stripPreamble(out, input: input), input)
    }

    /// Accepted cost: the dictated pair is kept and another is added, so the
    /// counts differ and everything is stripped.
    func testN3_keptPairPlusAddedPairAllStripped() {
        let input = "The label \"stale\" appears after the reload."
        let out = "The label \"stale\" appears after the \"reload\"."
        XCTAssertEqual(CleanupService.stripPreamble(out, input: input), "The label stale appears after the reload.")
    }

    func testN4_restyledQuotesAllStripped() {
        let input = "The label \"stale\" appears after the reload."
        let out = "The label \u{201C}stale\u{201D} appears after the reload."
        XCTAssertEqual(CleanupService.stripPreamble(out, input: input), "The label stale appears after the reload.")
    }

    func testN5_oneArgumentFormStrips() {
        let expected = "So what does the label stale really signal after a reload? As far as I recall, the queue now has a cap of 40 jobs per minute or so."
        XCTAssertEqual(CleanupService.stripPreamble(q1Input + "</corrected_text>"), expected)
    }
}
