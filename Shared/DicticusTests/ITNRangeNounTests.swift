import XCTest
@testable import Dicticus

/// Phase 49.7 ITN-01 / D-13, D-14, D-15.
///
/// D-13: `applyRangeHomophoneFix`'s noun-head list gains a member (`clusters`) for
/// each live audited record of the `<noun> N0M <number>` shape — a list-member
/// addition, never a new rule or a composition change. The only member sized by
/// the Wave-0 §C ITN replay (audited record `08-25:32`, cited by timestamp only —
/// never quoted verbatim) is `clusters`; no further English member and no German
/// member has a live record, so none are added (`49.7-WAVE0.md` §C
/// `decision: clusters`).
///
/// D-14: `applyEnglishITNCore` and the magnitude-guard wrapper are untouched —
/// bare `one two` → `102` composition is unchanged, and a noun outside the list
/// (e.g. `servers`) is a documented known miss, not a target of this fix.
///
/// D-15: range output keeps the connector word (`1 to 5` / `1 bis 4`) — no hyphen,
/// no en dash. The existing `phases 102, four` fixture stays byte-identical.
///
/// Every sentence in this file is invented for this phase.
final class ITNRangeNounTests: XCTestCase {

    // MARK: - D-13: clusters (RED on pre-fix code, GREEN after the noun-list change)

    func testD13_clustersRange_oneTwoFive() {
        let out = ITNUtility.applyITN(to: "address the clusters one two five", language: "en")
        XCTAssertEqual(out, "address the clusters 1 to 5")
        XCTAssertFalse(out.contains("102"))
    }

    // MARK: - D-15: existing noun-head fixtures stay byte-identical

    func testD15_existingPhasesShapeByteIdentical() {
        XCTAssertEqual(
            ITNUtility.applyITN(to: "the phases 102, four", language: "en"),
            "the phases 1 to 4"
        )
        XCTAssertEqual(
            ITNUtility.applyITN(to: "phases 102 four", language: "en"),
            "phases 1 to 4"
        )
    }

    func testD15_germanPhasenKeepsBis() {
        XCTAssertEqual(
            ITNUtility.applyITN(to: "die Phasen 102 vier", language: "de"),
            "die Phasen 1 bis 4"
        )
    }

    // MARK: - D-14: composition unchanged; a noun outside the list is a known miss

    func testD14_nounOutsideListIsKnownMiss() {
        // "servers" is not a range noun head — the composed form passes through
        // untouched. This is the documented residue, not a target of this fix.
        XCTAssertEqual(
            ITNUtility.applyITN(to: "the servers one two five", language: "en"),
            "the servers 102 five"
        )
    }

    func testD14_bareRunWithoutTrailingNumberUnchanged() {
        // Pattern 2 needs a trailing number/word after the N0M token; without one,
        // "clusters" being in the noun list changes nothing — composition unchanged.
        XCTAssertEqual(
            ITNUtility.applyITN(to: "clusters one two", language: "en"),
            "clusters 102"
        )
    }

    func testD13_fourDigitTokenDoesNotMatchPattern2() {
        // A four-digit token is not the N0M (3-digit) shape pattern 2 requires.
        XCTAssertEqual(
            ITNUtility.applyITN(to: "the clusters 1024 five", language: "en"),
            "the clusters 1024 five"
        )
    }
}
