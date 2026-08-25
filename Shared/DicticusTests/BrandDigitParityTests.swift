import XCTest
@testable import Dicticus

/// Quick task 260825-pt5 — guard B: a fuzzy match whose canonical carries a
/// digit sequence the spoken window does not (or vice versa) fabricates or
/// drops a version/model identity — a meaning change, not a spelling repair
/// ("FIBAL." -> "Fable 5" invents a "5"; "a USB-5" -> "USB-A" and "iTerm2." ->
/// "iTerm" both drop a digit the speaker said).
///
/// Uses the REAL bundled lexicon via `BrandMatcher.bundledLexiconMatcher` so
/// the guard is proven against production data. Every assertion is an EXACT
/// string — `contains` cannot see deleted/invented content.
@MainActor
final class BrandDigitParityTests: XCTestCase {

    static let canonicals: [String] = [
        "USB-A", "Fable 5", "iTerm", "1Password", "Sonnet", "Opus", "Gemma",
        "Tailscale", "Dicticus", "SwiftBar"
    ]

    private func makeMatcher() -> BrandMatcher {
        BrandMatcher.bundledLexiconMatcher(canonicals: BrandDigitParityTests.canonicals)
    }

    // MARK: - Digit-invention negatives

    func testFibalNotRewrittenToFable5English() {
        XCTAssertEqual(
            makeMatcher().apply(to: "The diagram is not the actual model according to FIBAL.", language: "en"),
            "The diagram is not the actual model according to FIBAL.")
    }

    func testFibalNotRewrittenToFable5German() {
        XCTAssertEqual(
            makeMatcher().apply(to: "The diagram is not the actual model according to FIBAL.", language: "de"),
            "The diagram is not the actual model according to FIBAL.")
    }

    func testBareFableStemDoesNotAcquireVersionNumber() {
        XCTAssertEqual(makeMatcher().apply(to: "I asked Fable about it.", language: "en"),
                       "I asked Fable about it.")
    }

    // MARK: - Digit-drop negatives

    func testUsb5AndSonnet5BothSurviveBothGuards() {
        XCTAssertEqual(
            makeMatcher().apply(to: "So if you have a USB-5 or reversely a Sonnet 5 a task, it would delegate.",
                                 language: "en"),
            "So if you have a USB-5 or reversely a Sonnet 5 a task, it would delegate.")
    }

    func testITerm2NotCollapsedToITerm() {
        XCTAssertEqual(makeMatcher().apply(to: "iTerm2. That is my terminal.", language: "en"),
                       "iTerm2. That is my terminal.")
    }

    // MARK: - Digit-bearing positives that must still fire

    func testFable5ToFable5() {
        XCTAssertEqual(makeMatcher().apply(to: "Fable5", language: "en"), "Fable 5")
    }

    func test1PasswordIdentityFires() {
        XCTAssertEqual(makeMatcher().apply(to: "1Password", language: "en"), "1Password")
    }

    func testSonatToSonnetUnaffectedByDigitGuard() {
        XCTAssertEqual(makeMatcher().apply(to: "Sonat", language: "en"), "Sonnet")
    }

    func testDicticosToDicticusUnaffectedByDigitGuard() {
        XCTAssertEqual(makeMatcher().apply(to: "Dicticos", language: "en"), "Dicticus")
    }

    func testSwiftBarCompoundUnaffectedByDigitGuard() {
        XCTAssertEqual(makeMatcher().apply(to: "Swift bar", language: "en"), "SwiftBar")
    }

    // MARK: - Pre-existing digit fixtures that must remain green

    func testPreExistingSonnet5Unchanged() {
        XCTAssertEqual(makeMatcher().apply(to: "Sonnet 5", language: "en"), "Sonnet 5")
        XCTAssertEqual(makeMatcher().apply(to: "Sonnet 5", language: "de"), "Sonnet 5")
    }

    func testPreExistingOpus5Unchanged() {
        XCTAssertEqual(makeMatcher().apply(to: "opus 5", language: "en"), "opus 5")
    }

    func testPreExistingGemma4Unchanged() {
        XCTAssertEqual(makeMatcher().apply(to: "Gemma 4", language: "en"), "Gemma 4")
    }
}
