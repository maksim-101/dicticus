import XCTest
@testable import Dicticus

/// Quick task 260809-g7h — Defects D + E in `DictionaryService`'s fuzzy pass:
///
/// D: the fuzzy pass never checks whether the CANDIDATE token is itself one
/// of the user's own dictionary canonicals — a token that IS a canonical is
/// by definition correctly heard, so any fuzzy candidate matching it is a
/// collision between two canonicals, never a repair
/// ("AdGuard" -> "Cellguard" via key "SalGuard", ratio exactly 0.250).
///
/// E: a casing-only entry (key ≡ replacement modulo case, e.g.
/// "Screenshot" -> "screenshot") acted as a fuzzy candidate and shadow-ate
/// inflections of its own key ("screenshots" -> "screenshot").
///
/// Same fixture-dictionary idiom as `BrandRewriteTraceTests`: `removeAll()`
/// then `setReplacement(for:with:)` against `DictionaryService.shared`,
/// which `DicticusTestBootstrap` redirects to an ephemeral store — never
/// touches the live user dictionary. Every assertion is an EXACT string.
@MainActor
final class DictionaryCanonicalCollisionTests: XCTestCase {

    var dictionaryService: DictionaryService!

    override func setUp() {
        super.setUp()
        dictionaryService = DictionaryService.shared
        dictionaryService.removeAll()
    }

    override func tearDown() {
        dictionaryService.removeAll()
        dictionaryService = nil
        super.tearDown()
    }

    private func makeDict(_ pairs: [(String, String)]) {
        for (key, replacement) in pairs {
            dictionaryService.setReplacement(for: key, with: replacement)
        }
    }

    // MARK: - Defect D: canonical-collision veto

    func testAdGuardNotRewrittenToCellguardViaSalGuardKey() {
        makeDict([("SalGuard", "Cellguard"), ("add guard", "adguard")])
        XCTAssertEqual(dictionaryService.apply(to: "AdGuard blocks the ads."),
                       "AdGuard blocks the ads.")
    }

    /// Adversarial variant: protection must come from a MULTI-WORD
    /// replacement being split into its constituent words, not from a
    /// coincidental single-word sibling entry.
    func testAdGuardProtectedByMultiWordReplacementSplit() {
        makeDict([("SalGuard", "Cellguard"), ("Edgardhomm", "AdGuard Home")])
        XCTAssertEqual(dictionaryService.apply(to: "AdGuard blocks the ads."),
                       "AdGuard blocks the ads.")
    }

    /// Pins verified fact 3: the 260801-m0c punctuation-bearing-key
    /// candidacy filter already excludes ".cloud" from the fuzzy pass — this
    /// filter can never be relaxed silently.
    func testICloudNotCorruptedByPunctuationBearingKey() {
        makeDict([(".cloud", ".claude")])
        XCTAssertEqual(dictionaryService.apply(to: "my iCloud backup is fine"),
                       "my iCloud backup is fine")
    }

    // MARK: - Defect D preservation: genuine fuzzy repairs must still fire

    func testTelsceleStillRepairsToTailscale() {
        makeDict([("Telscale", "Tailscale")])
        XCTAssertEqual(dictionaryService.apply(to: "Telscele is up"), "Tailscale is up")
    }

    func testChellifinStillRepairsToJellyfin() {
        makeDict([("chellyfin", "Jellyfin")])
        XCTAssertEqual(dictionaryService.apply(to: "chellifin is running"), "Jellyfin is running")
    }

    func testTavaliiStillRepairsToTavily() {
        makeDict([("Tavali", "Tavily")])
        XCTAssertEqual(dictionaryService.apply(to: "Tavalii search"), "Tavily search")
    }

    // MARK: - Defect E: casing-only shadow exclusion

    func testScreenshotsNotShadowEatenByCasingOnlyEntry() {
        makeDict([("Screenshot", "screenshot")])
        XCTAssertEqual(dictionaryService.apply(to: "I took two screenshots today"),
                       "I took two screenshots today")
    }

    /// The exact-match pass must still apply the casing entry.
    func testScreenshotExactPassStillApplies() {
        makeDict([("Screenshot", "screenshot")])
        XCTAssertEqual(dictionaryService.apply(to: "Screenshot of the log"),
                       "screenshot of the log")
    }
}
