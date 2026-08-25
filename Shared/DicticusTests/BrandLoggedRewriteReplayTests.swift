import XCTest
@testable import Dicticus

/// Quick task 260825-pt5, Task 3 — production replay net: every brand
/// rewrite (or correctly-inert non-rewrite) observed in the 2026-08-20
/// through 2026-08-25 debug logs, run through the real guard stack (guards
/// A+B from Tasks 1-2, plus every pre-existing `BrandMatcher` guard) so the
/// fix is proven against real production behaviour, not just the four cases
/// that motivated it.
///
/// Surfaces only — no surrounding dictation. Bare brand tokens carry no
/// personal content, which keeps this net publishable under the repo's
/// public-history rule while the sentence-level fixtures in Tasks 1-2 stay
/// neutralized with neutral carrier sentences.
///
/// Every assertion is an EXACT output string — `contains` cannot see the
/// deleted/invented content this defect class produces.
@MainActor
final class BrandLoggedRewriteReplayTests: XCTestCase {

    /// Union of every canonical the logged rewrites in this table targeted.
    /// "Dicticus" is not enumerated in the plan's stated union list but is
    /// required for the "Dicticus." identity-fire row the plan's own
    /// identity-fire list demands — added here as the minor, self-evident
    /// completion of that list (documented as a deviation in the SUMMARY).
    static let canonicals: [String] = [
        "iPad", "USB-A", "Fable 5", "Tailscale", "TrueNAS", "Dockge",
        "Claude Code", "Claude Desktop", "Antigravity CLI", "1Password",
        "GitHub", "Jellyfin", "Kagi", "Vercel", "iTerm", "localhost",
        "Threema", "Nimbalyst", "CCMetrics", "deep dive", "Dicticus"
    ]

    private func makeMatcher() -> BrandMatcher {
        BrandMatcher.bundledLexiconMatcher(canonicals: BrandLoggedRewriteReplayTests.canonicals)
    }

    /// (id, surface, expected output, language). The 4 INERT rows are the
    /// traced false fires closed by guards A+B; every other row is a real
    /// logged rewrite or an identity fire proving the guards do not
    /// over-block.
    static let table: [(id: String, surface: String, expected: String, lang: String)] = [
        // MARK: INERT — guard A (function-word window boundary)
        ("inert-ip-and", "IP and", "IP and", "en"),

        // MARK: INERT — guard B (digit-sequence parity)
        ("inert-usb5", "a USB-5", "a USB-5", "en"),
        ("inert-fibal", "FIBAL.", "FIBAL.", "en"),
        ("inert-iterm2", "iTerm2.", "iTerm2.", "en"),

        // MARK: Recovered mishearings (real logged rewrites)
        ("live-kagee", "Kagee", "Kagi", "en"),
        ("live-talescal", "TALESCAL", "Tailscale", "en"),
        ("live-versil", "Versil", "Vercel", "en"),
        ("live-fable5", "Fable5", "Fable 5", "en"),
        ("live-claudecode-glued", "ClaudeCode", "Claude Code", "en"),

        // MARK: Identity fires (already-canonical surfaces that must survive)
        ("live-claude-code-comma", "Claude Code,", "Claude Code,", "en"),
        ("live-antigravity-cli", "Antigravity CLI.", "Antigravity CLI.", "en"),
        ("live-claude-desktop", "Claude Desktop.", "Claude Desktop.", "en"),
        ("live-dicticus", "Dicticus.", "Dicticus.", "en"),
        ("live-claude-code-lowercase", "Claude code.", "Claude Code.", "en"),
        ("live-claude-code-question", "Claude Code?", "Claude Code?", "en"),
        ("live-github-lowercase", "github", "GitHub", "en"),
        ("live-jellyfin-lowercase", "jellyfin", "Jellyfin", "en"),
        ("live-1password", "1Password", "1Password", "en"),
        ("live-threema", "Threema", "Threema", "en"),
        ("live-deep-dive", "deep dive", "deep dive", "en"),
        ("live-nimbalyst", "Nimbalyst", "Nimbalyst", "en"),
        ("live-ccmetrics", "CCMetrics", "CCMetrics", "en"),
        ("live-localhost", "localhost", "localhost", "en"),
        ("live-dockge", "Dockge", "Dockge", "en"),
        ("live-github", "GitHub", "GitHub", "en")
    ]

    func testProductionReplayNet() {
        let bm = makeMatcher()
        var mismatches: [String] = []
        for row in BrandLoggedRewriteReplayTests.table {
            let got = bm.apply(to: row.surface, language: row.lang)
            if got != row.expected {
                mismatches.append("\(row.id): '\(row.surface)' -> got '\(got)', expected '\(row.expected)'")
            }
        }
        XCTAssertTrue(mismatches.isEmpty, "Replay net mismatches: \(mismatches.joined(separator: "; "))")
    }
}
