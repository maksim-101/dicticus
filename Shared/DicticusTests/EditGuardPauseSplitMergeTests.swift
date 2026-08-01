import XCTest
@testable import Dicticus

/// Quick task 260801-m8o: RED-first regression net for `AcceptClass
/// .pauseSplitMerge` — a four-arm structural predicate that lets
/// `EditGuard` drop a Whisper pause-split period (a false mid-clause
/// sentence boundary) even when a bundled neighbour edit in the same
/// atomic revert group is independently, correctly rejected.
///
/// Positives (P1-P4) MUST FAIL at HEAD (before the enum case + predicate +
/// coupling exemption exist) and PASS once quick task 260801-m8o's Task 2
/// lands. Negatives (N1-N6) MUST PASS at HEAD and keep passing — each pins
/// one of the predicate's four exclusion arms (R1 exact ".", R2 non-empty
/// whitespace trailing, R3 previous-word length >= 5, R4 next-word
/// lowercase) against a real corpus counterexample.
///
/// Same conventions as `EditGuardMergeAtomicityTests.swift`: the `guardOut`
/// helper, an INTERNAL duplicated copy of the R2-independent neither-source
/// bigram checker (deliberately NOT importing the harness's or that file's
/// copy — same spec, independent implementation), and
/// `assertNeitherSourceClean`.
///
/// Positive fixtures are trimmed/anonymised from real corpus records (per
/// this repo's fixture-anonymisation rule — no personal/project-specific
/// content survives verbatim); negative fixtures N1-N4 are trimmed/
/// anonymised from the four real corpus records the mechanism decision's
/// dry-run table names as "correctly excluded"; N5/N6 are hand-authored to
/// pin R2 (glued form) and R1 (only "." qualifies) respectively, since no
/// real corpus record in the 330-record window exercises those two shapes
/// against a genuinely grouped delete.
@MainActor
final class EditGuardPauseSplitMergeTests: XCTestCase {

    private func guardOut(_ baseline: String, _ llm: String, _ lang: String = "en") -> EditGuard.GuardResult {
        EditGuard.apply(rulesCleaned: baseline, llmOutput: llm, language: lang, lexicon: TestSpellLexicon.allKnown)
    }

    // MARK: - R2 independent neither-source checker (internal copy — see
    // EditGuardMergeAtomicityTests.swift's own copy for the shared spec)

    private static let punctuationChars: Set<Character> = [",", ".", ";", ":", "!", "?"]

    private static func tokenize(_ s: String) -> [String] {
        var tokens: [String] = []
        for word in s.lowercased().split(whereSeparator: { $0.isWhitespace }) {
            var current = ""
            for ch in word {
                if punctuationChars.contains(ch) {
                    if !current.isEmpty { tokens.append(current); current = "" }
                    tokens.append(String(ch))
                } else {
                    current.append(ch)
                }
            }
            if !current.isEmpty { tokens.append(current) }
        }
        return tokens
    }

    private static func isPunctToken(_ t: String) -> Bool {
        t.count == 1 && punctuationChars.contains(t.first!)
    }

    private static func bigramSet(_ tokens: [String]) -> Set<String> {
        guard tokens.count > 1 else { return [] }
        var result = Set<String>()
        for i in 0..<(tokens.count - 1) {
            result.insert(tokens[i] + "\u{0}" + tokens[i + 1])
        }
        return result
    }

    private static func tier1Violations(output: String, sourceA: String, sourceB: String) -> [String] {
        let outWords = tokenize(output).filter { !isPunctToken($0) }
        let aWords = tokenize(sourceA).filter { !isPunctToken($0) }
        let bWords = tokenize(sourceB).filter { !isPunctToken($0) }
        let allowedWordBigrams = bigramSet(aWords).union(bigramSet(bWords))
        guard outWords.count > 1 else { return [] }
        var tier1: [String] = []
        for i in 0..<(outWords.count - 1) {
            let bg = outWords[i] + "\u{0}" + outWords[i + 1]
            if !allowedWordBigrams.contains(bg) {
                tier1.append("\(outWords[i]) \(outWords[i + 1])")
            }
        }
        return tier1
    }

    private func assertNeitherSourceClean(_ output: String, _ baseline: String, _ llm: String, file: StaticString = #filePath, line: UInt = #line) {
        let v = Self.tier1Violations(output: output, sourceA: baseline, sourceB: llm)
        XCTAssertTrue(v.isEmpty, "tier-1 neither-source violation(s) \(v) in: \(output)", file: file, line: line)
    }

    // MARK: - Firing-path guards (gate-blind-to-firing-path rule)

    /// Positive-fixture guard: the run genuinely produced an accepted
    /// `delete(".")` classified `pauseSplitMerge` AND at least one other
    /// REJECTED edit in the same run — the shape this quick task's
    /// exemption exists for. Compared against the raw string
    /// "pauseSplitMerge", not `EditGuard.AcceptClass.pauseSplitMerge`, so
    /// this file compiles at HEAD (the enum case does not exist until
    /// Task 2) and the assertion — not a compile error — is what fails RED.
    private func assertPauseSplitMergeFired(_ result: EditGuard.GuardResult, file: StaticString = #filePath, line: UInt = #line) {
        let periodFired = result.edits.contains {
            $0.kind == "delete" && $0.from == "." && $0.accepted && $0.acceptClass == "pauseSplitMerge"
        }
        XCTAssertTrue(periodFired, "expected an accepted delete(\".\") classified pauseSplitMerge", file: file, line: line)
        let hasOtherRejection = result.edits.contains { !$0.accepted }
        XCTAssertTrue(hasOtherRejection, "fixture must exercise at least one other rejected edit in the same run", file: file, line: line)
    }

    /// Negative-fixture guard: NO edit in the run carries acceptClass
    /// "pauseSplitMerge" — the predicate correctly excluded this shape.
    private func assertPauseSplitMergeDidNotFire(_ result: EditGuard.GuardResult, file: StaticString = #filePath, line: UInt = #line) {
        let fired = result.edits.contains { $0.acceptClass == "pauseSplitMerge" }
        XCTAssertFalse(fired, "expected no edit classified pauseSplitMerge", file: file, line: line)
    }

    // MARK: - P1: evidence record 1 shape (cleanup-2026-08-01.jsonl:121)
    //
    // Real shape: baseline "...different. to what..." / candidate
    // "...different than what...". `to`->`than` is correctly REJECTED
    // (contentWordIdentityChange — "than" is in neither englishInsertable
    // nor englishDualRole); the bundled period-delete must not be dragged
    // down with it. Trimmed to the minimal clause, no anonymisation needed
    // (already generic).

    func testPositive_pauseSplitBeforeRejectedSubstitute_en() {
        let baseline = "I said something completely different. to what was actually written down in the end."
        let llm = "I said something completely different than what was actually written down in the end."
        let expected = "I said something completely different to what was actually written down in the end."
        let result = guardOut(baseline, llm)
        XCTAssertEqual(result.text, expected)
        assertNeitherSourceClean(result.text, baseline, llm)
        assertPauseSplitMergeFired(result)
    }

    // MARK: - P2: evidence record 2 shape (cleanup-2026-07-31.jsonl:103)
    //
    // Real shape: baseline "...Any new thing. that we should consider..."
    // / candidate "...Any new things we should consider...". The period-
    // delete's cluster also contains an ACCEPTED-then-flipped
    // `thing`->`things` inflectionFix and a REJECTED `delete(that)`
    // (contentWordDeletion) — the period must drop while "thing" and
    // "that" both restore to baseline. Trimmed, anonymised (no session/
    // project-specific content).

    func testPositive_pauseSplitBeforeRejectedDeleteInSameGroup_en() {
        let baseline = "Any new thing. that we should consider or maybe something similar we could add later."
        let llm = "Any new things we should consider or maybe something similar we could add later."
        let expected = "Any new thing that we should consider or maybe something similar we could add later."
        let result = guardOut(baseline, llm)
        XCTAssertEqual(result.text, expected)
        assertNeitherSourceClean(result.text, baseline, llm)
        assertPauseSplitMergeFired(result)
    }

    // MARK: - P3: hand-authored German pause-split, lowercase continuation
    //
    // German shape diversity (a capitalised German noun continuation is a
    // documented NON-firing case — see N2/R4 — not a coverage claim here).
    // The continuation word "dann" is lowercase and the word before the
    // period ("gelöst", 6 chars) is >= 5. The neighbouring
    // `gelöst`->`behoben` substitute is a genuine content-identity change,
    // correctly rejected.

    func testPositive_pauseSplitGerman_lowercaseContinuation() {
        let baseline = "Wir haben das Problem gelöst. dann können wir weitermachen."
        let llm = "Wir haben das Problem behoben dann können wir weitermachen."
        let expected = "Wir haben das Problem gelöst dann können wir weitermachen."
        let result = guardOut(baseline, llm, "de")
        XCTAssertEqual(result.text, expected)
        assertNeitherSourceClean(result.text, baseline, llm)
        assertPauseSplitMergeFired(result)
    }

    // MARK: - P4: no-substitution-neighbour shape — REJECTED insert only
    //
    // Hand-authored: the period's atomic group contains the period-delete
    // plus a REJECTED `move` (the baseline word "indeed", correctly
    // reverted to its baseline anchor) and a REJECTED `insert` of an
    // invented content word ("urgently") — no `.substitute` at all. The
    // move+insert pairing is what keeps the period's own delete from being
    // absorbed into a `.substitute` by `EditDiff.pairAdjacentSubstitutes`
    // (a lone delete+insert pair in one gap always merges into a
    // substitute; the move op breaks the gap boundary while NOT breaking
    // the cluster boundary applyAtomicGroupCoupling uses).

    func testPositive_pauseSplitBeforeRejectedInsertOnly_en() {
        let baseline = "The plan is ready. indeed we can proceed forward."
        let llm = "The plan is ready urgently we can proceed indeed forward."
        let expected = "The plan is ready indeed we can proceed forward."
        let result = guardOut(baseline, llm)
        XCTAssertEqual(result.text, expected)
        assertNeitherSourceClean(result.text, baseline, llm)
        assertPauseSplitMergeFired(result)
    }

    // MARK: - N1: abbreviation dot (R3), from cleanup-2026-07-30.jsonl:35
    //
    // Real shape: "...Funktion bzw. dieser Button...". "bzw" is 3
    // characters (< 5), so R3 excludes it — the period stays classified
    // `punctuationOrCasing` and remains subject to ordinary
    // `atomicGroupRevert` coupling, exactly like every other punctuation
    // delete in a reverting group. Trimmed/anonymised: the LLM candidate
    // drops "dieser" entirely (no replacement) — same structural shape
    // (delete(".") + delete(word), zero inserts in the gap) that produced
    // the real record's atomicGroupRevert pairing.

    func testNegative_abbreviationDot_bzw() {
        let baseline = "Diese Funktion bzw. dieser Button sollte klar sein."
        let llm = "Diese Funktion bzw Button sollte klar sein."
        let result = guardOut(baseline, llm, "de")
        XCTAssertEqual(result.text, baseline)
        assertPauseSplitMergeDidNotFire(result)
    }

    // MARK: - N2: capitalised continuation (R4), from cleanup-2026-07-31.jsonl:3
    //
    // Real shape: "...Apple Music. I hovered...". The word after the
    // period is "I" — capitalised — so R4 excludes it regardless of R3.
    // Trimmed/anonymised, with an adjacent rejected `delete("today")` to
    // put the period-delete in a genuinely reverting group (an isolated
    // punctuation-only delete is a DIFFERENT, pre-existing D-05 behavior
    // unrelated to this predicate).

    func testNegative_capitalizedContinuation_appleMusic() {
        let baseline = "I started playing a song in Apple Music today. I hovered over the screen but nothing happened."
        let llm = "I started playing a song in Apple Music I hovered over the screen but nothing happened."
        let result = guardOut(baseline, llm)
        XCTAssertEqual(result.text, baseline)
        assertPauseSplitMergeDidNotFire(result)
    }

    // MARK: - N3: capitalised continuation + rejected content deletion (R3+R4),
    // from cleanup-2026-07-31.jsonl:37
    //
    // Real shape: "...I'm looking for. So maybe...". The word before the
    // period is "for" (3 chars, < 5 — R3 excludes) AND the word after is
    // "So" (capitalised — R4 excludes too) — both arms independently
    // exclude firing, matching the mechanism decision's dry-run table
    // ("R3 + R4"). Trimmed/anonymised.

    func testNegative_capitalizedContinuationWithRejectedDeletion_lookingForSo() {
        let baseline = "Can you apply a color grading is I guess the word I'm looking for. So maybe two darker shades would work better."
        let llm = "Can you apply a color grade? I guess the word I'm looking for is maybe two darker shades would work better."
        let result = guardOut(baseline, llm)
        XCTAssertEqual(result.text, baseline)
        assertPauseSplitMergeDidNotFire(result)
    }

    // MARK: - N4: ellipsis run (R2+R3+R4), from cleanup-2026-07-31.jsonl:91
    //
    // Real shape: "...another... investigation...". Each dot's neighbour
    // is another dot (not a `.word`), so R3 and R4 both fail for the
    // interior dots regardless of R2; the trailing (first/last) dots also
    // fail R3 (neighbour is a dot, not a word) or R2 (empty trailing
    // between glued dots). All three dots stay classified
    // `punctuationOrCasing` and revert together with the group.
    // Trimmed/anonymised.

    func testNegative_ellipsisRun_threeDotsAllSurvive() {
        let baseline = "Please look into this... issue further when you get a chance today."
        let llm = "Please look into further when you get a chance today."
        let result = guardOut(baseline, llm)
        XCTAssertEqual(result.text, baseline)
        assertPauseSplitMergeDidNotFire(result)
    }

    // MARK: - N5: glued form (R2), hand-authored
    //
    // "claw.md"-shaped token: the internal period's own `trailing` is
    // empty (glued directly to "md", no whitespace) — R2 excludes it
    // regardless of R3/R4. The LLM candidate collapses "claw.md" to
    // "clawmd" (dropping the internal period), forcing `EditDiff` to
    // actually attempt a delete of that glued period rather than keeping
    // it untouched — a naive R2-less predicate would otherwise misfire
    // here.

    func testNegative_gluedForm_clawMd() {
        let baseline = "We updated the claw.md file for the team."
        let llm = "We updated the clawmd file for the team."
        let result = guardOut(baseline, llm)
        XCTAssertEqual(result.text, baseline)
        assertPauseSplitMergeDidNotFire(result)
    }

    // MARK: - N6: question form (R1), hand-authored
    //
    // Same shape as P1 but with "?" in place of ".": R1 requires the
    // deleted token's text to be EXACTLY ".", so a `?` never qualifies —
    // even though R2/R3/R4 would all otherwise pass here. Pins that a
    // future widening to all terminal marks fails loudly against this
    // fixture, mirroring `testAtomicRevert_rightSoLostQuestionMark`'s
    // precedent in `EditGuardMergeAtomicityTests.swift`. The "?" must
    // still be fully reverted (restored) alongside the rejected
    // `to`->`than` substitute.

    func testNegative_questionMarkNeverQualifies() {
        let baseline = "I said something completely different? to what was actually written down in the end."
        let llm = "I said something completely different than what was actually written down in the end."
        let result = guardOut(baseline, llm)
        XCTAssertEqual(result.text, baseline)
        assertPauseSplitMergeDidNotFire(result)
    }
}
