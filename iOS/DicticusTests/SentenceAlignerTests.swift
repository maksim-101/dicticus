import XCTest
@testable import Dicticus

/// Phase 36.6 Plan 08 (R-02 / CLEANRD-03): sentence-alignment utility for the
/// Plan 09 per-sentence phonetic gate.
///
/// Covers 1:1 alignment, the MERGE and SPLIT shapes CONTEXT.md flagged as a
/// "known open problem," the degenerate single-sentence case, graceful
/// handling of empty input, the mean-Jaccard degrade/fallback rule, and
/// lossless reconstruction of the baseline text from its windows.
///
/// Byte-identical with iOS/DicticusTests/SentenceAlignerTests.swift per
/// cross-platform test convention (Shared/ changes ship macOS + iOS
/// together).
///
/// @MainActor: `SentenceAligner.align` is `@MainActor`-isolated (it calls
/// `CleanupService.tokenizeForDialectGate`, declared on the `@MainActor`
/// `CleanupService` class).
@MainActor
final class SentenceAlignerTests: XCTestCase {

    // MARK: - 1:1 alignment

    func testOneToOneAlignmentReturnsTwoWindows() {
        let baseline = "The weather is nice today. I might go for a walk."
        let output = "The weather is nice today. I might go for a walk."

        let windows = SentenceAligner.align(baseline: baseline, output: output)

        XCTAssertEqual(windows.count, 2, "N==M should align 1:1, not degrade")
        XCTAssertTrue(windows[0].baseline.contains("weather"))
        XCTAssertTrue(windows[0].output.contains("weather"))
        XCTAssertTrue(windows[1].baseline.contains("walk"))
        XCTAssertTrue(windows[1].output.contains("walk"))
    }

    // MARK: - MERGE (N=2, M=1 — LLM merged two sentences into one)

    func testMergeCaseReturnsSingleWindowPairingBothBaselineSentences() {
        let baseline = "The weather is nice today. I might go for a walk."
        let output = "The weather is nice today, so I might go for a walk."

        let windows = SentenceAligner.align(baseline: baseline, output: output)

        XCTAssertEqual(windows.count, 1, "N=2,M=1 merge collapses to a single whole-utterance window")
        XCTAssertEqual(windows[0].baseline, baseline)
        XCTAssertEqual(windows[0].output, output)
    }

    // MARK: - SPLIT (N=1, M=2 — LLM split a run-on into two sentences)

    func testSplitCaseReturnsSingleWindowPairingBaselineAgainstBothOutputs() {
        let baseline = "The weather is nice today so I might go for a walk."
        let output = "The weather is nice today. So I might go for a walk."

        let windows = SentenceAligner.align(baseline: baseline, output: output)

        XCTAssertEqual(windows.count, 1, "N=1,M=2 split collapses to a single whole-utterance window")
        XCTAssertEqual(windows[0].baseline, baseline)
        XCTAssertEqual(windows[0].output, output)
    }

    // MARK: - DEGENERATE (single sentence on either side)

    func testDegenerateSingleSentenceReturnsOneWholeUtteranceWindow() {
        let baseline = "one sentence only"
        let output = "one sentence only."

        let windows = SentenceAligner.align(baseline: baseline, output: output)

        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].baseline, baseline)
        XCTAssertEqual(windows[0].output, output)
    }

    // MARK: - Empty input (graceful no-op, never a crash)

    func testEmptyBaselineReturnsOneWindowNoCrash() {
        let windows = SentenceAligner.align(baseline: "", output: "x")

        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].baseline, "")
        XCTAssertEqual(windows[0].output, "x")
    }

    func testEmptyOutputReturnsOneWindowNoCrash() {
        let windows = SentenceAligner.align(baseline: "x", output: "")

        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].baseline, "x")
        XCTAssertEqual(windows[0].output, "")
    }

    // MARK: - DEGRADE (low-confidence alignment falls back to whole-utterance)

    func testMismatchedContentDegradesToWholeUtteranceWindow() {
        let baseline = "The cat sat on the mat. It was warm."
        let output = "Quantum entanglement. Ferromagnetism. Photosynthesis."

        let windows = SentenceAligner.align(baseline: baseline, output: output)

        XCTAssertEqual(windows.count, 1, "Near-zero mean-Jaccard overlap must degrade to a single window")
        XCTAssertEqual(windows[0].baseline, baseline)
        XCTAssertEqual(windows[0].output, output)
    }

    // MARK: - Reconstruction losslessness

    func testConcatenatingBaselineWindowsReproducesBaselineContentInOrder() {
        let baseline = "The weather is nice today. I might go for a walk."
        let output = "The weather is nice today. I might go for a walk."

        let windows = SentenceAligner.align(baseline: baseline, output: output)
        let reconstructed = windows.map(\.baseline).joined()

        XCTAssertEqual(
            reconstructed.trimmingCharacters(in: .whitespacesAndNewlines),
            baseline.trimmingCharacters(in: .whitespacesAndNewlines),
            "Concatenating window.baseline in order must reproduce the original baseline text"
        )
    }
}
