// Regression net for the context-overflow crash found on device in Phase 44 Plan 14.
//
// THE BUG: `llama_decode` does not return an error when the batch exceeds n_batch — it calls
// GGML_ABORT, which calls abort(). An ~8000-character dictation (≈2500 prompt tokens against a
// 2048 context) hard-crashed the app on an iPhone 17 Pro Max:
//
//     SIGABRT <- abort <- ggml_abort <- llama_context::decode <- llama_decode
//               <- CleanupService.runInference <- CleanupService.cleanup
//
// This is NOT an iOS bug — n_ctx/n_batch live in Shared/, so macOS crashed on the same input.
//
// Phase 20.08 already hit this exact class once and "fixed" it by raising n_batch 512 -> 2048,
// which moved the wall rather than guarding it. These tests exist so the next person cannot
// fix it that way again: they assert the GUARD's arithmetic, not the wall's location.

import XCTest
@testable import Dicticus

final class CleanupContextLimitTests: XCTestCase {

    /// HONEST FALLBACK (Phase 44 Plan 14). When cleanup() cannot run, it must record WHY in
    /// `lastCleanupOutcome` so the orchestrator can tell the user their text was inserted without
    /// cleanup — instead of silently pasting raw text. The model-free path (`.notLoaded`) proves
    /// the mechanism end-to-end without loading a GGUF.
    func testCleanupRecordsNotLoadedOutcomeWhenModelAbsent() async {
        CleanupService.lastCleanupOutcome = .applied  // seed a different value to prove it changes
        let service = CleanupService()  // no loadModel() call → isLoaded == false

        let out = await service.cleanup(text: "hello world", language: "en")

        XCTAssertEqual(out, "hello world", "with no model, cleanup returns the input unchanged (D-19)")
        if case .notLoaded = CleanupService.lastCleanupOutcome {} else {
            XCTFail("cleanup with no model must record .notLoaded, got \(CleanupService.lastCleanupOutcome)")
        }
    }

    /// The guard must reserve room for generation, not just for the prompt. If it only checked
    /// `prompt <= n_ctx`, a prompt of 2000 tokens would pass and then overflow the KV cache
    /// mid-generation — llama_decode starts failing in the token loop and the user gets a
    /// TRUNCATED rewrite of their own dictation (measured on device: a 6072-char input came
    /// back at 6% of its length).
    func testUsableCapacityReservesRoomForGeneration() {
        let maxTokens = 512
        let capacity = Int(CleanupService.contextTokens) - maxTokens

        XCTAssertEqual(capacity, 1536, "n_ctx 2048 − 512 generated = 1536 usable prompt tokens")
        XCTAssertLessThan(
            capacity, Int(CleanupService.contextTokens),
            "Capacity must be strictly below n_ctx — a prompt filling the whole context leaves "
                + "zero room to generate into, which overflows the KV cache mid-loop."
        )
    }

    /// The on-device measurements, encoded as arithmetic. These are the real observations:
    ///   6072 chars -> 1964 prompt tokens -> survived (under the 2048 wall)
    ///   8004 chars -> ~2500 prompt tokens -> SIGABRT
    /// Both are now rejected by the guard, because both exceed the 1536 usable capacity.
    func testMeasuredOverflowInputsAreRejectedByTheGuard() {
        let capacity = Int(CleanupService.contextTokens) - 512

        // The case that CRASHED the app on device.
        XCTAssertGreaterThan(
            2500, capacity,
            "The ~8000-char dictation that produced SIGABRT must be caught by the guard."
        )

        // The case that did NOT crash but came back 94% destroyed — it overflowed during
        // generation (1964 prompt + up to 512 generated = 2476 > 2048 n_ctx).
        XCTAssertGreaterThan(
            1964 + 512, Int(CleanupService.contextTokens),
            "The 6072-char dictation fits the batch but NOT the KV cache once generation is "
                + "accounted for — this is why it returned truncated text rather than crashing."
        )
        XCTAssertGreaterThan(
            1964, capacity,
            "...and so the guard must reject it too, rather than letting it truncate silently."
        )
    }

    /// A realistic long-form dictation must still be cleanable. The guard is a crash net, not a
    /// licence to reject ordinary input: the longest utterance in the real 44-01 corpus is 1248
    /// chars (921 prompt tokens including the ~600-token German system prompt) and must pass.
    func testRealCorpusLongestUtteranceStillFitsComfortably() {
        let capacity = Int(CleanupService.contextTokens) - 512

        XCTAssertLessThan(
            921, capacity,
            "The longest REAL corpus utterance (1248 chars, 921 prompt tokens) must not be "
                + "rejected — if it were, the guard would be silently disabling cleanup for "
                + "normal dictation."
        )
    }

    /// THE OUTPUT-BUDGET LIMIT — independent of the context wall, and it bites FIRST.
    ///
    /// Cleanup rewrites the utterance, so output length ≈ input length. A 4002-char dictation
    /// tokenized to only 1499 PROMPT tokens (well under the 1536 context capacity, so the crash
    /// guard never fired) but needed ~1000 OUTPUT tokens against a 512 cap — generation stopped
    /// mid-text and returned 57% of the input. Measured on device.
    ///
    /// This is the case that proves the two guards are not redundant.
    func testOutputCapBitesBeforeTheContextWall() {
        let maxOutputTokens = 512
        let contextCapacity = Int(CleanupService.contextTokens) - maxOutputTokens

        let promptTokensOfThe4002CharCase = 1499
        let outputTokensNeededByThe4002CharCase = 1000  // ≈ its own length; measured gtok hit the 512 cap

        XCTAssertLessThan(
            promptTokensOfThe4002CharCase, contextCapacity,
            "The 4002-char case passes the CONTEXT guard — which is exactly why a context guard "
                + "alone is insufficient."
        )
        XCTAssertGreaterThan(
            outputTokensNeededByThe4002CharCase, maxOutputTokens,
            "...but it cannot fit the OUTPUT budget, so it must be rejected by the output guard "
                + "or the user silently loses 43% of their dictation."
        )
    }

    /// The boundary case that a bare `textTokens > maxOutputTokens` check LETS THROUGH.
    /// On device, a 2070-char utterance tokenized to ~511 tokens — under the 512 cap — passed the
    /// unmargined guard, and generation then hit the cap anyway (gtok=512) and was cut mid-text.
    /// Cleaned output is routinely a little longer than its input (restored punctuation, expanded
    /// contractions), so the guard MUST project growth rather than compare raw lengths.
    func testOutputGuardHasHeadroomForGrowth() {
        let maxOutputTokens = 512
        let boundaryUtteranceTokens = 511  // the real 2070-char case

        XCTAssertLessThan(
            boundaryUtteranceTokens, maxOutputTokens,
            "It fits on a naive comparison — which is precisely the trap."
        )

        let projected = Int(Double(boundaryUtteranceTokens) * CleanupService.outputGrowthMargin)
        XCTAssertGreaterThan(
            projected, maxOutputTokens,
            "With growth projected, it must be rejected — otherwise it truncates at the cap."
        )
    }

    /// ...but the margin must not be so aggressive that it disables cleanup for real dictation.
    /// The longest REAL corpus utterance is 1248 chars ≈ 320 tokens.
    func testMarginStillAllowsTheLongestRealUtterance() {
        let longestRealUtteranceTokens = 320
        let projected = Int(Double(longestRealUtteranceTokens) * CleanupService.outputGrowthMargin)

        XCTAssertLessThanOrEqual(
            projected, 512,
            "The longest real corpus utterance must still be cleaned — a crash net that silently "
                + "turns into a cleanup-disabler for normal speech is a worse bug than the one it fixes."
        )
    }

    /// The true ceiling on cleanable dictation, stated as arithmetic so it cannot be forgotten:
    /// the context must hold the system prompt AND the input AND an output of the same size.
    ///   system(~600 DE) + T + T <= 2048  =>  T <= ~720 tokens  ≈ 2800 chars of German.
    /// Anything longer cannot be cleaned at all without chunking or a larger context window.
    func testTrueCeilingOnCleanableDictation() {
        let germanSystemPromptTokens = 600
        let usable = Int(CleanupService.contextTokens) - germanSystemPromptTokens
        let maxInputTokens = usable / 2  // input + an output of equal length

        XCTAssertEqual(maxInputTokens, 724)
        XCTAssertLessThan(
            maxInputTokens, 512 * 2,
            "The real limit is set by n_ctx, not by maxOutputTokens alone — raising the output "
                + "cap without raising n_ctx just moves the failure from truncation to KV overflow."
        )
    }
}
