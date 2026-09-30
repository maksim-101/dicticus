import XCTest
@testable import Dicticus

/// Quick task 260930-s1d: a fuzzy brand match (dl >= 1) must not delete a
/// word-joining character (dot or hyphen) that the canonical does not have.
/// Whisper glued two words with a dot (live record ts 2026-09-27T04:15:14.358Z)
/// and the matcher scored the single glued token against a brand.
///
/// Every carrier sentence here is invented; Korvex and Zorbix stand in for
/// personal or model names. No dictation text is quoted. Uses the REAL bundled
/// lexicon via `BrandMatcher.bundledLexiconMatcher` with hermetic canonicals;
/// every assertion is an exact string.
@MainActor
final class BrandInteriorPunctuationTests: XCTestCase {

    static let canonicals: [String] = [
        "iCloud", "claude.ai", "Claude.MD", "Hostpoint.ch", "iTerm", "1Password", "CCMetrics"
    ]

    private func makeMatcher() -> BrandMatcher {
        BrandMatcher.bundledLexiconMatcher(canonicals: BrandInteriorPunctuationTests.canonicals)
    }

    // MARK: - Negatives: glued words must stay as dictated

    func testN1DotGluedNotRewrittenToICloud() {
        let s = "There is a note in.cloud about the backup."
        XCTAssertEqual(makeMatcher().apply(to: s, language: "en"), s)
    }

    func testN2DotGluedAtSentenceEndNotRewritten() {
        let s = "I saved the file in.cloud."
        XCTAssertEqual(makeMatcher().apply(to: s, language: "en"), s)
    }

    func testN3HyphenGluedNotRewritten() {
        let s = "There is a note in-cloud about the backup."
        XCTAssertEqual(makeMatcher().apply(to: s, language: "en"), s)
    }

    func testN4GermanDotGluedNotRewritten() {
        let s = "Da liegt eine Notiz in.cloud zum Backup."
        XCTAssertEqual(makeMatcher().apply(to: s, language: "de"), s)
    }

    func testN5SegmentDropNotRewritten() {
        let m = BrandMatcher.bundledLexiconMatcher(canonicals: ["Korvex"])
        let s = "Please open the Korvex-CH repository tomorrow."
        XCTAssertEqual(m.apply(to: s, language: "en"), s)
    }

    // MARK: - Controls: correct punctuation-bearing rewrites keep firing

    func testC1DottedSurfaceOntoDottedCanonical() {
        XCTAssertEqual(makeMatcher().apply(to: "Please ask cloud.ai about it.", language: "en"),
                       "Please ask claude.ai about it.")
    }

    func testC2DottedSurfaceAtSentenceEnd() {
        XCTAssertEqual(makeMatcher().apply(to: "Please ask Cloud.ai.", language: "en"),
                       "Please ask claude.ai.")
    }

    func testC3DottedSurfaceBeforeClause() {
        XCTAssertEqual(makeMatcher().apply(to: "Please ask Cloud.ai, then report back.", language: "en"),
                       "Please ask claude.ai, then report back.")
    }

    func testC4ClaudeMdUnchanged() {
        XCTAssertEqual(makeMatcher().apply(to: "Update Claude.MD today.", language: "en"),
                       "Update Claude.MD today.")
    }

    func testC5HostpointChUnchanged() {
        XCTAssertEqual(makeMatcher().apply(to: "Move it to Hostpoint.ch today.", language: "en"),
                       "Move it to Hostpoint.ch today.")
    }

    func testC6HyphenatedDlZeroReformat() {
        XCTAssertEqual(makeMatcher().apply(to: "Store it in 1-password please.", language: "en"),
                       "Store it in 1Password please.")
    }

    func testC7HyphenatedDlZeroReformatITerm() {
        XCTAssertEqual(makeMatcher().apply(to: "Open I-Term for me.", language: "en"),
                       "Open iTerm for me.")
    }

    func testC8ApostropheDlOneRepair() {
        XCTAssertEqual(makeMatcher().apply(to: "Check the CCMetrix's dashboard.", language: "en"),
                       "Check the CCMetrics dashboard.")
    }

    func testC9UndottedWindowOntoDottedCanonical() {
        XCTAssertEqual(makeMatcher().apply(to: "Update Claude MD today.", language: "en"),
                       "Update Claude.MD today.")
    }

    // MARK: - Digit-flanked dot is a version/decimal point, not a word join

    func testD1DigitFlankedDotStillRepairs() {
        let m = BrandMatcher.bundledLexiconMatcher(canonicals: ["Zorbix 4 E2B"])
        XCTAssertEqual(m.apply(to: "I think I should have Zorbix 4.2EB.", language: "en"),
                       "I think I should have Zorbix 4 E2B.")
    }
}
