import XCTest
@testable import Dicticus

/// Phase 49.7 NUMFMT-01 — invented, RED-first fixtures for D-09 / D-10 / D-11.
///
/// D-09: an EXISTING single thousands group (comma, period, or apostrophe) is
/// re-rendered with the Swiss straight apostrophe `'`. The group is never
/// invented — bare integers (years, IDs) never reach this rule, so the Phase
/// 20.08 year fix stays intact.
///
/// D-10: `d,ddd` is a thousands group in both languages; a comma followed by
/// one or two digits is a decimal (`1,80`→`1.80`, `2,5`→`2.5`); a zero integer
/// part is always a decimal (`0,125`→`0.125`) even when three digits follow
/// the comma. A three-place German decimal with a non-zero integer part
/// (`3,141`) is a known, documented residue — it renders as a thousands group.
///
/// D-11: when the same digit string occurs twice in one utterance with
/// different separators, the user is naming the punctuation contrast — every
/// numeric token of that utterance is left untouched. No keyword trigger. A
/// lone comma-decimal utterance still normalizes (accepted known miss).
///
/// Every sentence in this file is invented for this plan. The two
/// corpus-derived tokens (`2,273`, `10,011`) are plain numbers, never
/// embedded in a sentence copied from a live record.
///
/// Deferred finding (no fixture, out of scope for D-09): `12,500,000` renders
/// `12.000` today — CONTEXT's premise that multi-group tokens are "emitted
/// verbatim" is false. Multi-comma / multi-period tokens stay out of scope
/// for this plan; the defect is carried to the phase summary's deferred list.
final class SwissNumberGroupingTests: XCTestCase {

    // MARK: - D-09: existing group re-rendered with the apostrophe

    func testD09_commaGroupRendersApostrophe_2273() {
        XCTAssertEqual(SwissNumberFormatter.format("2,273"), "2'273")
    }

    func testD09_commaGroupRendersApostrophe_10011() {
        XCTAssertEqual(SwissNumberFormatter.format("10,011"), "10'011")
    }

    func testD09_periodGroupRendersApostrophe_1250() {
        XCTAssertEqual(SwissNumberFormatter.format("1.250"), "1'250")
    }

    func testD09_apostropheGroupIsIdempotent() {
        XCTAssertEqual(SwissNumberFormatter.format("1'250"), "1'250")
        XCTAssertEqual(SwissNumberFormatter.format("2'273"), "2'273")
    }

    func testD09_groupWithDecimalTail() {
        XCTAssertEqual(SwissNumberFormatter.format("2,273.50"), "2'273.50")
        XCTAssertEqual(SwissNumberFormatter.format("1.250,70"), "1'250.70")
    }

    func testD09_glyphAndTailPreserved() {
        XCTAssertEqual(SwissNumberFormatter.format("€2,273"), "€2'273")
        XCTAssertEqual(SwissNumberFormatter.format("2,273."), "2'273.")
    }

    func testD09_bareIntegersNeverGrouped() {
        XCTAssertEqual(SwissNumberFormatter.format("2026"), "2026")
        XCTAssertEqual(SwissNumberFormatter.format("im Jahr 2026"), "im Jahr 2026")
        XCTAssertEqual(SwissNumberFormatter.format("10000"), "10000")
        XCTAssertEqual(SwissNumberFormatter.format("65535"), "65535")
    }

    // MARK: - D-10: d,ddd thousands in both languages, zero-integer clause

    func testD10_shortCommaDecimalsStayDecimals() {
        XCTAssertEqual(SwissNumberFormatter.format("1,80"), "1.80")
        XCTAssertEqual(SwissNumberFormatter.format("2,5"), "2.5")
    }

    func testD10_zeroIntegerPartIsDecimal() {
        XCTAssertEqual(SwissNumberFormatter.format("0,125"), "0.125")
    }

    func testKnownResidue_threePlaceGermanDecimalRendersAsThousands() {
        XCTAssertEqual(SwissNumberFormatter.format("3,141"), "3'141")
    }

    // MARK: - D-11: contrast-pair guard

    func testD11_contrastPairLeavesUtteranceUntouched() {
        XCTAssertEqual(
            SwissNumberFormatter.format("It should never be 1,80 but actually 1.80 meters"),
            "It should never be 1,80 but actually 1.80 meters"
        )
    }

    func testD11_loneCommaDecimalStillNormalizes_knownMiss() {
        XCTAssertEqual(SwissNumberFormatter.format("write 1,80 with a comma"), "write 1.80 with a comma")
    }

    // MARK: - Idempotency across every fixture in this file

    func testFormatIsIdempotentOnEveryFixture() {
        let inputs = [
            "2,273", "10,011", "1.250", "1'250", "2'273",
            "2,273.50", "1.250,70", "€2,273", "2,273.", "3,141",
            "It should never be 1,80 but actually 1.80 meters",
            "2026", "im Jahr 2026", "10000", "65535",
            "1,80", "2,5", "0,125",
            "write 1,80 with a comma",
        ]
        for s in inputs {
            let once = SwissNumberFormatter.format(s)
            XCTAssertEqual(SwissNumberFormatter.format(once), once, "Idempotency failed for input: \(s)")
        }
    }
}
