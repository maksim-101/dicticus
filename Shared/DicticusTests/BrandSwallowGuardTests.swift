import XCTest
@testable import Dicticus

/// Quick task 260809-g7h — Defect B: the 2-token fuzzy window in
/// `BrandMatcher.applyReportingRewrites` swallowed the neighbouring word,
/// its punctuation, or a sentence boundary whenever the brand token ALONE
/// already scored near-exact against the matched canonical (e.g. "TrueNAS,
/// I" -> "TrueNAS", eating "I"; "1Password is" -> "1Password", eating "is").
///
/// Uses the REAL bundled lexicon via `BrandMatcher.bundledLexiconMatcher` so
/// the guard is proven against production data, not a hand-supplied lexicon
/// that would let it pass vacuously. Every assertion is an EXACT string —
/// `contains` cannot see deleted content.
@MainActor
final class BrandSwallowGuardTests: XCTestCase {

    static let canonicals: [String] = [
        "TrueNAS", "Cloudflare", "ChatGPT", "GitHub", "1Password", "iTerm",
        "Tailscale", "Jellyfin", "Cellguard", "SwiftBar", "AdGuard"
    ]

    private func makeMatcher() -> BrandMatcher {
        BrandMatcher.bundledLexiconMatcher(canonicals: BrandSwallowGuardTests.canonicals)
    }

    // MARK: - Corruption sweep (must be byte-identical — the brand is already canonical)

    func testSwallowGuardTrueNASCommaI() {
        XCTAssertEqual(makeMatcher().apply(to: "I set up TrueNAS, I think it works.", language: "en"),
                       "I set up TrueNAS, I think it works.")
    }

    func testSwallowGuardCloudflareOrTailscale() {
        XCTAssertEqual(makeMatcher().apply(to: "Use Cloudflare or Tailscale for that.", language: "en"),
                       "Use Cloudflare or Tailscale for that.")
    }

    func testSwallowGuardChatGPTSentenceBoundary() {
        XCTAssertEqual(makeMatcher().apply(to: "I asked ChatGPT. So then I tried again.", language: "en"),
                       "I asked ChatGPT. So then I tried again.")
    }

    func testSwallowGuard1PasswordIsWhereIKeepIt() {
        XCTAssertEqual(makeMatcher().apply(to: "1Password is where I keep it.", language: "en"),
                       "1Password is where I keep it.")
    }

    func testSwallowGuardWholePointOf1Password() {
        XCTAssertEqual(makeMatcher().apply(to: "the whole point of 1Password.", language: "en"),
                       "the whole point of 1Password.")
    }

    func testSwallowGuard1PasswordIUseEveryDay() {
        XCTAssertEqual(makeMatcher().apply(to: "1Password I use every day.", language: "en"),
                       "1Password I use every day.")
    }

    func testSwallowGuardJellyfinThenLeft() {
        XCTAssertEqual(makeMatcher().apply(to: "I switched to Jellyfin, then left.", language: "en"),
                       "I switched to Jellyfin, then left.")
    }

    func testSwallowGuardITermToRunIt() {
        XCTAssertEqual(makeMatcher().apply(to: "I opened iTerm to run it.", language: "en"),
                       "I opened iTerm to run it.")
    }

    func testSwallowGuardTrueNASOrTheOtherOne() {
        XCTAssertEqual(makeMatcher().apply(to: "TrueNAS or the other one.", language: "en"),
                       "TrueNAS or the other one.")
    }

    /// Article case: the brand IS corrected (mishearing "a github" -> "a GitHub"),
    /// and the neighbouring article survives.
    func testSwallowGuardArticleGithubStillCorrects() {
        XCTAssertEqual(makeMatcher().apply(to: "I pushed it to a github repo.", language: "en"),
                       "I pushed it to a GitHub repo.")
    }

    // MARK: - Preservation sweep (the 2-token window must STILL win here)

    func testPreservationCellGuardCompound() {
        XCTAssertEqual(makeMatcher().apply(to: "I use cell guard daily.", language: "en"),
                       "I use Cellguard daily.")
    }

    func testPreservationSwiftBarCompound() {
        XCTAssertEqual(makeMatcher().apply(to: "Open Swift bar now.", language: "en"),
                       "Open SwiftBar now.")
    }

    func testPreservationAdGuardCompound() {
        XCTAssertEqual(makeMatcher().apply(to: "I run ad guard at home.", language: "en"),
                       "I run AdGuard at home.")
    }
}
