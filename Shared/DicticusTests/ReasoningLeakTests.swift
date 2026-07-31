import XCTest
@testable import Dicticus

/// Phase 44 Plan 09 (T-44-25, SC-05): proves the three-deep reasoning-leak
/// defense — (a) `CleanupPrompt.build(..., reasoningPreclose:)`, (b)
/// `CleanupService.stopSequences`, (c) `CleanupService.stripReasoningBlock` —
/// makes a `<think>` preamble structurally incapable of reaching the
/// pasteboard, without changing the currently-shipping Qwen2.5 baseline.
///
/// `testStripReasoningBlockIsIdentityOnCleanText` is the false-positive
/// guard (T-44-27): a `stripReasoningBlock` that over-triggers on ordinary
/// text would discard every good LLM output, so it runs over the entire
/// `EditGuardFixtures.all` corpus rather than a hand-picked sample.
final class ReasoningLeakTests: XCTestCase {

    // MARK: - Layer (c): stripReasoningBlock

    func testStripReasoningBlockRemovesCompleteSpan() {
        let (text, leaked) = CleanupService.stripReasoningBlock(
            "<think>\nlet me consider\n</think>\n\nHallo Welt"
        )
        XCTAssertEqual(text, "Hallo Welt")
        XCTAssertFalse(leaked)
    }

    func testStripReasoningBlockFailsClosedOnBareOpen() {
        let input = "<think>\nlet me consider\n\nHallo Welt"
        let (text, leaked) = CleanupService.stripReasoningBlock(input)
        XCTAssertTrue(leaked, "a bare, unclosed <think> must fail closed")
        XCTAssertEqual(text, input, "no salvage — the caller discards, this function must not hand back a half-stripped string")
    }

    func testStripReasoningBlockFailsClosedOnStrayClose() {
        let input = "reasoning</think>Hallo"
        let (text, leaked) = CleanupService.stripReasoningBlock(input)
        XCTAssertTrue(leaked, "a stray closing </think> with no matching open must fail closed")
        XCTAssertEqual(text, input, "no salvage on a stray close either")
    }

    func testStripReasoningBlockIsIdentityOnCleanText() {
        // T-44-27: a false-positive leak flag would discard every good LLM
        // output. Run over the FULL shape cross-product fixture corpus, not
        // a hand-picked sample.
        for fixture in EditGuardFixtures.all {
            let (text, leaked) = CleanupService.stripReasoningBlock(fixture.candidate)
            XCTAssertFalse(leaked, "\(fixture.id): stripReasoningBlock false-flagged ordinary text as a leak")
            XCTAssertEqual(text, fixture.candidate, "\(fixture.id): stripReasoningBlock must not alter text with no <think>/</think>")
        }
    }

    // MARK: - Layer (b): stopSequences

    func testStopSequencesContainThinkTokens() {
        XCTAssertTrue(CleanupService.stopSequences.contains("<think>"))
        XCTAssertTrue(CleanupService.stopSequences.contains("</think>"))
    }

    // MARK: - Layer (a): the model-gated preclose

    func testPreCloseIsModelGated() {
        let withoutPreclose = CleanupPrompt.build(text: "hello", language: "en", reasoningPreclose: false)
        XCTAssertFalse(withoutPreclose.contains("<think>"))
        XCTAssertFalse(withoutPreclose.contains("</think>"))

        let withPreclose = CleanupPrompt.build(text: "hello", language: "en", reasoningPreclose: true)
        XCTAssertTrue(withPreclose.contains("<|im_start|>assistant\n<think>\n\n</think>\n\n<corrected_text>"),
                      "reasoningPreclose:true must emit the exact preclosed frame")
    }

    /// Acceptance criterion: `build(..., reasoningPreclose: false)` is
    /// byte-identical to the pre-Plan-09 shape — the Qwen2.5 baseline is
    /// untouched by adding this parameter.
    func testDefaultBuildUnaffectedByReasoningPrecloseParam() {
        let withDefault = CleanupPrompt.build(text: "hello world", language: "en")
        let withExplicitFalse = CleanupPrompt.build(text: "hello world", language: "en", reasoningPreclose: false)
        XCTAssertEqual(withDefault, withExplicitFalse)
        XCTAssertTrue(withDefault.hasSuffix("<|im_start|>assistant\n<corrected_text>"))
    }

    func testQwen25DoesNotGetThePreclose() {
        XCTAssertFalse(CleanupService.modelWantsReasoningPreclose("qwen2.5-3b-instruct-q4_k_m.gguf"))
        // Positive case, same gate: proves the check can actually fire, not
        // just that it stays off for Qwen2.5.
        XCTAssertTrue(CleanupService.modelWantsReasoningPreclose("qwen3.5-4b-instruct-q4_k_m.gguf"))
    }

    // MARK: - Injection defense (T-44-26)

    func testSanitizeControlTokensStripsDictatedThink() {
        XCTAssertEqual(CleanupPrompt.sanitizeControlTokens("think tag"), "think tag",
                      "ordinary dictated prose containing the word 'think' must be unaffected")

        let withOpen = CleanupPrompt.sanitizeControlTokens("before <think> after")
        XCTAssertFalse(withOpen.contains("<think>"), "a dictated literal <think> must be stripped before it reaches the model's context")

        let withClose = CleanupPrompt.sanitizeControlTokens("before </think> after")
        XCTAssertFalse(withClose.contains("</think>"), "a dictated literal </think> must be stripped before it reaches the model's context")
    }
}
