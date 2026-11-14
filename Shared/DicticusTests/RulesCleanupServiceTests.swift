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

    // MARK: - Slice 60: a pause period becomes a comma

    func testPausePeriod_lowercaseContinuation_becomesComma() {
        let service = RulesCleanupService()
        XCTAssertEqual(
            service.clean("The tool is rewriting some of my notes. in a way that changes them.", language: "en"),
            "The tool is rewriting some of my notes, in a way that changes them.")
        XCTAssertEqual(
            service.clean("Und wie wir das abbilden wollen. in unserer eigenen Karte.", language: "de"),
            "Und wie wir das abbilden wollen, in unserer eigenen Karte.")
    }

    func testPausePeriod_capitalisedContinuation_stays() {
        let service = RulesCleanupService()
        let input = "The tool is rewriting some of my notes. In a way that changes them."
        XCTAssertEqual(service.clean(input, language: "en"), input)
    }

    func testPausePeriod_abbreviationsNumbersAndEllipsesStay() {
        let service = RulesCleanupService()
        for input in [
            "Das Element wächst bzw. das andere beginnt.",
            "Take the files, logs, etc. and move them.",
            "Use a checker, e.g. the system one, first.",
            "Am 3. und 4. des Monats läuft es.",
            "Otherwise... tests like these are shaky.",
            "What about the next one? maybe later.",
        ] {
            XCTAssertEqual(service.clean(input, language: input.contains("Das") || input.contains("Am ") ? "de" : "en"), input,
                           "must stay unchanged: \(input)")
        }
    }

    func testPausePeriod_isIdempotent() {
        let service = RulesCleanupService()
        let once = service.clean("First part of the thought. then the second part. and a third.", language: "en")
        XCTAssertEqual(once, "First part of the thought, then the second part, and a third.")
        XCTAssertEqual(service.clean(once, language: "en"), once)
    }

    // MARK: - Scratch phrases are dictated content

    // "scratch that" and "streich das" are not voice commands: the rules
    // cleanup passes them through byte-identical. ("scratch that" stays a
    // comma-path self-correction connector, see SelfCorrectionResolverTests.)

    func testScratchPhrasePassesThroughRulesCleanup() {
        let service = RulesCleanupService()
        let input = "The report is done. We ship on Friday. Scratch that."
        let result = service.clean(input, language: "en")
        XCTAssertEqual(result, input,
            "scratch phrases are dictated content — must pass through byte-identical")
    }

    /// An ordinary Phase-43 self-correction still resolves.
    func testCleanResolvesClassicSelfCorrection() {
        let service = RulesCleanupService()
        let result = service.clean(
            "Das kostet 110 Franken, ich meine 110 Euro.",
            language: "de"
        )
        XCTAssertEqual(result, "Das kostet 110 Euro.",
            "ordinary self-correction must still resolve")
    }

    func testFullyScratchedUtterancePassesThroughRulesCleanup() {
        let service = RulesCleanupService()
        let input = "We ship on Friday, scratch that."
        let result = service.clean(input, language: "en")
        XCTAssertEqual(result, input,
            "scratch phrases are dictated content — must pass through byte-identical")
    }

    func testGermanScratchPhrasePassesThroughRulesCleanup() {
        let service = RulesCleanupService()
        let result = service.clean(
            "Wir liefern am Freitag. Streich das.",
            language: "de"
        )
        XCTAssertEqual(result, "Wir liefern am Freitag. Streich das.",
            "scratch phrases are dictated content — must pass through byte-identical")
    }
}
