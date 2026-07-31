import XCTest
@testable import Dicticus

// Pure-logic tests for the D-09 no-speech discard predicate (WHISP-03).
// Drives NoSpeechDiscard.looksLikeSilence(noSpeechProbs:threshold:) directly
// over [Float] values — no WhisperKit import, no live WhisperKit instance,
// no TranscriptionSegment construction required. Shared between macOS and
// iOS test targets since the discard predicate is pure logic. See
// 41-RESEARCH.md Pattern 3 for the production mechanism this pins.
final class NoSpeechDiscardTests: XCTestCase {

    func testAllHighProbsAboveThresholdDiscards() {
        let probs: [Float] = [0.8, 0.9, 0.95]
        XCTAssertTrue(
            NoSpeechDiscard.looksLikeSilence(noSpeechProbs: probs, threshold: 0.6),
            "All segments above threshold should be discarded as silence"
        )
    }

    func testAtLeastOneLowProbKeeps() {
        let probs: [Float] = [0.9, 0.2, 0.95]
        XCTAssertFalse(
            NoSpeechDiscard.looksLikeSilence(noSpeechProbs: probs, threshold: 0.6),
            "At least one segment below threshold means real speech was detected — must not discard"
        )
    }

    func testEmptyInputUsesDocumentedDegenerateDefault() {
        // Degenerate default: no segments means no evidence of speech, so the
        // predicate treats an empty result as silence (vacuously true, matching
        // Swift's Sequence.allSatisfy semantics used by the production
        // implementation — see 41-RESEARCH.md Pattern 3). NoSpeechDiscard must
        // document this default explicitly when it lands (41-04).
        XCTAssertTrue(
            NoSpeechDiscard.looksLikeSilence(noSpeechProbs: [], threshold: 0.6),
            "Empty noSpeechProbs should discard (vacuous-true default, documented in NoSpeechDiscard)"
        )
    }
}
