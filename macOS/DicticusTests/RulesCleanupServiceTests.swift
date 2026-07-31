import XCTest
@testable import Dicticus

// Phase 36.1 Wave 0 RED scaffolding.
// These tests call RulesCleanupService().clean(_:language:) and assert the
// trailing-artifact strip behavior that Plan 36.1-04 adds to that method.
// Until that plan lands, the strip behavior is absent and these tests will fail
// — that is the intended RED state.

final class RulesCleanupServiceTests: XCTestCase {

    // MARK: - Trailing-artifact strip

    func testArtifactStrip_terminalYeah_stripped() {
        // Terminal standalone "Yeah" (media bleed) must be stripped.
        // The preceding sentence terminal punctuation must be preserved.
        let service = RulesCleanupService()
        let result = service.clean("This is the transcribed text. Yeah", language: "en")
        XCTAssertEqual(result, "This is the transcribed text.",
            "Phase 36.1: artifact strip — terminal Yeah must be removed, sentence punct preserved")
    }

    func testArtifactStrip_terminalMmHmm_stripped() {
        // Terminal "Mm-hmm" is a media bleed artifact — must be stripped.
        let service = RulesCleanupService()
        let result = service.clean("That sounds right okay Mm-hmm", language: "en")
        XCTAssertEqual(result, "That sounds right okay",
            "Phase 36.1: artifact strip — terminal Mm-hmm must be removed")
    }

    func testArtifactStrip_interiorYeah_preserved() {
        // Interior "yeah" (not terminal) must NOT be stripped — only terminal artifacts are removed.
        let service = RulesCleanupService()
        let result = service.clean("Yeah that makes sense to me", language: "en")
        XCTAssertTrue(result.lowercased().contains("yeah"),
            "Phase 36.1: artifact strip — interior yeah must be preserved, only terminal artifacts stripped")
    }

    // MARK: - Phase 39: voice-command toggle (D-07) + divergence-gate baseline (D-08)

    /// Simultaneously the D-07 default-ON proof AND the CONTEXT.md
    /// confirming test. `clean(...)` IS Step 2c, and `TextProcessingService`
    /// snapshots `rulesCleanedText` on the line immediately after Step 2c —
    /// so whatever this function returns is literally the divergence gate's
    /// baseline. The gate compares LLM output against THIS string, which
    /// already has the scratch applied, so it structurally cannot revert a
    /// deliberate scratch as content-loss. This turns the CONTEXT.md
    /// "verified non-issue" claim from a code-reading assertion into a
    /// pinned, tested property.
    ///
    /// DISABLED 2026-07-11 (enableScratchCommand = false in
    /// SelfCorrectionResolver.swift; see CR-01/CR-02). The D-07
    /// `enableVoiceCommands` runtime toggle is still wired and still
    /// default-ON, but the underlying evidence source it gates now
    /// ABSTAINS unconditionally, so passing `enableVoiceCommands: true`
    /// (the default, as here) no longer fires a delete.
    /// Asserts passthrough because the gate is off.
    /// WHEN RE-ENABLED after gap closure, this MUST assert:
    ///   "The report is done."
    /// Do not re-enable the flag and leave this asserting passthrough.
    func testVoiceCommandsEnabledByDefaultDeletesScratchedSentence() {
        let service = RulesCleanupService()
        let input = "The report is done. We ship on Friday. Scratch that."
        let result = service.clean(input, language: "en")
        XCTAssertEqual(result, input,
            "enableScratchCommand ships false (CR-01/CR-02) — must ABSTAIN, byte-identical")
    }

    /// D-07's escape hatch for users who dictate ABOUT editing: with the
    /// toggle explicitly OFF, the command phrase survives verbatim.
    func testVoiceCommandsDisabledPassesCommandPhraseThrough() {
        let service = RulesCleanupService()
        let result = service.clean(
            "The report is done. We ship on Friday. Scratch that.",
            language: "en",
            enableVoiceCommands: false
        )
        XCTAssertEqual(result, "The report is done. We ship on Friday. Scratch that.",
            "Phase 39/D-07: voice commands OFF — command phrase must pass through literally")
    }

    /// Pins that the D-07 toggle gates ONLY the new scratch-delete evidence
    /// source and does not accidentally switch off the whole resolver — an
    /// ordinary Phase-43 self-correction must still resolve with the toggle
    /// OFF. Reuses the German "ich meine" currency-correction fixture from
    /// `SelfCorrectionResolverTests` (line 33).
    func testVoiceCommandsDisabledStillResolvesClassicSelfCorrection() {
        let service = RulesCleanupService()
        let result = service.clean(
            "Das kostet 110 Franken, ich meine 110 Euro.",
            language: "de",
            enableVoiceCommands: false
        )
        XCTAssertEqual(result, "Das kostet 110 Euro.",
            "Phase 39/D-07: voice commands OFF must not disable ordinary self-correction")
    }

    /// An empty rules-cleaned baseline is the honest outcome of "delete
    /// everything I just said" — pinned so a later well-meaning "restore
    /// the text if the result is empty" patch would resurrect content the
    /// user explicitly scratched.
    ///
    /// DISABLED 2026-07-11 (enableScratchCommand = false; see CR-01/CR-02).
    /// Asserts passthrough because the gate is off.
    /// WHEN RE-ENABLED after gap closure, this MUST assert:
    ///   ""
    /// Do not re-enable the flag and leave this asserting passthrough.
    func testFullyScratchedUtteranceYieldsEmptyRulesCleanedBaseline() {
        let service = RulesCleanupService()
        let input = "We ship on Friday, scratch that."
        let result = service.clean(input, language: "en")
        XCTAssertEqual(result, input,
            "enableScratchCommand ships false (CR-01/CR-02) — must ABSTAIN, byte-identical")
    }

    /// German mirror of the toggle-off case.
    func testVoiceCommandsGermanToggleOffPassesPhraseThrough() {
        let service = RulesCleanupService()
        let result = service.clean(
            "Wir liefern am Freitag. Streich das.",
            language: "de",
            enableVoiceCommands: false
        )
        XCTAssertEqual(result, "Wir liefern am Freitag. Streich das.",
            "Phase 39/D-07: German voice commands OFF — command phrase must pass through literally")
    }
}
