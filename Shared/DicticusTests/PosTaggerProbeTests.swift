import XCTest
@testable import Dicticus

/// Phase 44 Plan 07: the self-binding ship-gate test for `PosTagger`.
///
/// `testNLTaggerWideningFlagIsBoundToTheEvidence` is the ONLY assertion
/// that matters here — it binds `PosTagger.enableNLTaggerFunctionWidening`
/// to `measureAgreement`'s dangerous-direction error count in BOTH
/// directions, unconditionally (no `if`/`guard`/`XCTSkip` around it). This
/// is deliberately NOT the "green gate over a corpus that cannot fire the
/// feature" anti-pattern flagged in this phase's blocking constraints:
/// `testProbeCorpusCanFireTheProbe` exists specifically to prove the
/// corpus has both known-function and known-content tokens BEFORE the ship
/// gate test is trusted, so a zero error count can never be an artifact of
/// an empty denominator.
final class PosTaggerProbeTests: XCTestCase {

    // MARK: - The anti-vacuity precondition

    /// A probe over a corpus with zero content words (or zero function
    /// words) could report a perfect zero dangerous-direction error rate
    /// and mean nothing — this is the direct Phase-39 lesson
    /// (`feedback_gate_blind_to_firing_path`) applied to this plan. This
    /// test exists so `testNLTaggerWideningFlagIsBoundToTheEvidence` cannot
    /// be vacuous.
    @MainActor
    func testProbeCorpusCanFireTheProbe() {
        XCTAssertFalse(GermanPosProbeFixtures.sentences.isEmpty,
            "The German probe fixture must be non-empty.")

        let result = PosTagger.measureAgreement(GermanPosProbeFixtures.sentences, language: "de")
        XCTAssertGreaterThan(result.knownFunctionWords, 0,
            "The probe corpus must contain closed-list-backed function words, or the dangerous-direction error rate is meaningless.")
        XCTAssertGreaterThan(result.knownContentWords, 0,
            "The probe corpus must contain heuristic-content words, or the dangerous-direction error rate is meaningless.")
    }

    // MARK: - The ship gate (self-binding, unconditional, both directions)

    /// The flag may be `true` ONLY if the measured dangerous-direction
    /// error count is exactly 0, and it MUST be `true` if it is 0. No
    /// `if`/`guard`/`XCTSkip` wraps this assertion — it cannot be satisfied
    /// by disabling the feature and skipping the check. If a future OS
    /// update degrades or improves NLTagger's German model, this test goes
    /// red first and forces a decision, rather than silently drifting
    /// stale.
    @MainActor
    func testNLTaggerWideningFlagIsBoundToTheEvidence() {
        let result = PosTagger.measureAgreement(GermanPosProbeFixtures.sentences, language: "de")
        XCTAssertEqual(
            PosTagger.enableNLTaggerFunctionWidening,
            result.contentMisclassifiedAsFunction == 0,
            "enableNLTaggerFunctionWidening (\(PosTagger.enableNLTaggerFunctionWidening)) must equal " +
            "(contentMisclassifiedAsFunction == 0) (\(result.contentMisclassifiedAsFunction) == 0 is " +
            "\(result.contentMisclassifiedAsFunction == 0)) — the flag is bound to the measured evidence " +
            "in both directions. See 44-NLTAGGER-PROBE.md."
        )
    }

    // MARK: - nil must never be coerced to true

    /// A language with no `.lexicalClass` German/English asset available
    /// must return `nil` ("no opinion") — never `true`. `NLLanguage`
    /// accepts any BCP-47 string; a fabricated/unsupported tag exercises
    /// the `availableTagSchemes` early-return without needing to stub
    /// `NLTagger` internals.
    @MainActor
    func testTaggerUnavailableIsNotSilentlyTreatedAsFunction() {
        let verdict = PosTagger.isFunctionWord("xyzzy", in: "xyzzy plugh", language: "zz-Unsupported-FANTASY")
        XCTAssertNil(verdict, "An unsupported/unavailable tagger language must yield nil, never true.")

        // Also: a token that genuinely does not occur in the sentence must
        // be nil, not silently coerced.
        let notFound = PosTagger.isFunctionWord("nichtvorhanden", in: "Der Hund läuft schnell.", language: "de")
        XCTAssertNil(notFound, "A token absent from the sentence must yield nil, never true.")
    }

    // MARK: - Report the numbers (lands in the test log even when green)

    @MainActor
    func testMeasuredRatesAreReported() {
        let result = PosTagger.measureAgreement(GermanPosProbeFixtures.sentences, language: "de")
        let functionRate = result.knownFunctionWords > 0
            ? Double(result.functionMisclassifiedAsContent) / Double(result.knownFunctionWords) * 100
            : 0
        let contentRate = result.knownContentWords > 0
            ? Double(result.contentMisclassifiedAsFunction) / Double(result.knownContentWords) * 100
            : 0

        print("""
        [PosTagger probe — 44-07] \
        total=\(result.total) \
        knownFunctionWords=\(result.knownFunctionWords) \
        knownContentWords=\(result.knownContentWords) \
        functionMisclassifiedAsContent=\(result.functionMisclassifiedAsContent) (\(String(format: "%.2f", functionRate))%, SAFE direction) \
        contentMisclassifiedAsFunction=\(result.contentMisclassifiedAsFunction) (\(String(format: "%.2f", contentRate))%, DANGEROUS direction) \
        taggerUnavailable=\(result.taggerUnavailable) \
        shippedFlag=\(PosTagger.enableNLTaggerFunctionWidening)
        """)

        // Not a real assertion — this test's job is the print above landing
        // in the log. Keep one trivial assertion so XCTest still reports
        // pass/fail rather than "no assertions" ambiguity.
        XCTAssertGreaterThanOrEqual(result.total, 0)
    }
}
