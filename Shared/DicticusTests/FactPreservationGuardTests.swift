import XCTest
@testable import Dicticus

/// Quick task 260830-pf3: an INDEPENDENT fact-preservation backstop for the
/// AI-cleanup pipeline, modeled (approach only, not ported — see
/// `FactPreservationGuard.swift`'s doc comment) on competitor app natter's
/// `TranscriptFactGuard.preservesFacts`.
///
/// Table split into two halves, per the evidence-gate contract:
///   - RED corpus: documented project corruptions this guard exists to
///     catch, expressed as `baseline`/`output` pairs the guard must reject.
///   - Accept-controls: legitimate ITN / number-form rewrites the guard must
///     NOT veto — the real risk this backstop could introduce.
final class FactPreservationGuardTests: XCTestCase {

    // MARK: - RED corpus

    /// project memory `project_v15_capture_findings`: "forty one" → "4001".
    /// By the time text reaches this guard's baseline (rulesCleaned, POST-
    /// ITN), "forty one" already reads as digit "41" — this fixture starts
    /// from that post-ITN shape and reproduces the LLM inventing extra
    /// digits on top of a correct value.
    func testCatchesFortyOneToFourThousandOneShapeCorruption() {
        let baseline = "I need 41 copies by Friday."
        let corrupted = "I need 4001 copies by Friday."
        let result = FactPreservationGuard.check(baseline: baseline, output: corrupted)
        XCTAssertFalse(result.preserved)
        XCTAssertTrue(result.missingLiterals.contains("41"), "expected '41' flagged missing, got \(result.missingLiterals)")
    }

    /// project memory `project_v19d_r8_kink_king_bug`: Gemma collapses
    /// "kink three" → "K3", "King Four" → "K4" — a multi-token merge
    /// `EditDiff`'s alignment (and hence `EditGuard`'s own digit lock) can
    /// miss. Reproduces the SHAPE (a digit token merging into an
    /// alphanumeric identifier) with the digit already present in the
    /// baseline as its own token — the case this guard's digit-only
    /// extraction can see (see SUMMARY for the spelled-number-word gap this
    /// does NOT cover).
    func testCatchesDigitMergingIntoAlphanumericIdentifier_K3Shape() {
        let baseline = "Ask about the K 3 chip specs."
        let corrupted = "Ask about the K3 chip specs."
        let result = FactPreservationGuard.check(baseline: baseline, output: corrupted)
        XCTAssertFalse(result.preserved, "bare '3' merged into 'K3' must not satisfy a naive substring check")
        XCTAssertTrue(result.missingLiterals.contains("3"), "expected '3' flagged missing, got \(result.missingLiterals)")
    }

    /// project memory `project_ios_cleanup_limits`: an output-length cap
    /// silently truncated 43-94% of text. Reproduces the shape — a trailing
    /// clause carrying a number gets dropped entirely.
    func testCatchesTruncationDroppingTrailingNumber() {
        let baseline = "The invoice total was 250 CHF, due Friday."
        let truncated = "The invoice total was, due Friday."
        let result = FactPreservationGuard.check(baseline: baseline, output: truncated)
        XCTAssertFalse(result.preserved)
        XCTAssertTrue(result.missingLiterals.contains("250"), "expected '250' flagged missing, got \(result.missingLiterals)")
    }

    /// Same corruption shape as `EditGuardFixtures.substituteDigit`'s
    /// `fx-sub-digit-en-value` (digit-flanked comma, D-03 blindspot fixture)
    /// — reused here to prove this backstop reaches the same verdict via a
    /// completely independent mechanism (whole-text literal presence, not
    /// `EditDiff` token alignment).
    func testCatchesValueCorruptionInDigitFlankedCommaNumber() {
        let baseline = "...the latency was 10,011 milliseconds under load."
        let corrupted = "...the latency was 10,111 milliseconds under load."
        let result = FactPreservationGuard.check(baseline: baseline, output: corrupted)
        XCTAssertFalse(result.preserved)
        XCTAssertTrue(result.missingLiterals.contains("10,011"), "expected '10,011' flagged missing, got \(result.missingLiterals)")
    }

    func testCatchesDroppedURL() {
        let baseline = "Check https://example.com/docs for details."
        let corrupted = "Check for details."
        let result = FactPreservationGuard.check(baseline: baseline, output: corrupted)
        XCTAssertFalse(result.preserved)
    }

    func testCatchesDroppedEmail() {
        let baseline = "Send it to jane.doe@example.com please."
        let corrupted = "Send it please."
        let result = FactPreservationGuard.check(baseline: baseline, output: corrupted)
        XCTAssertFalse(result.preserved)
    }

    func testCatchesDroppedFilesystemPath() {
        let baseline = "It's saved at ~/code/dicticus/Shared/Utilities for now."
        let corrupted = "It's saved there for now."
        let result = FactPreservationGuard.check(baseline: baseline, output: corrupted)
        XCTAssertFalse(result.preserved)
    }

    func testCatchesDroppedPercentValue() {
        let baseline = "We're at 15% capacity right now."
        let corrupted = "We're at capacity right now."
        let result = FactPreservationGuard.check(baseline: baseline, output: corrupted)
        XCTAssertFalse(result.preserved)
        XCTAssertTrue(result.missingLiterals.contains("15%"), "expected the glued '15%' literal, got \(result.missingLiterals)")
    }

    // MARK: - Accept-controls (the real risk: ITN legitimately rewrites numbers)

    /// `EditGuard`'s `numberFormChange` accept class legitimately turns a
    /// baseline digit into a spelled word ("10" → "zehn"); `NumberRevert`
    /// (Step 3a.5) turns it back BEFORE this guard runs — see
    /// `FactPreservationGuard.swift`'s placement doc comment. Chains the
    /// real `NumberRevert.apply`, not a mock, so this proves the actual
    /// pipeline ordering keeps the accept path open.
    func testAllowsLegitimateDigitToWordFormChangeAfterNumberRevert_de() {
        let baseline = "Ich habe 10 Kunden angerufen."
        let llmOutput = "Ich habe zehn Kunden angerufen."
        let reverted = NumberRevert.apply(baseline: baseline, output: llmOutput, language: "de").text
        let result = FactPreservationGuard.check(baseline: baseline, output: reverted)
        XCTAssertTrue(result.preserved, "legitimate numberFormChange, reverted, must pass: missing \(result.missingLiterals)")
    }

    func testAllowsLegitimateDigitToWordFormChangeAfterNumberRevert_en() {
        let baseline = "I called 10 customers."
        let llmOutput = "I called ten customers."
        let reverted = NumberRevert.apply(baseline: baseline, output: llmOutput, language: "en").text
        let result = FactPreservationGuard.check(baseline: baseline, output: reverted)
        XCTAssertTrue(result.preserved, "legitimate numberFormChange, reverted, must pass: missing \(result.missingLiterals)")
    }

    func testAllowsIdenticalTextThroughUnchanged() {
        let text = "We shipped 3 fixes, saved to ~/code/dicticus, contact team@dicticus.app, see https://dicticus.app/changelog. Cost: 15%."
        let result = FactPreservationGuard.check(baseline: text, output: text)
        XCTAssertTrue(result.preserved, "byte-identical text must always pass: missing \(result.missingLiterals)")
    }

    func testAllowsPunctuationAndCasingChangesAroundNumbers() {
        let baseline = "wir treffen uns um 14 uhr"
        let candidate = "Wir treffen uns um 14 Uhr."
        let result = FactPreservationGuard.check(baseline: baseline, output: candidate)
        XCTAssertTrue(result.preserved, "casing/punctuation-only changes must not veto: missing \(result.missingLiterals)")
    }

    func testAllowsWordOrderRepairAroundNumbers() {
        let baseline = "Um 14 Uhr treffen wir uns."
        let candidate = "Wir treffen uns um 14 Uhr."
        let result = FactPreservationGuard.check(baseline: baseline, output: candidate)
        XCTAssertTrue(result.preserved, "word-order repair must not veto: missing \(result.missingLiterals)")
    }

    // MARK: - Non-vacuity

    /// A fact guard is trivially satisfiable by text carrying no facts.
    /// Asserts the existing EditGuard fixture corpus is NOT that trivial
    /// case: at least some baselines carry a protected literal, so this
    /// guard has real corpus coverage, not just synthetic fixtures above.
    /// (Full count reported in `260830-pf3-SUMMARY.md`, computed the same
    /// way — `check(baseline:, output: "")` against an empty output can
    /// only report `preserved == false` when at least one literal was
    /// extracted from `baseline`.)
    func testNonVacuity_existingFixtureCorpusHasBaselinesWithProtectedLiterals() {
        let baselinesWithLiterals = EditGuardFixtures.all.filter {
            !FactPreservationGuard.check(baseline: $0.baseline, output: "").preserved
        }
        // 260830-pf3-SUMMARY.md: 10 of 87 fixture baselines (~11%) carry a
        // protected literal — the German repair corpus is overwhelmingly
        // non-numeric prose. Not vacuous (>0), but this guard's real
        // coverage is thin against THIS corpus; its value is the specific
        // corruption shapes it targets (see the RED tests above), not broad
        // corpus overlap.
        XCTAssertGreaterThan(
            baselinesWithLiterals.count, 0,
            "expected at least one existing fixture baseline to carry a protected literal"
        )
    }
}
