import XCTest
@testable import Dicticus

/// LevenshteinDistance unit tests (Phase 20.01 — Wave 0 RED).
///
/// These tests reference `LevenshteinDistance` which does NOT exist yet —
/// the type lands in plan 20.02 at `Shared/Utilities/LevenshteinDistance.swift`.
/// The test target will FAIL TO BUILD until plan 02 ships the implementation.
/// That is the planner-required RED state.
///
/// Contract being locked:
///   ```
///   public enum LevenshteinDistance {
///       public static func distance(_ s1: String, _ s2: String) -> Int
///       public static func normalizedDistance(_ s1: String, _ s2: String) -> Double
///   }
///   ```
/// `normalizedDistance` returns a value in `[0.0, 1.0]` using `max(s1.count, s2.count)`
/// as the denominator. This is the CleanupService Levenshtein-gate signal.
final class LevenshteinDistanceTests: XCTestCase {

    // MARK: - distance: identity / empty cases

    func testDistanceEmptyEmpty() {
        XCTAssertEqual(LevenshteinDistance.distance("", ""), 0)
    }

    func testNormalizedDistanceEmptyEmpty() {
        // Both empty: zero distance, zero normalized distance (0/0 must
        // resolve to 0.0, not NaN — implementation contract).
        XCTAssertEqual(LevenshteinDistance.normalizedDistance("", ""), 0.0,
                       accuracy: 0.0001)
    }

    func testDistanceIdentical() {
        XCTAssertEqual(LevenshteinDistance.distance("abc", "abc"), 0)
        XCTAssertEqual(LevenshteinDistance.normalizedDistance("abc", "abc"),
                       0.0, accuracy: 0.0001)
    }

    // MARK: - distance: single-edit cases

    func testDistanceSingleSubstitution() {
        // abc → abd: 1 substitution.
        XCTAssertEqual(LevenshteinDistance.distance("abc", "abd"), 1)
        XCTAssertEqual(LevenshteinDistance.normalizedDistance("abc", "abd"),
                       1.0 / 3.0, accuracy: 0.0001)
    }

    func testDistanceEmptyVsNonEmpty() {
        XCTAssertEqual(LevenshteinDistance.distance("", "abc"), 3)
        XCTAssertEqual(LevenshteinDistance.distance("abc", ""), 3)
        XCTAssertEqual(LevenshteinDistance.normalizedDistance("", "abc"),
                       1.0, accuracy: 0.0001,
                       "Empty vs len-3 must report normalized distance 1.0")
    }

    // MARK: - Hallucination-detection signal cases

    /// Documents that morpheme-level hallucinations like "ausgeflogen" (flew out)
    /// vs. "ausgezogen" (moved out) are NOT distinguishable by edit distance.
    /// The gate cannot catch this; tests here are the contract documentation
    /// that the gate is intentionally coarse.
    func testDistanceMorphemeHallucinationSlipsThrough() {
        let d = LevenshteinDistance.distance("ausgeflogen", "ausgezogen")
        XCTAssertLessThanOrEqual(d, 3,
            "Morpheme-level hallucination ausgeflogen↔ausgezogen has distance ≤ 3 — gate cannot detect it. Documents the gate's intentional coarseness.")
    }

    /// Word-substitution hallucination (Franken→Euro) IS detectable by edit
    /// distance. This is the gate's primary signal.
    func testDistanceWordSubstitutionDetected() {
        let d = LevenshteinDistance.distance("Franken", "Euro")
        XCTAssertGreaterThanOrEqual(d, 5,
            "Word-substitution hallucination Franken↔Euro has distance ≥ 5 — gate catches it.")
    }

    // MARK: - Unicode handling

    /// Composed-form characters must count as a single grapheme. café (with
    /// é as U+00E9) vs cafe must be distance 1. If the impl walked
    /// utf8 bytes naively, this would be 2.
    func testDistanceUnicodeGraphemeAware() {
        XCTAssertEqual(LevenshteinDistance.distance("café", "cafe"), 1,
                       "Unicode é (U+00E9) must count as a single grapheme — distance 1, not 2")
    }

    // MARK: - Two-row optimization regression

    /// Long-vs-short input — the standard memory-optimized two-row variant
    /// can have off-by-one bugs at the m·n boundary. This is a smoke test
    /// that the implementation handles asymmetric lengths correctly.
    func testDistanceLongVsShort() {
        let long = String(repeating: "a", count: 50)
        let short = String(repeating: "a", count: 10)
        // Pure deletions on the long side: distance == 40.
        XCTAssertEqual(LevenshteinDistance.distance(long, short), 40,
                       "Two-row optimization must handle asymmetric lengths (50 vs 10 a's → 40 deletions)")
    }

    func testDistanceLongVsShortReversed() {
        // Symmetry: distance(a, b) == distance(b, a).
        let long = String(repeating: "a", count: 50)
        let short = String(repeating: "a", count: 10)
        XCTAssertEqual(LevenshteinDistance.distance(short, long), 40)
    }

    // MARK: - Normalized denominator semantics

    /// Normalized distance uses max(len(s1), len(s2)) as denominator —
    /// NOT min, NOT sum, NOT (len1+len2)/2. The CleanupService gate threshold
    /// 0.30 is calibrated against this specific normalization.
    func testNormalizedDistanceUsesMaxLengthDenominator() {
        // distance("hello", "") == 5; max(5, 0) == 5; normalized = 5/5 = 1.0.
        XCTAssertEqual(LevenshteinDistance.normalizedDistance("hello", ""),
                       1.0, accuracy: 0.0001)
        // distance("hello", "h") == 4; max(5, 1) == 5; normalized = 4/5 = 0.8.
        XCTAssertEqual(LevenshteinDistance.normalizedDistance("hello", "h"),
                       0.8, accuracy: 0.0001)
    }
}
