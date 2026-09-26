import XCTest
@testable import Dicticus

/// Quick task 260926-bcc — Guard A's allowlist misses correctly-spelled words
/// outside its 1,930-word top-1000-lemma corpus. Live corruption: raw "this
/// safeguard" became "this Cellguard" via the user entry SalGuard -> Cellguard
/// (ratio 2/9 = 0.222, under the 0.25 cap), record cleanup-2026-09-21.jsonl ts
/// 2026-09-21T18:55:02Z.
///
/// Same fixture idiom as `DictionaryCanonicalCollisionTests`: `removeAll()`
/// then `setReplacement(for:with:)` against `DictionaryService.shared`, which
/// `DicticusTestBootstrap` redirects to an ephemeral store — never touches the
/// live user dictionary. Every assertion is an EXACT string.
@MainActor
final class DictionaryRealWordVetoTests: XCTestCase {

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

    func testSafeguardNotRewrittenViaSalGuardKey() {
        makeDict([("SalGuard", "Cellguard")])
        let input = "And how would you evaluate this safeguard in terms of what other users are doing in terms of the risk profile, probability, and actual implementation of it?"
        XCTAssertEqual(dictionaryService.apply(to: input), input)
        XCTAssertEqual(dictionaryService.applyWithTrace(to: input).replacements.count, 0)
    }

    func testGermanParkettNotRewrittenViaParakeetAnchor() {
        makeDict([("Parakeet", "Parakeet")])
        let input = "Das Parkett im Wohnzimmer ist neu."
        XCTAssertEqual(dictionaryService.apply(to: input), input)
    }

    func testGermanSignaleNotRewrittenViaSignalAnchor() {
        makeDict([("Signal", "Signal")])
        let input = "Die Signale sind heute schwach."
        XCTAssertEqual(dictionaryService.apply(to: input), input)
    }

    func testTrunasStillRepairsToTrueNAS() {
        makeDict([("Thrunas", "TrueNAS")])
        XCTAssertEqual(dictionaryService.apply(to: "the Trunas box rebooted"),
                       "the TrueNAS box rebooted")
    }
}
