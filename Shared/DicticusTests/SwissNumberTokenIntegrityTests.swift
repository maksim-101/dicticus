import XCTest
@testable import Dicticus

/// Quick fix swiss-number-digit-loss: SwissNumberFormatter re-renders the
/// separators `. , ' U+2019` and changes nothing else. A token whose Decimal
/// round trip would alter any other character is emitted unchanged (D-26).
///
/// Oracle: specified (the formatter's contract, not "does not crash").
///
/// Two independent rules destroyed characters before the fix:
///   Rule A: `numericCore` admits `-` / `+` inside a token, `parseGerman`
///           rejects it, and the `parseSwiss` fallback hands the whole core to
///           `Decimal(string:)`, which keeps only the numeric prefix
///           (`4-5` -> `4`).
///   Rule B: `parseGerman` accepts a zero-led integer and `Decimal` drops the
///           leading zeros (`0042` -> `42`).
///
/// Every sentence is invented for this fix. Only the bare shapes (a digit
/// range, a hyphenated digit pair, a zero-padded integer) come from the
/// corpus; the literals here are different numbers.
final class SwissNumberTokenIntegrityTests: XCTestCase {

    private func assertVerbatim(
        _ input: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        let out = SwissNumberFormatter.format(input)
        XCTAssertEqual(out, input, file: file, line: line)
        XCTAssertEqual(SwissNumberFormatter.format(out), out, "idempotency: \(input)", file: file, line: line)
    }

    // MARK: - Rule A: prefix parse after parseGerman rejects the token

    func testRuleA_digitRangeKeepsBothBounds() {
        assertVerbatim("Der Eintritt kostet 4-5 Franken pro Person.")
        assertVerbatim("4-5")
    }

    func testRuleA_hyphenatedDigitPairKeepsBothParts() {
        assertVerbatim("Please look at ticket 12-07 before lunch.")
        assertVerbatim("12-07")
    }

    func testRuleA_multiSegmentHyphenKeepsEverySegment() {
        assertVerbatim("Der Stichtag ist 31-12-2027.")
        assertVerbatim("31-12-2027")
    }

    func testRuleA_plusAndCommaJoinedDigitsKeepEveryDigit() {
        assertVerbatim("Die Hotline beginnt mit 1-800 und endet offen.")
        assertVerbatim("Rechne 2+3 im Kopf.")
        assertVerbatim("Wähle 5,6,7 aus der Liste.")
        assertVerbatim("Es sind 3-5.5 Meter.")
    }

    func testRuleA_dashAtTheEdgeIsNotDropped() {
        assertVerbatim("10-")
        assertVerbatim("2--3")
    }

    // MARK: - Rule B: leading zeros lost in the Decimal round trip

    func testRuleB_zeroPaddedIdentifierKeepsLeadingZeros() {
        assertVerbatim("Apply patch 0042 after lunch.")
        assertVerbatim("Look at build 007, then rerun.")
        assertVerbatim("Ordner 0042.")
    }

    func testRuleB_zeroPaddedBoundaries() {
        for s in ["0", "00", "000", "01", "007", "0042", "€007", "$007"] {
            assertVerbatim(s)
        }
    }

    // MARK: - Same guard, adjacent shapes (no corpus record has them)

    func testLeadingPlusSurvives() {
        assertVerbatim("+41")
        assertVerbatim("Rufe +41 an.")
    }

    // Before the fix `parseGerman` read a zero-led single group as German
    // thousands, so "0.125" rendered "125" (a 1000x value change).
    func testZeroLedThreeDigitGroupIsNotReadAsThousands() {
        assertVerbatim("0.125")
        assertVerbatim("0.250")
        assertVerbatim("Das Mass ist 0.125 Zoll.")
    }

    // MARK: - Controls: value-preserving reformats keep working

    func testControl_thousandsGroupStillRendersApostrophe() {
        XCTAssertEqual(SwissNumberFormatter.format("Der Betrag ist 1,000 Franken."), "Der Betrag ist 1'000 Franken.")
        XCTAssertEqual(SwissNumberFormatter.format("1.250"), "1'250")
        XCTAssertEqual(SwissNumberFormatter.format("2,273"), "2'273")
    }

    func testControl_commaDecimalStillRendersPeriod() {
        XCTAssertEqual(SwissNumberFormatter.format("Das Brett ist 1,80 Meter lang."), "Das Brett ist 1.80 Meter lang.")
        XCTAssertEqual(SwissNumberFormatter.format("Es kostet 1,80."), "Es kostet 1.80.")
        XCTAssertEqual(SwissNumberFormatter.format("5,70"), "5.70")
        XCTAssertEqual(SwissNumberFormatter.format("0,50"), "0.50")
        XCTAssertEqual(SwissNumberFormatter.format("0,125"), "0.125")
        XCTAssertEqual(SwissNumberFormatter.format("-5,5"), "-5.5")
    }

    func testControl_multiGroupGlyphAndCentsFoldStillNormalize() {
        XCTAssertEqual(SwissNumberFormatter.format("1.234.567"), "1234567")
        XCTAssertEqual(SwissNumberFormatter.format("12'500'000"), "12500000")
        XCTAssertEqual(SwissNumberFormatter.format("1.250,70"), "1'250.70")
        XCTAssertEqual(SwissNumberFormatter.format("€6,70"), "€6.70")
        XCTAssertEqual(SwissNumberFormatter.format("15 Franken 50"), "15.50 Franken")
    }

    // MARK: - Idempotency across every fixture in this file

    func testFormatIsIdempotentOnEveryFixture() {
        let inputs = [
            "Der Eintritt kostet 4-5 Franken pro Person.", "12-07", "31-12-2027", "1-800", "2+3", "5,6,7", "3-5.5",
            "10-", "2--3", "0042", "007", "€007", "+41", "0.125", "0.250",
            "Der Betrag ist 1,000 Franken.", "1.250", "Es kostet 1,80.", "0,50", "0,125", "-5,5",
            "1.234.567", "12'500'000", "1.250,70", "€6,70", "15 Franken 50",
        ]
        for s in inputs {
            let once = SwissNumberFormatter.format(s)
            XCTAssertEqual(SwissNumberFormatter.format(once), once, "Idempotency failed for input: \(s)")
        }
    }
}
