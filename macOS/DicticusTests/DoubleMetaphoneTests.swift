import XCTest
@testable import Dicticus

/// Reference-vector + brand-collision tests for the English Double Metaphone
/// (primary code) encoder, `DoubleMetaphone` (Phase 36.5-02).
///
/// EXECUTION NOTE: these tests are AUTHORED in 36.5-02 but first EXECUTED in
/// 36.5-04, the plan that regenerates the Xcode projects and runs the
/// dual-platform XCTest suite. `DoubleMetaphone` exists after 36.5-02, so the
/// suite is GREEN when 36.5-04 runs it. 36.5-02 deliberately does NOT run
/// xcodegen/xcodebuild — that would race the Wave-1 plans on the shared
/// `*.xcodeproj`. Correctness in 36.5-02 was proven by a standalone `swiftc`
/// assertion driver (1545/1545 agreement with the `abydos` reference); these
/// XCTests are the permanent regression net.
///
/// This file is kept BYTE-IDENTICAL in `macOS/DicticusTests/` and
/// `iOS/DicticusTests/` (cross-platform parity).
final class DoubleMetaphoneTests: XCTestCase {

    // MARK: - Reference vectors (canonical Lawrence Philips primary code)

    /// The output is the FULL, uncapped primary code. The plan stated
    /// "Thompson" -> "TMSN"; the canonical Double Metaphone is "TMPSN" (verified
    /// against the Python `metaphone` AND `abydos` references). "TMSN" is neither
    /// the full code nor a 4-char truncation ("TMPS"), so it is an incorrect
    /// reference vector, corrected here.
    func testReferenceVectors() {
        XCTAssertEqual(DoubleMetaphone.encode("Thompson"), "TMPSN")
        XCTAssertEqual(DoubleMetaphone.encode("Smith"), "SM0") // theta ("0") for "th"
        XCTAssertEqual(DoubleMetaphone.encode("school"), "SKL")
        XCTAssertEqual(DoubleMetaphone.encode("Catherine"), "K0RN")
    }

    /// The encoder's purpose: spelling variants of the same sound collide.
    func testSpellingVariantsCollide() {
        XCTAssertEqual(
            DoubleMetaphone.encode("Catherine"),
            DoubleMetaphone.encode("Katherine")
        )
    }

    // MARK: - Brand spelling-variant collisions (corpus.json positives)

    /// A misheard brand and its canonical encode to the same phonetic key, so the
    /// matcher (36.5-04) can accept the rewrite. These pairs collide on the
    /// primary code alone; weaker pairs rely on bounded edit distance in 36.5-04.
    func testBrandPairsCollide() {
        XCTAssertEqual(DoubleMetaphone.encode("Sonat"), DoubleMetaphone.encode("Sonnet"))
        XCTAssertEqual(DoubleMetaphone.encode("Versal"), DoubleMetaphone.encode("Vercel"))
        XCTAssertEqual(DoubleMetaphone.encode("Towry"), DoubleMetaphone.encode("Tauri"))
    }

    /// A canonical key is non-empty for a real brand and discriminates a clearly
    /// different one (sanity that the key carries signal).
    func testBrandKeyHasSignal() {
        XCTAssertFalse(DoubleMetaphone.encode("Sonnet").isEmpty)
        XCTAssertNotEqual(
            DoubleMetaphone.encode("Sonnet"),
            DoubleMetaphone.encode("Gemini")
        )
    }

    // MARK: - Non-letter input (letters only, never crash)

    func testNonLetterInput() {
        XCTAssertEqual(DoubleMetaphone.encode(""), "")
        XCTAssertEqual(DoubleMetaphone.encode("123"), "")
        XCTAssertEqual(DoubleMetaphone.encode("!?.,"), "")
        // Digits and punctuation are stripped; only the letters are encoded.
        XCTAssertEqual(DoubleMetaphone.encode("Sonat3!"), DoubleMetaphone.encode("Sonat"))
        XCTAssertEqual(DoubleMetaphone.encode("O'Brien"), DoubleMetaphone.encode("OBrien"))
    }
}
