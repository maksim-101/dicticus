import XCTest
@testable import Dicticus

final class SwissHelvetismsTests: XCTestCase {

    func testWordsCountInRange() {
        // D-D2 — target ~30, allow 25..35.
        XCTAssertGreaterThanOrEqual(SwissHelvetisms.words.count, 25)
        XCTAssertLessThanOrEqual(SwissHelvetisms.words.count, 35)
    }

    func testWordsAreUnique() {
        let unique = Set(SwissHelvetisms.words)
        XCTAssertEqual(unique.count, SwissHelvetisms.words.count,
                       "SwissHelvetisms.words contains duplicates")
    }

    func testCanonicalEntriesPresent() {
        // Spot-check that the curated list contains daily-use entries.
        let canonical = ["Velo", "Trottoir", "parkieren", "Billett", "Spital"]
        for word in canonical {
            XCTAssertTrue(SwissHelvetisms.words.contains(word),
                          "Expected canonical Helvetism '\(word)' to be in the list")
        }
    }

    // W9 LOCK — runtime constant assertion (no source-file-path walking).
    func testLicenseAttributionContainsRequiredStrings() {
        // The CC BY-SA 3.0 license requires source attribution. Assert on
        // the public `licenseAttribution` constant exposed by Plan 03,
        // NOT on the .swift file contents — the file-walk approach was brittle
        // (depends on test bundle layout, fails on CI / .ipa shipped builds).
        XCTAssertTrue(SwissHelvetisms.licenseAttribution.contains("CC BY-SA 3.0"),
                      "licenseAttribution must contain 'CC BY-SA 3.0' per W9 lock")
        XCTAssertTrue(SwissHelvetisms.licenseAttribution.contains("Liste von Helvetismen"),
                      "licenseAttribution must contain 'Liste von Helvetismen' per W9 lock")
    }
}
