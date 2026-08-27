import XCTest
@testable import Dicticus

/// Quick task 260827-81z Task 3: audit of `EditGuard.isPauseSplitPeriod`
/// (`Shared/Utilities/EditGuard.swift:854-874`) against real Parakeet output.
/// The predicate has governed iOS/Parakeet's `AcceptClass.pauseSplitMerge`
/// exemption since Phase 47.1 without ever being exercised against it — its
/// R4 arm is explicitly Whisper-shaped ("Whisper capitalises after a period
/// it means; a lowercase continuation is the pause-split signature").
///
/// **Sample size, stated plainly:** the real-corpus fixtures below are
/// paraphrased from `n≈61` Parakeet decodes in one speaker's corpus
/// (`.planning/phases/47-ios-asr-engine-spike-parakeet-vs-whisper/
/// 47-asshipped.jsonl`, filtered `"engine":"parakeet"`). Exactly 3 of those
/// ~61 rows contain a period followed by a space and a lowercase letter, and
/// all three are excluded by R3 (the token before the period is either the
/// 3-character abbreviation "etc" or a bare digit, never a 5+-character
/// word) — R4 is never actually exercised by a genuine 5+-character-word
/// boundary in this corpus. This is a complete, honest result for `n≈61`
/// from one speaker, not a general claim about Parakeet.
///
/// This is an AUDIT, not a fix. `EditGuard.swift` is untouched by this file
/// (`git diff` on it is empty) unless one of these tests demonstrated a real
/// defect — see the SUMMARY for the audit's finding statement.
///
/// Same conventions as `EditGuardPauseSplitMergeTests.swift`: the `guardOut`
/// helper, and INTERNAL duplicated copies of `assertPauseSplitMergeFired` /
/// `assertPauseSplitMergeDidNotFire` (private to that file — this is a
/// deliberate independent copy, the same convention that file's own header
/// documents for its neither-source bigram checker, not an oversight to fix
/// by promoting them to internal).
///
/// Fixtures paraphrased from real project-management/dev-workflow archive
/// rows are trimmed and anonymised per this repo's fixture-anonymisation
/// rule — no verbatim archive-row text survives here.
@MainActor
final class EditGuardPauseSplitParakeetAuditTests: XCTestCase {

    private func guardOut(_ baseline: String, _ llm: String, _ lang: String = "en") -> EditGuard.GuardResult {
        EditGuard.apply(rulesCleaned: baseline, llmOutput: llm, language: lang, lexicon: TestSpellLexicon.allKnown)
    }

    /// Positive-fixture guard, modelled on `EditGuardPauseSplitMergeTests
    /// .assertPauseSplitMergeFired` — an accepted `delete(".")` classified
    /// `pauseSplitMerge` exists in the run. Compared against the raw string
    /// "pauseSplitMerge" (not the enum case) so this file's own copy stays
    /// independent, matching that file's convention.
    private func assertPauseSplitMergeFired(_ result: EditGuard.GuardResult, file: StaticString = #filePath, line: UInt = #line) {
        let periodFired = result.edits.contains {
            $0.kind == "delete" && $0.from == "." && $0.accepted && $0.acceptClass == "pauseSplitMerge"
        }
        XCTAssertTrue(periodFired, "expected an accepted delete(\".\") classified pauseSplitMerge", file: file, line: line)
    }

    /// Negative-fixture guard: no edit in the run carries acceptClass
    /// "pauseSplitMerge" — the predicate correctly excluded this shape.
    private func assertPauseSplitMergeDidNotFire(_ result: EditGuard.GuardResult, file: StaticString = #filePath, line: UInt = #line) {
        let fired = result.edits.contains { $0.acceptClass == "pauseSplitMerge" }
        XCTAssertFalse(fired, "expected no edit classified pauseSplitMerge", file: file, line: line)
    }

    // MARK: - N1: real shape, "etc. mean" (R3 excludes — "etc" is 3 chars)
    //
    // Paraphrased from the real corpus row (archive-2026-08-01, Parakeet):
    // a question about what a set of small labelled icons mean, with "etc."
    // immediately followed by lowercase "mean". The LLM candidate also
    // drops the following content word ("mean" itself), bundling it with
    // the period-delete in one atomic group — mirrors
    // `EditGuardPauseSplitMergeTests.testNegative_abbreviationDot_bzw`'s
    // structural pattern (period-delete + adjacent word-delete, zero
    // inserts) so a full group revert is a meaningful confirmation that R3
    // excluded firing, not just an isolated no-op punctuation delete.
    //
    // FINDING: CORRECT. R3 excludes "etc" (3 chars, < 5) regardless of R4 —
    // matches the real corpus row exactly (planning findings: all 3 real
    // period-lowercase Parakeet rows are R3-excluded).

    func testNegative_abbreviationEtc_realShapeIconLegend_en() {
        let baseline = "The small icons for size, weight, etc. mean nothing without a legend."
        let llm = "The small icons for size, weight, etc nothing without a legend."
        let result = guardOut(baseline, llm)
        XCTAssertEqual(result.text, baseline)
        assertPauseSplitMergeDidNotFire(result)
    }

    // MARK: - N2: real shape, "etc. in the" (R3 excludes)
    //
    // Paraphrased from the real corpus row (archive-2026-08-11, Parakeet):
    // a dev-workflow question about updating labels/ports/settings, with
    // "etc." immediately followed by lowercase "in". The LLM candidate
    // drops the following function word ("in"), same bundling pattern as
    // N1.
    //
    // FINDING: CORRECT. R3 excludes "etc" (3 chars) — matches the real row.

    func testNegative_abbreviationEtc_realShapeUpdateGuide_en() {
        let baseline = "We should also update the labels, ports, and settings, etc. in the guide."
        let llm = "We should also update the labels, ports, and settings, etc the guide."
        let result = guardOut(baseline, llm)
        XCTAssertEqual(result.text, baseline)
        assertPauseSplitMergeDidNotFire(result)
    }

    // MARK: - N3: real shape, bare digit before the period (R3 excludes via
    // TokenKind.numeric, not TokenKind.word)
    //
    // Paraphrased from the real corpus row (archive-2026-08-15, Parakeet):
    // a question about retiring an old versioned build, with the period
    // immediately preceded by a bare digit ("2."). The LLM candidate also
    // drops the following content word ("four"), same bundling pattern.
    //
    // FINDING: CORRECT. R3 requires `prev.kind == .word`; a bare digit is
    // tokenised `.numeric`, so R3 excludes it regardless of length — a
    // distinct exclusion path from N1/N2's length guard, both landing on
    // the same "does not fire" outcome. Matches the real row.

    func testNegative_bareDigitBeforePeriod_realShapeVersionRetire_en() {
        let baseline = "Can we retire the legacy version 2. four is already shipped and no longer supported."
        let llm = "Can we retire the legacy version 2 is already shipped and no longer supported."
        let result = guardOut(baseline, llm)
        XCTAssertEqual(result.text, baseline)
        assertPauseSplitMergeDidNotFire(result)
    }

    // MARK: - P1: hand-authored, genuine Parakeet-shaped sentence boundary
    // with lowercase continuation, English (R3+R4 both pass)
    //
    // Not present in the real n≈61 corpus (no row exercises R4 against a
    // 5+-character previous word) — hand-authored to expose what the
    // heuristic actually does if this shape DID occur. Parakeet emits
    // native punctuation/capitalisation but is closer-to-spoken and runs no
    // internal ITN sentence-boundary pass (unlike Whisper's seq2seq LM), so
    // a genuine sentence boundary followed by a lowercase continuation is a
    // plausible Parakeet output shape R4's doc comment does not anticipate.
    //
    // FINDING: OVER-EAGER (theoretical, not measured live). R3 passes
    // ("already", 7 chars) and R4 passes ("now" lowercase), so
    // `isPauseSplitPeriod` returns true exactly as it would for a genuine
    // Whisper pause-split — the predicate cannot distinguish "Whisper
    // pause-split period" from "Parakeet genuine sentence boundary that
    // merely lacks Whisper-style capitalisation discipline". The two real
    // sentences below get merged into one run-on: `result.text` drops the
    // period even though the neighbouring `already`->`promptly` edit is
    // correctly rejected. This is NOT a demonstrated live defect — the real
    // n≈61 corpus never exercises this shape — so `EditGuard.swift` is left
    // unchanged; this test PINS the current (over-eager) behaviour as a
    // regression net for a future corpus that does exercise it.

    func testPositive_genuineBoundaryLowercaseContinuation_overEager_en() {
        let baseline = "I have closed the ticket already. now let's move to the next one."
        let llm = "I have closed the ticket promptly now let's move to the next one."
        let expected = "I have closed the ticket already now let's move to the next one."
        let result = guardOut(baseline, llm)
        XCTAssertEqual(result.text, expected)
        assertPauseSplitMergeFired(result)
    }

    // MARK: - P2: hand-authored, genuine Parakeet-shaped sentence boundary
    // with lowercase continuation, German (R3+R4 both pass)
    //
    // Same shape as P1, German. "erledigt" (8 chars) satisfies R3; "dann"
    // (lowercase) satisfies R4. Deliberately distinct vocabulary from
    // `EditGuardPauseSplitMergeTests.testPositive_pauseSplitGerman
    // _lowercaseContinuation` ("gelöst"/"behoben") — same shape, an
    // independent fixture, not a copy.
    //
    // FINDING: OVER-EAGER (theoretical, not measured live) — same reasoning
    // as P1. Pinned as a regression net, `EditGuard.swift` left unchanged.

    func testPositive_genuineBoundaryLowercaseContinuation_overEager_de() {
        let baseline = "Wir haben die Aufgabe bereits erledigt. dann können wir weitermachen."
        let llm = "Wir haben die Aufgabe bereits abgeschlossen dann können wir weitermachen."
        let expected = "Wir haben die Aufgabe bereits erledigt dann können wir weitermachen."
        let result = guardOut(baseline, llm, "de")
        XCTAssertEqual(result.text, expected)
        assertPauseSplitMergeFired(result)
    }

    // MARK: - N4: German capitalised NOUN continuation (R4 excludes) — the
    // exclusion pinned rather than assumed
    //
    // German capitalises every noun, not just sentence-initial words, so a
    // genuine sentence boundary followed by a capitalised German noun is
    // structurally indistinguishable — for R4's purposes — from any other
    // capitalised continuation. "eingereicht" (11 chars) satisfies R3, but
    // "Der" (article, capitalised because it is sentence-initial here) and
    // the noun it introduces are both capitalised; either way the FIRST
    // character of the continuation word is uppercase, so R4 excludes it
    // regardless of why it is capitalised.
    //
    // FINDING: CORRECT. This is the documented ACCEPTED COST direction (a
    // genuine pause-split before a capitalised German noun continuation
    // would be a missed repair, not a corruption) — here it correctly
    // protects a genuine sentence boundary instead.

    func testNegative_germanCapitalizedNounContinuation_der() {
        let baseline = "Wir haben die Unterlagen bereits eingereicht. Der Antrag wird nun geprüft."
        let llm = "Wir haben die Unterlagen bereits abgeschickt Der Antrag wird nun geprüft."
        let result = guardOut(baseline, llm, "de")
        XCTAssertEqual(result.text, baseline)
        assertPauseSplitMergeDidNotFire(result)
    }
}
