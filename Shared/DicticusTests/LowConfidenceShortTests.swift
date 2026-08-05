import XCTest
@testable import Dicticus

// Pure-logic tests for the SPIKE-PROVISIONAL low-confidence-short garble
// detector (quick task 260805-qx7). Drives
// LowConfidenceShort.flag(durationSeconds:avgLogProbs:) directly over [Float]
// values — no WhisperKit import, no live WhisperKit instance, no
// TranscriptionSegment construction required. Shared between macOS and iOS
// test targets since the predicate is pure logic, following the house style
// of NoSpeechDiscardTests.swift.
final class LowConfidenceShortTests: XCTestCase {

    func testGarbleShapeFlags() {
        // 2.6s, mean avg_log_prob -0.435 — the shape of the four hand-found
        // Aug 2-5 garbles (2.3-3.3s, -0.39...-0.47).
        XCTAssertTrue(
            LowConfidenceShort.flag(durationSeconds: 2.6, avgLogProbs: [-0.42, -0.45]),
            "Short duration + low mean confidence should flag as a garble candidate"
        )
    }

    func testShortCleanCommandDoesNotFlag() {
        // The adversarial negative class: short, confident, genuinely clean.
        XCTAssertFalse(
            LowConfidenceShort.flag(durationSeconds: 2.1, avgLogProbs: [-0.22]),
            "A short but confident command must not be flagged"
        )
    }

    func testLongLowConfidenceDoesNotFlag() {
        // Duration gate dominates: 12.0s exceeds the 5.0s max, regardless of score.
        XCTAssertFalse(
            LowConfidenceShort.flag(durationSeconds: 12.0, avgLogProbs: [-0.44]),
            "Duration gate must exclude long clips even with a low mean score"
        )
    }

    func testEmptyAvgLogProbsDoesNotFlag() {
        // Deliberately DIVERGES from NoSpeechDiscard's vacuous-true default: an
        // empty segment list is already owned by the noResult guard, so a
        // no-evidence record must not be reported as low-confidence.
        XCTAssertFalse(
            LowConfidenceShort.flag(durationSeconds: 2.0, avgLogProbs: []),
            "Empty avgLogProbs must not flag — no evidence is not low-confidence evidence"
        )
    }

    func testDurationBoundaryIsStrictlyLessThan() {
        // Exactly 5.0s should NOT pass the < 5.0 duration gate.
        XCTAssertFalse(
            LowConfidenceShort.flag(durationSeconds: 5.0, avgLogProbs: [-0.99]),
            "Duration exactly at the max-duration boundary must not flag (strict <)"
        )
    }

    func testScoreBoundaryIsStrictlyLessThan() {
        // Mean exactly -0.35 should NOT pass the < -0.35 threshold gate.
        XCTAssertFalse(
            LowConfidenceShort.flag(durationSeconds: 2.0, avgLogProbs: [-0.35]),
            "Mean score exactly at the threshold boundary must not flag (strict <)"
        )
    }

    func testUsesArithmeticMeanNotMinOrMax() {
        // Mean of [-0.10, -0.54] is -0.32: false at the default -0.35
        // threshold but true once the threshold is injected at -0.30. Pins
        // arithmetic-mean semantics against a future "use the worst segment"
        // drift, since min(-0.10, -0.54) = -0.54 would flag at the default
        // threshold and max(-0.10, -0.54) = -0.10 would never flag at all.
        //
        // Deliberately NOT using a mean that lands exactly on -0.35 (e.g.
        // [-0.10, -0.60]): Float32 addition/division on -0.10 and -0.60
        // rounds the computed mean to -0.350000024, one ULP past the -0.35
        // literal used as the default threshold, so the boundary would flip
        // depending on rounding rather than on the arithmetic-mean-vs-min/max
        // distinction this test exists to pin. testScoreBoundaryIsStrictlyLessThan
        // already covers the exact--0.35 boundary with a single segment, where
        // no addition/division occurs and the literal is bit-identical.
        XCTAssertFalse(
            LowConfidenceShort.flag(durationSeconds: 2.0, avgLogProbs: [-0.10, -0.54]),
            "Mean -0.32 must not flag at the default -0.35 threshold"
        )
        XCTAssertTrue(
            LowConfidenceShort.flag(durationSeconds: 2.0, avgLogProbs: [-0.10, -0.54], threshold: -0.30),
            "Mean -0.32 must flag once the injected threshold is raised to -0.30"
        )
    }
}
