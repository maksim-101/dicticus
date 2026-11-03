import XCTest
@testable import Dicticus

/// Reference-vector tests for the brand-matcher string utilities (Phase 36.5-01):
/// `BrandStringMetrics` (Damerau-Levenshtein OSA + Jaro-Winkler) and
/// `ColognePhonetic` (German Kölner Phonetik).
///
/// EXECUTION NOTE: these tests are AUTHORED in 36.5-01 but first EXECUTED in
/// 36.5-04, the plan that regenerates the Xcode projects and runs the
/// dual-platform XCTest suite. Both utilities exist after 36.5-01, so the suite
/// is GREEN when 36.5-04 runs it. 36.5-01 deliberately does NOT run
/// xcodegen/xcodebuild — that would race the three Wave-1 plans on the shared
/// `*.xcodeproj`. Correctness in 36.5-01 was proven by standalone `swiftc`
/// assertion drivers; these XCTests are the permanent regression net.
///
/// This file is kept BYTE-IDENTICAL in `macOS/DicticusTests/` and
/// `iOS/DicticusTests/` (cross-platform parity).
final class BrandPhoneticsTests: XCTestCase {

    // MARK: - BrandStringMetrics.damerauLevenshtein (OSA)

    func testDamerauLevenshteinIdentityAndEmpty() {
        XCTAssertEqual(BrandStringMetrics.damerauLevenshtein("Sonnet", "Sonnet"), 0)
        XCTAssertEqual(BrandStringMetrics.damerauLevenshtein("", ""), 0)
        XCTAssertEqual(BrandStringMetrics.damerauLevenshtein("", "abcd"), 4)
        XCTAssertEqual(BrandStringMetrics.damerauLevenshtein("abcd", ""), 4)
    }

    /// A clean adjacent transposition is a single OSA operation — the signal that
    /// distinguishes OSA from plain Levenshtein (which would score these 2).
    func testDamerauLevenshteinAdjacentTransposition() {
        XCTAssertEqual(BrandStringMetrics.damerauLevenshtein("ca", "ac"), 1)
        XCTAssertEqual(BrandStringMetrics.damerauLevenshtein("ab", "ba"), 1)
    }

    /// OSA semantics: "CA" → "ABC" is 3 because the transposed region cannot be
    /// edited a second time (Wikipedia's canonical OSA example). Unrestricted
    /// Damerau-Levenshtein would score it 2; the matcher uses OSA by design.
    func testDamerauLevenshteinOSARestriction() {
        XCTAssertEqual(BrandStringMetrics.damerauLevenshtein("ca", "abc"), 3)
    }

    func testDamerauLevenshteinSmallBrandMishearing() {
        XCTAssertLessThanOrEqual(BrandStringMetrics.damerauLevenshtein("Sonat", "Sonnet"), 2)
    }

    /// Grapheme correctness: a precomposed é (U+00E9) counts as one edit, not
    /// multiple UTF-8/UTF-16 code units.
    func testDamerauLevenshteinGraphemeAware() {
        XCTAssertEqual(BrandStringMetrics.damerauLevenshtein("café", "cafe"), 1)
    }

    // MARK: - BrandStringMetrics.jaroWinkler

    func testJaroWinklerContracts() {
        XCTAssertEqual(BrandStringMetrics.jaroWinkler("Tauri", "Tauri"), 1.0, accuracy: 0.0001)
        XCTAssertEqual(BrandStringMetrics.jaroWinkler("", ""), 1.0, accuracy: 0.0001)
        XCTAssertEqual(BrandStringMetrics.jaroWinkler("Tauri", ""), 0.0, accuracy: 0.0001)
        XCTAssertEqual(BrandStringMetrics.jaroWinkler("abc", "xyz"), 0.0, accuracy: 0.0001)
    }

    /// Classic published Jaro-Winkler reference vectors validate the standard
    /// algorithm (matching window, transposition count, prefix boost) exactly.
    func testJaroWinklerReferenceVectors() {
        XCTAssertEqual(BrandStringMetrics.jaroWinkler("MARTHA", "MARHTA"), 0.9611, accuracy: 0.0005)
        XCTAssertEqual(BrandStringMetrics.jaroWinkler("DWAYNE", "DUANE"), 0.84, accuracy: 0.0005)
        XCTAssertEqual(BrandStringMetrics.jaroWinkler("DIXON", "DICKSONX"), 0.8133, accuracy: 0.0005)
    }

    /// "Towry"/"Tauri" share only T and r, so standard Jaro-Winkler is ~0.64
    /// (NOT >0.8). The orthographic signal alone is weak here — in the real
    /// matcher the phonetic encoder carries this pair. The metric still ranks
    /// the true brand above a disjoint one.
    func testJaroWinklerWeakPairRanking() {
        XCTAssertEqual(BrandStringMetrics.jaroWinkler("Towry", "Tauri"), 0.64, accuracy: 0.01)
        XCTAssertGreaterThan(
            BrandStringMetrics.jaroWinkler("Towry", "Tauri"),
            BrandStringMetrics.jaroWinkler("Towry", "Gemini")
        )
    }

    func testJaroWinklerGraphemeIdentical() {
        XCTAssertEqual(BrandStringMetrics.jaroWinkler("café", "café"), 1.0, accuracy: 0.0001)
    }

    // MARK: - ColognePhonetic

    func testColognePhoneticReferenceVectors() {
        XCTAssertEqual(ColognePhonetic.encode("Müller"), "657")
        XCTAssertEqual(ColognePhonetic.encode("Wikipedia"), "3412")
        XCTAssertEqual(ColognePhonetic.encode("Breschnew"), "17863")
    }

    /// The encoder's purpose: spelling variants of the same sound collide.
    func testColognePhoneticVariantsCollide() {
        XCTAssertEqual(ColognePhonetic.encode("Meier"), "67")
        XCTAssertEqual(ColognePhonetic.encode("Mayer"), "67")
        XCTAssertEqual(ColognePhonetic.encode("Meier"), ColognePhonetic.encode("Mayer"))
    }

    /// Umlauts are classed as vowels (code 0), never ASCII-stripped. If ü were
    /// deleted, "Lül" would collapse to "5"; as a separating vowel it yields
    /// "55". This is the #1 port-correctness guard (Pitfall §4.1).
    func testColognePhoneticPreservesUmlauts() {
        XCTAssertEqual(ColognePhonetic.encode("Lül"), "55")
        XCTAssertFalse(ColognePhonetic.encode("Müller").isEmpty)
    }

    /// ß is treated as "ss".
    func testColognePhoneticEszett() {
        XCTAssertEqual(ColognePhonetic.encode("Straße"), ColognePhonetic.encode("Strasse"))
    }
}
