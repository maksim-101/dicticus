import XCTest
@testable import Dicticus

/// Phase 36.6 Plan 03 (CLEANRD-01 / CLEANRD-02): v-next prompt + ChatML contract tests.
///
/// Locks the "one coherent contract" invariant between CleanupPrompt.build() and
/// CleanupService's ChatML feed/stop/strip path: the prompt's framing must be
/// exactly what CleanupService tokenizes, stops on, and strips.
///
/// Byte-identical with iOS/DicticusTests/CleanupPromptVNextTests.swift per
/// cross-platform parity convention (Shared/ changes ship macOS + iOS together).
@MainActor
final class CleanupPromptVNextTests: XCTestCase {

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: CleanupPrompt.customInstructionKey)
        super.tearDown()
    }

    // MARK: - Task 1: EN branch + ChatML frame + few-shot-free skeleton

    func testEnPromptIsFewShotFree() {
        let prompt = CleanupPrompt.build(
            text: "Visually speaking, I liked your variants C, D and E the best.",
            language: "en"
        )
        XCTAssertFalse(prompt.contains("In: "), "v-next EN prompt must contain NO In:/Out: few-shot exemplar lines")
        XCTAssertFalse(prompt.contains("Out: "), "v-next EN prompt must contain NO In:/Out: few-shot exemplar lines")
        XCTAssertFalse(prompt.contains("# Editing rules"), "v-next EN prompt must not contain the old v20 few-shot skeleton section")
    }

    func testEnPromptContainsDictatedTextExactlyOnce() {
        let text = "Visually speaking, I liked your variants C, D and E the best."
        let prompt = CleanupPrompt.build(text: text, language: "en")
        let occurrences = prompt.components(separatedBy: text).count - 1
        XCTAssertEqual(occurrences, 1, "Dictated text must appear exactly once in the ChatML user turn")
    }

    func testEnPromptIsChatMLWrappedAndEndsOnAssistantAnchor() {
        let prompt = CleanupPrompt.build(text: "hello", language: "en")
        XCTAssertTrue(prompt.contains("<|im_start|>"), "v-next prompt must contain ChatML <|im_start|> markers")
        XCTAssertTrue(prompt.contains("<|im_end|>"), "v-next prompt must contain ChatML <|im_end|> markers")
        XCTAssertTrue(prompt.hasSuffix("<|im_start|>assistant\n<corrected_text>"),
                      "v-next prompt must end anchored on the assistant turn with the pre-filled <corrected_text> opener")
    }

    func testEnPromptContainsAntiInventionDirectives() {
        let prompt = CleanupPrompt.build(text: "test", language: "en")
        XCTAssertTrue(prompt.contains("iCloud"), "EN prompt must name iCloud as the canonical valid-word-preservation example")
        XCTAssertTrue(prompt.contains("C++") || prompt.contains("C#"), "EN prompt must prohibit single-letter expansion (C -> C++/C#)")
        XCTAssertTrue(prompt.contains("Never rewrite, rephrase, summarize, or translate"),
                      "EN prompt must explicitly prohibit rewrite/rephrase/summarize/translate")
        // Phase 42 Plan 03 (D-03/D-04): "Preserve substantive self-corrections
        // verbatim" was the contradictory old rule — replaced by the single
        // unambiguous self-correction rule.
        XCTAssertTrue(prompt.contains("keep only the corrected version"),
                      "EN prompt must instruct the single, unambiguous self-correction rule")
        XCTAssertTrue(prompt.contains("Never change how numbers are written"),
                      "EN prompt must retain the flat number prohibition")
    }

    func testCurrentVersionIsNotV20() {
        // Phase 36.6 Rethink Plan 07: bumped again v-next -> v-brave (R-01/R-03).
        // Phase 42 Plan 03: bumped again v-brave -> v-transcriptionist (D-01).
        XCTAssertNotEqual(CleanupPrompt.currentVersion, "v20", "currentVersion must be bumped off v20")
        XCTAssertNotEqual(CleanupPrompt.currentVersion, "v-next", "currentVersion must be bumped off v-next for the brave prompt")
        XCTAssertNotEqual(CleanupPrompt.currentVersion, "v-brave", "currentVersion must be bumped off v-brave for the Transcriptionist prompt")
        XCTAssertEqual(CleanupPrompt.currentVersion, "v-transcriptionist")
    }

    func testDefaultInstructionReferencesCurrentVersion() {
        // Phase 36.6 Rethink Plan 07: doc string updated in lockstep with v-brave.
        // Phase 42 Plan 03: doc string updated in lockstep with v-transcriptionist.
        XCTAssertFalse(CleanupPrompt.defaultInstruction.contains("v20"))
        XCTAssertFalse(CleanupPrompt.defaultInstruction.contains("v-next"))
        XCTAssertFalse(CleanupPrompt.defaultInstruction.contains("v-brave"))
        XCTAssertTrue(CleanupPrompt.defaultInstruction.contains("v-transcriptionist"))
    }

    func testDictionaryWrapperNoLongerInjectedIntoUserTurn() {
        // Phase 36.6 Rethink Plan 07 (R-03): INVERTED from the v-next pin.
        // The "Known terms — ... EXACTLY as shown" wrapper was the P1 on-device
        // UAT leak vector (Qwen regurgitated it to the user's cursor) and is
        // removed at source; term spelling is owned by the deterministic
        // pre-LLM DictionaryService + BrandMatcher.
        let context = ["swiss quote": "Swissquote"]
        let prompt = CleanupPrompt.build(text: "I use swiss quote", language: "en", dictionaryContext: context)
        XCTAssertFalse(prompt.contains("spelled EXACTLY as shown"))
        XCTAssertFalse(prompt.contains("swiss quote -> Swissquote"))
        XCTAssertFalse(prompt.contains("Known terms"))
    }

    // MARK: - Task 2: DE branch — native German, few-shot-free, Swiss ss

    func testDePromptIsFewShotFree() {
        let prompt = CleanupPrompt.build(
            text: "Ich glaube, aktuell ist nur bei einem Leih Prinzip wirklich die Rede von KI ...",
            language: "de"
        )
        XCTAssertFalse(prompt.contains("In: "), "v-next DE prompt must contain NO In:/Out: few-shot exemplar lines")
        XCTAssertFalse(prompt.contains("Out: "), "v-next DE prompt must contain NO In:/Out: few-shot exemplar lines")
        XCTAssertFalse(prompt.contains("Das Meeting ist um fünf"), "The leak-source DE few-shot exemplar must be gone (track-A fix)")
        XCTAssertFalse(prompt.contains("Kannst du mir sagen, wie spät es ist"), "The leak-source DE few-shot exemplar must be gone (track-A fix)")
    }

    func testDePromptIsNativeGerman() {
        let prompt = CleanupPrompt.build(text: "x", language: "de")
        XCTAssertTrue(prompt.contains("Du bist der Transkriptions-Editor von Dicticus"),
                      "DE branch identity must be native German (language-drift defense)")
        XCTAssertTrue(prompt.contains("Feste Grenzen"), "DE branch hard-limits header must be native German")
    }

    func testDePromptContainsGermanAntiInventionDirectives() {
        let prompt = CleanupPrompt.build(text: "x", language: "de")
        XCTAssertTrue(prompt.contains("iCloud"), "DE prompt must name iCloud as the canonical valid-word-preservation example")
        XCTAssertTrue(prompt.contains("C++") || prompt.contains("C#"), "DE prompt must prohibit single-letter expansion")
        XCTAssertTrue(prompt.contains("Schreibe niemals um"), "DE prompt must prohibit rewriting")
        XCTAssertTrue(prompt.contains("übersetze niemals"), "DE prompt must prohibit translation")
        // Phase 42 Plan 03 (D-03/D-04): "Bewahre inhaltliche Selbstkorrekturen
        // wörtlich" was the contradictory old rule — replaced by the single
        // unambiguous self-correction rule.
        XCTAssertTrue(prompt.contains("nur die korrigierte Fassung"),
                      "DE prompt must instruct the single, unambiguous self-correction rule")
        XCTAssertTrue(prompt.contains("Zahlen niemals umformen"), "DE prompt must retain the flat number prohibition")
    }

    func testDePromptSwissOrthographyBannerWhenEnabled() {
        let p = CleanupPrompt.build(text: "x", language: "de", useSwissGerman: true)
        XCTAssertTrue(p.contains("Schweizer Orthographie: ss statt ß."),
                      "Swiss orthography banner must appear when useSwissGerman=true")
    }

    func testDePromptNoSwissBannerWhenDisabled() {
        let p = CleanupPrompt.build(text: "x", language: "de", useSwissGerman: false)
        XCTAssertFalse(p.contains("Schweizer Orthographie"),
                       "Swiss banner must be absent when useSwissGerman=false")
    }

    func testDePromptIsChatMLFramedIdenticallyToEn() {
        let p = CleanupPrompt.build(text: "x", language: "de")
        XCTAssertTrue(p.contains("<|im_start|>system"))
        XCTAssertTrue(p.contains("<|im_start|>user"))
        XCTAssertTrue(p.hasSuffix("<|im_start|>assistant\n<corrected_text>"))
    }

    func testEnglishBranchHasNoGermanBanner() {
        let p = CleanupPrompt.build(text: "x", language: "en")
        XCTAssertFalse(p.contains("Sprache: Standard-Hochdeutsch"), "German banner must NOT appear in English branch")
    }

    // MARK: - Task 3: CleanupService ChatML-aware stripPreamble

    func testStripPreambleRemovesFullChatMLEnvelope() {
        let model = "<corrected_text>Cleaned text.</corrected_text><|im_end|>"
        XCTAssertEqual(CleanupService.stripPreamble(model), "Cleaned text.")
    }

    func testStripPreambleScrubsLeadingAssistantRoleMarker() {
        let model = "<|im_start|>assistant\nHello, world.</corrected_text>"
        let out = CleanupService.stripPreamble(model)
        XCTAssertEqual(out, "Hello, world.")
        XCTAssertFalse(out.contains("<|im_start|>"))
        XCTAssertFalse(out.contains("assistant"))
    }

    func testStripPreambleScrubsBareImEndMarker() {
        let model = "Hello, world.</corrected_text><|im_end|>"
        let out = CleanupService.stripPreamble(model)
        XCTAssertEqual(out, "Hello, world.")
        XCTAssertFalse(out.contains("<|im_end|>"))
    }

    func testStripPreambleScrubsImEndInsideTruncatedEnvelope() {
        // Case 2 (opening-only envelope, model truncated before the closing tag):
        // a trailing <|im_end|> lands INSIDE the extracted content and must be
        // scrubbed by the ChatML regex, not just discarded by envelope extraction.
        let model = "<corrected_text>Hello, world.<|im_end|>"
        let out = CleanupService.stripPreamble(model)
        XCTAssertEqual(out, "Hello, world.")
        XCTAssertFalse(out.contains("<|im_end|>"))
    }

    func testStripPreambleScrubsBothChatMLMarkersWithNoEnvelopeTags() {
        // Case 4 (no <corrected_text> tags at all — passthrough): both the
        // leading role marker and the trailing EOG marker must be scrubbed.
        let model = "<|im_start|>assistant\nHello.<|im_end|>"
        let out = CleanupService.stripPreamble(model)
        XCTAssertEqual(out, "Hello.")
        XCTAssertFalse(out.contains("<|im_start|>"))
        XCTAssertFalse(out.contains("<|im_end|>"))
    }

    func testStripPreambleUserAngleBracketContentSurvives() {
        // Closed-list scrub must not clobber genuine user-dictated angle-bracket content.
        XCTAssertEqual(
            CleanupService.stripPreamble("use the <div> tag in HTML"),
            "use the <div> tag in HTML"
        )
    }
}
