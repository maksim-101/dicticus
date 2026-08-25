import XCTest
@testable import Dicticus

/// Quick task 260825-pt5 — guard A: a 2-token fuzzy window in
/// `BrandMatcher.applyReportingRewrites` fires across a word boundary onto a
/// closed-class function word / pronoun that is NOT part of the matched
/// canonical, deleting a word the speaker actually said (the traced
/// `cleanup-2026-08-21.jsonl` line 8 record: "IP and" -> "iPad").
///
/// Uses the REAL bundled lexicon via `BrandMatcher.bundledLexiconMatcher` so
/// the guard is proven against production data, not a hand-supplied lexicon
/// that would let it pass vacuously. Every assertion is an EXACT string —
/// `contains` cannot see deleted content. The negative corpus is
/// adversarially broadened beyond the three traced records per this
/// project's own prior incident (a 7-case corpus produced a false
/// zero-corruption pass that shipped corrupting code).
@MainActor
final class BrandFunctionWordWindowTests: XCTestCase {

    static let canonicals: [String] = [
        "iPad", "Tailscale", "TrueNAS", "Cellguard", "SwiftBar", "AdGuard",
        "Sonnet", "Tauri", "Vercel", "Dicticus", "Kagi", "Jellyfin", "GitHub"
    ]

    private func makeMatcher() -> BrandMatcher {
        BrandMatcher.bundledLexiconMatcher(canonicals: BrandFunctionWordWindowTests.canonicals)
    }

    // MARK: - Headline case (record 2): one sentence, one correct fire, one false fire

    func testTalescalRepairedIPAndSurvives() {
        XCTAssertEqual(
            makeMatcher().apply(
                to: "I would point the CNAME record at my TALESCAL IP and not at the TrueNAS IP directly.",
                language: "en"),
            "I would point the CNAME record at my Tailscale IP and not at the TrueNAS IP directly.")
    }

    // MARK: - Adversarially broadened function-word-span negatives (EN)

    func testNegativeUpAndRunning() {
        XCTAssertEqual(makeMatcher().apply(to: "the deploy was up and running again", language: "en"),
                       "the deploy was up and running again")
    }

    func testNegativeLookedAtItAndMovedOn() {
        XCTAssertEqual(makeMatcher().apply(to: "I looked at it and moved on", language: "en"),
                       "I looked at it and moved on")
    }

    func testNegativeSoIOpenedTheTerminal() {
        XCTAssertEqual(makeMatcher().apply(to: "so I opened the terminal instead", language: "en"),
                       "so I opened the terminal instead")
    }

    func testNegativeStillAtMyDeskCopy() {
        XCTAssertEqual(makeMatcher().apply(to: "the file was still at my desk copy", language: "en"),
                       "the file was still at my desk copy")
    }

    func testNegativeInAndOutOfSync() {
        XCTAssertEqual(makeMatcher().apply(to: "the service is in and out of sync", language: "en"),
                       "the service is in and out of sync")
    }

    func testNegativeShippedItAndHonestlySpanEndsInPunctuation() {
        XCTAssertEqual(makeMatcher().apply(to: "we shipped it and, honestly, it holds up", language: "en"),
                       "we shipped it and, honestly, it holds up")
    }

    func testNegativeCheckedTheIPAndSentenceBoundary() {
        XCTAssertEqual(makeMatcher().apply(to: "I checked the IP and. Then I stopped.", language: "en"),
                       "I checked the IP and. Then I stopped.")
    }

    // MARK: - Adversarially broadened function-word-span negatives (DE)

    func testNegativeGermanAnUndFuerSich() {
        XCTAssertEqual(makeMatcher().apply(to: "ich habe das an und für sich verstanden", language: "de"),
                       "ich habe das an und für sich verstanden")
    }

    func testNegativeGermanUndDannIstDasBackupAnDerReihe() {
        XCTAssertEqual(makeMatcher().apply(to: "und dann ist das Backup an der Reihe", language: "de"),
                       "und dann ist das Backup an der Reihe")
    }

    // MARK: - Compound-preservation counterpart (NOT a blanket multi-token ban)

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

    // MARK: - Single-token recall counterpart (untouched by a window-boundary guard)

    func testRecallKageeToKagi() {
        XCTAssertEqual(makeMatcher().apply(to: "Kagee", language: "en"), "Kagi")
    }

    func testRecallVersilToVercel() {
        XCTAssertEqual(makeMatcher().apply(to: "Versil", language: "en"), "Vercel")
    }

    func testRecallSonatToSonnet() {
        XCTAssertEqual(makeMatcher().apply(to: "Sonat", language: "en"), "Sonnet")
    }

    func testRecallTowryToTauri() {
        XCTAssertEqual(makeMatcher().apply(to: "Towry", language: "en"), "Tauri")
    }

    func testRecallDicticosToDicticus() {
        XCTAssertEqual(makeMatcher().apply(to: "Dicticos", language: "en"), "Dicticus")
    }
}
