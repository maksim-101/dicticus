import XCTest
@testable import Dicticus

final class SwissDialectFormsTests: XCTestCase {

    // MARK: - R4: Token list shape contract

    func testTokensCountInRange() {
        // Phase 20.08 D-09 / RESEARCH.md §3 — target band 30..50
        XCTAssertGreaterThanOrEqual(SwissDialectForms.tokens.count, 30,
            "SwissDialectForms.tokens must contain at least 30 entries")
        XCTAssertLessThanOrEqual(SwissDialectForms.tokens.count, 50,
            "SwissDialectForms.tokens must contain at most 50 entries")
    }

    func testTokensAreAllLowercase() {
        for tok in SwissDialectForms.tokens {
            XCTAssertEqual(tok, tok.lowercased(),
                "Token '\(tok)' must be lowercase (gate uses lowercased compare)")
        }
    }

    func testTokensAreUnique() {
        let unique = Set(SwissDialectForms.tokens)
        XCTAssertEqual(unique.count, SwissDialectForms.tokens.count,
            "SwissDialectForms.tokens contains duplicates")
    }

    func testTokensDoNotOverlapSwissHelvetisms() {
        let dialect = Set(SwissDialectForms.tokens.map { $0.lowercased() })
        let helvetisms = Set(SwissHelvetisms.words.map { $0.lowercased() })
        let overlap = dialect.intersection(helvetisms)
        XCTAssertTrue(overlap.isEmpty,
            "SwissDialectForms.tokens and SwissHelvetisms.words must be disjoint (D-06 separation). Overlap: \(overlap)")
    }

    func testCanonicalUATAnchorTokensPresent() {
        // Phase 20.08 D-11 — anchor on the 2026-04-27 UAT failure transcript
        let anchors = ["uf", "siite", "wahrschiinli", "het", "hie", "alli", "mini", "wuer", "usfiltere"]
        for tok in anchors {
            XCTAssertTrue(SwissDialectForms.tokens.contains(tok),
                "UAT-anchor token '\(tok)' must be in SwissDialectForms.tokens")
        }
    }

    // MARK: - R5: License attribution contract (W9-LOCK pattern)

    func testLicenseAttributionContainsRequiredStrings() {
        XCTAssertTrue(SwissDialectForms.licenseAttribution.contains("CC BY-SA 4.0"),
            "licenseAttribution must contain 'CC BY-SA 4.0' per W9 lock")
        XCTAssertTrue(SwissDialectForms.licenseAttribution.contains("Schweizerdeutsch"),
            "licenseAttribution must contain 'Schweizerdeutsch' per W9 lock")
    }
}
