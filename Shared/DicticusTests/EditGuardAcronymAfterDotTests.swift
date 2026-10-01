import XCTest
@testable import Dicticus

/// Quick task 260930-s1h: regression net for the acronym-after-a-dot rule.
/// Live defect `2026-09-27T04:32:59.544Z`: the dictionary produced a dotted
/// identifier with an all-caps extension, the LLM title-cased the extension,
/// and `classifySubstitute` step 1 (casing-only accept) shipped it. Fixed by
/// `RejectionClass.acronymLoweredAfterDot`, which is deliberately NOT a
/// `sentenceRevertTriggerClasses` member. The correct mid-sentence brand
/// recase of `2026-09-20T04:54:04.555Z` is the N2 shape and stays accepted.
///
/// Every fixture is INVENTED, with invented filenames and no personal facts;
/// live records are cited by ts only (D-12). `s1h_privacy_check.py` in the
/// quick task directory verifies no 5-word shingle overlap with the staged
/// corpus.
///
/// P1-P4 are RED before the fix (actual = expected with the lowered form in
/// place of the acronym); N1-N3 are GREEN before and after, each pinning one
/// clause of the predicate.
@MainActor
final class EditGuardAcronymAfterDotTests: XCTestCase {

    private func guardOut(_ baseline: String, _ llm: String, _ lang: String = "en") -> String {
        EditGuard.apply(rulesCleaned: baseline, llmOutput: llm, language: lang, lexicon: TestSpellLexicon.allKnown).text
    }

    private func guardResult(_ baseline: String, _ llm: String, _ lang: String = "en") -> EditGuard.GuardResult {
        EditGuard.apply(rulesCleaned: baseline, llmOutput: llm, language: lang, lexicon: TestSpellLexicon.allKnown)
    }

    private func assertAcronymRejected(_ result: EditGuard.GuardResult, from: String, to: String, file: StaticString = #filePath, line: UInt = #line) {
        let hit = result.edits.first { $0.kind == "substitute" && $0.from == from && $0.to == to }
        XCTAssertNotNil(hit, "no \(from)->\(to) substitute in \(result.edits)", file: file, line: line)
        XCTAssertEqual(hit?.accepted, false, file: file, line: line)
        XCTAssertEqual(hit?.rejectClass, "acronymLoweredAfterDot", file: file, line: line)
    }

    // MARK: - P1: target shape — glued dotted identifier, extension title-cased, more edits after it in the same raw sentence

    /// The tokenizer treats the identifier's `.` as a sentence boundary, so
    /// the extension opens baseline sentence 1 and the inserted commas and
    /// the final mark sit in that same raw sentence. They must stay accepted:
    /// this fails if the new class were added to `sentenceRevertTriggerClasses`.
    func testP1_gluedExtensionTitleCasedKeepsSentencePunctuation() {
        let baseline = "then we opened the notes.MD file and checked the budget numbers and the schedule for the week and sent the summary to the team"
        let llm = "Then we opened the notes.Md file, and checked the budget numbers, and the schedule for the week, and sent the summary to the team."
        let expected = "Then we opened the notes.MD file, and checked the budget numbers, and the schedule for the week, and sent the summary to the team."
        let out = guardOut(baseline, llm)
        let result = guardResult(baseline, llm)
        XCTAssertEqual(out, expected, "edits: \(result.edits)")
        assertAcronymRejected(result, from: "MD", to: "Md")
        XCTAssertTrue(result.edits.contains { $0.kind == "substitute" && $0.from == "then" && $0.to == "Then" && $0.accepted && $0.acceptClass == "punctuationOrCasing" })
        let commas = result.edits.filter { $0.kind == "insert" && $0.to == "," }
        XCTAssertEqual(commas.count, 3, "edits: \(result.edits)")
        XCTAssertTrue(commas.allSatisfy { $0.accepted && $0.acceptClass == "punctuationOrCasing" }, "edits: \(result.edits)")
        let mark = result.edits.last
        XCTAssertEqual(mark?.kind, "insert")
        XCTAssertEqual(mark?.to, ".")
        XCTAssertEqual(mark?.accepted, true)
        XCTAssertEqual(mark?.acceptClass, "punctuationOrCasing")
        XCTAssertFalse(result.edits.contains { $0.rejectClass == "sentenceCoupledRevert" }, "edits: \(result.edits)")
        let v = EditGuardMergeAtomicityTests.neitherSourceViolations(output: out, sourceA: baseline, sourceB: llm)
        XCTAssertTrue(v.tier1.isEmpty, "tier-1 neither-source violation(s) \(v.tier1) in: \(out)")
    }

    // MARK: - P2: full lowering after a glued dot

    func testP2_gluedExtensionFullyLowered() {
        let baseline = "then we opened the notes.TXT file and checked the budget numbers and the schedule for the week and sent the summary to the team"
        let llm = "Then we opened the notes.txt file, and checked the budget numbers, and the schedule for the week, and sent the summary to the team."
        let expected = "Then we opened the notes.TXT file, and checked the budget numbers, and the schedule for the week, and sent the summary to the team."
        let out = guardOut(baseline, llm)
        let result = guardResult(baseline, llm)
        XCTAssertEqual(out, expected, "edits: \(result.edits)")
        assertAcronymRejected(result, from: "TXT", to: "txt")
        let v = EditGuardMergeAtomicityTests.neitherSourceViolations(output: out, sourceA: baseline, sourceB: llm)
        XCTAssertTrue(v.tier1.isEmpty, "tier-1 neither-source violation(s) \(v.tier1) in: \(out)")
    }

    // MARK: - P3: utterance-final identifier — the lowered extension and the final mark share one cluster

    func testP3_utteranceFinalExtensionKeepsFinalMark() {
        let baseline = "we then wrote the final totals into the archive.ZIP"
        let llm = "We then wrote the final totals into the archive.zip."
        let expected = "We then wrote the final totals into the archive.ZIP."
        let out = guardOut(baseline, llm)
        let result = guardResult(baseline, llm)
        XCTAssertEqual(out, expected, "edits: \(result.edits)")
        assertAcronymRejected(result, from: "ZIP", to: "zip")
        let mark = result.edits.last
        XCTAssertEqual(mark?.kind, "insert")
        XCTAssertEqual(mark?.to, ".")
        XCTAssertEqual(mark?.accepted, true, "edits: \(result.edits)")
        let v = EditGuardMergeAtomicityTests.neitherSourceViolations(output: out, sourceA: baseline, sourceB: llm)
        XCTAssertTrue(v.tier1.isEmpty, "tier-1 neither-source violation(s) \(v.tier1) in: \(out)")
    }

    // MARK: - P4: spaced sentence boundary

    func testP4_spacedSentenceStartAcronymKept() {
        let baseline = "the build finally passed. API keys were rotated after that"
        let llm = "The build finally passed. Api keys were rotated after that."
        let expected = "The build finally passed. API keys were rotated after that."
        let out = guardOut(baseline, llm)
        let result = guardResult(baseline, llm)
        XCTAssertEqual(out, expected, "edits: \(result.edits)")
        assertAcronymRejected(result, from: "API", to: "Api")
        let v = EditGuardMergeAtomicityTests.neitherSourceViolations(output: out, sourceA: baseline, sourceB: llm)
        XCTAssertTrue(v.tier1.isEmpty, "tier-1 neither-source violation(s) \(v.tier1) in: \(out)")
    }

    // MARK: - N1: sentence-initial capitalization after a raw period stays accepted (pins the all-uppercase clause)

    func testN1_sentenceInitialCapitalizationAfterPeriodAccepted() {
        let baseline = "the invoice was paid. so the account is closed"
        let llm = "The invoice was paid. So the account is closed."
        let out = guardOut(baseline, llm)
        let result = guardResult(baseline, llm)
        XCTAssertEqual(out, llm, "edits: \(result.edits)")
        let so = result.edits.first { $0.kind == "substitute" && $0.from == "so" && $0.to == "So" }
        XCTAssertEqual(so?.accepted, true)
        XCTAssertEqual(so?.acceptClass, "punctuationOrCasing")
    }

    // MARK: - N2: all-caps brand recased mid-sentence, no dot before it (pins the dot-predecessor clause; 2026-09-20T04:54:04.555Z shape)

    func testN2_midSentenceBrandRecaseAccepted() {
        let baseline = "we shipped the new release to GITHUB yesterday"
        let llm = "We shipped the new release to GitHub yesterday."
        let out = guardOut(baseline, llm)
        let result = guardResult(baseline, llm)
        XCTAssertEqual(out, llm, "edits: \(result.edits)")
        let brand = result.edits.first { $0.kind == "substitute" && $0.from == "GITHUB" && $0.to == "GitHub" }
        XCTAssertEqual(brand?.accepted, true)
        XCTAssertEqual(brand?.acceptClass, "punctuationOrCasing")
    }

    // MARK: - N3: mixed-case segment after a glued dot (pins "every letter uppercase")

    func testN3_mixedCaseSegmentAfterDotAccepted() {
        let baseline = "please edit the Info.Plist before the build"
        let llm = "Please edit the Info.plist before the build."
        let out = guardOut(baseline, llm)
        let result = guardResult(baseline, llm)
        XCTAssertEqual(out, llm, "edits: \(result.edits)")
        let seg = result.edits.first { $0.kind == "substitute" && $0.from == "Plist" && $0.to == "plist" }
        XCTAssertEqual(seg?.accepted, true)
        XCTAssertEqual(seg?.acceptClass, "punctuationOrCasing")
    }
}
