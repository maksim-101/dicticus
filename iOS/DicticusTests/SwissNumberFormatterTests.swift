import XCTest
@testable import Dicticus

final class SwissNumberFormatterTests: XCTestCase {

    // Phase 20.08 apostrophe-strike: thousands grouping is dropped
    // entirely. Years like 2026 stay 2026, big numbers stay digit-only.
    func testThousandsNoGrouping() {
        let result = SwissNumberFormatter.format("1250")
        XCTAssertEqual(result, "1250")
        // Apostrophe-strike: NO thousands separator of any kind.
        XCTAssertFalse(result.contains("'"),
                       "Apostrophe-strike: no ASCII apostrophe expected. Got: \(result)")
        XCTAssertFalse(result.contains("\u{2019}"),
                       "Apostrophe-strike: no U+2019 expected. Got: \(result)")
    }

    // B3 LOCK (Phase 20.08 update) — German-thousands input still parses
    // correctly, but emits without grouping.
    func testGermanThousandsParsesAsInteger() {
        // 1.250 (German thousands) → 1250 (no grouping).
        let result = SwissNumberFormatter.format("1.250")
        XCTAssertEqual(result, "1250",
                       "B3: German-thousands input must reformat to ungrouped integer")
    }

    // B3 LOCK (Phase 20.08 update) — Swiss-apostrophe input still parses
    // correctly; emits without grouping.
    func testSwissApostropheNormalisesToUngrouped() {
        let result = SwissNumberFormatter.format("1'250")
        XCTAssertEqual(result, "1250",
                       "Apostrophe-strike: legacy Swiss-apostrophe input flattens to digits")
    }

    // Year preservation — 4-digit years must NOT acquire any thousands separator.
    func testYearPreservation() {
        XCTAssertEqual(SwissNumberFormatter.format("2026"), "2026",
                       "Year-bug fix: 2026 must stay 2026, not 2'026")
        XCTAssertEqual(SwissNumberFormatter.format("im Jahr 2026"), "im Jahr 2026")
        XCTAssertEqual(SwissNumberFormatter.format("von 1999 bis 2024"),
                       "von 1999 bis 2024")
    }

    func testGermanCommaDecimalToSwissPeriod() {
        // 5,70 → 5.70.
        let result = SwissNumberFormatter.format("5,70")
        XCTAssertEqual(result, "5.70")
    }

    func testSwissPeriodDecimalRoundtrip() {
        // 5.70 stays 5.70 (already correct).
        let result = SwissNumberFormatter.format("5.70")
        XCTAssertEqual(result, "5.70")
    }

    func testNonNumericTokensUnchanged() {
        let result = SwissNumberFormatter.format("Hello world")
        XCTAssertEqual(result, "Hello world")
    }

    func testMixedTokensFormat() {
        // Each token reformatted independently; non-numeric tokens preserved.
        // Apostrophe-strike: 1250 stays 1250.
        let result = SwissNumberFormatter.format("CHF 1250")
        XCTAssertEqual(result, "CHF 1250")
    }

    func testEmptyStringReturnsEmpty() {
        XCTAssertEqual(SwissNumberFormatter.format(""), "")
    }

    // W7 LOCK — currency-glyph-prefixed tokens are reformatted with the glyph preserved.
    func testCurrencyGlyphPrefixedEuroComma() {
        // "€6,70" → "€6.70" (W7 preferred behavior: strip+reattach glyph).
        let result = SwissNumberFormatter.format("€6,70")
        XCTAssertEqual(result, "€6.70",
                       "W7: leading currency glyph must be preserved while numeric core is reformatted")
    }

    func testCurrencyGlyphPrefixedDollar() {
        // "$1250" → "$1250" (W7 glyph preservation; apostrophe-strike → no grouping).
        let result = SwissNumberFormatter.format("$1250")
        XCTAssertEqual(result, "$1250")
    }

    // MARK: - B3 split-cents-with-currency-between (Phase 19.5 UAT followup)

    /// Original B3 ("15 Franken 50" → "15.50 Franken") relies on the post-LLM
    /// bridge to merge the cents back into the price when ASR splits them
    /// across the currency word. macOS LLM keeps them literal; iOS LLM
    /// occasionally concatenates them. The bridge handles the literal path.
    func testSplitCentsFrankenBridge() {
        XCTAssertEqual(SwissNumberFormatter.format("15 Franken 50"), "15.50 Franken")
    }

    func testSplitCentsEuroBridge() {
        XCTAssertEqual(SwissNumberFormatter.format("15 Euro 50"), "15.50 Euro")
    }

    func testSplitCentsCHFBridge() {
        XCTAssertEqual(SwissNumberFormatter.format("15 CHF 50"), "15.50 CHF")
    }

    func testSplitCentsEURBridge() {
        XCTAssertEqual(SwissNumberFormatter.format("15 EUR 50"), "15.50 EUR")
    }

    func testSplitCentsEuroGlyphBridge() {
        XCTAssertEqual(SwissNumberFormatter.format("15 € 50"), "15.50 €")
    }

    func testSplitCentsBoundedBySentenceEnd() {
        XCTAssertEqual(
            SwissNumberFormatter.format("Es kostet 15 Franken 50."),
            "Es kostet 15.50 Franken."
        )
    }

    func testSplitCentsRejectsSingleDigitRightSide() {
        // "5 Stück" should not be eaten as cents — single-digit right side
        // is ambiguous and far more likely a separate quantity word.
        XCTAssertEqual(
            SwissNumberFormatter.format("15 Franken 5 Stück"),
            "15 Franken 5 Stück"
        )
    }

    func testSplitCentsRejectsThreeDigitRightSide() {
        // "100" is a clean amount, not cents — leave the literal alone.
        XCTAssertEqual(
            SwissNumberFormatter.format("15 Franken 100"),
            "15 Franken 100"
        )
    }

    func testSplitCentsDoesNotEatThousandsPattern() {
        // "1.250 Franken 50" must NOT match "250 Franken 50" inside the
        // thousand pattern. The `(?<![.,'\u{2019}])` lookbehind prevents this.
        // Apostrophe-strike (Phase 20.08): German-thousands "1.250" flattens
        // to "1250" with no grouping; Bridge-2 still doesn't fire because the
        // pre-format lookbehind sees the period in front of "250".
        XCTAssertEqual(
            SwissNumberFormatter.format("1.250 Franken 50"),
            "1250 Franken 50"
        )
    }

    // Phase 20.08 — Bridge 2 ceiling fix: 4-digit (and longer) integers
    // followed by a currency word and 2-digit cents must collapse properly.
    // Pre-fix: pattern was \d{1,3}, which left "1250 Franken 20" untouched.
    func testSplitCentsBridgeFourDigit() {
        XCTAssertEqual(
            SwissNumberFormatter.format("1250 Franken 20"),
            "1250.20 Franken"
        )
    }

    func testSplitCentsBridgeFiveDigit() {
        XCTAssertEqual(
            SwissNumberFormatter.format("12500 Franken 75"),
            "12500.75 Franken"
        )
    }

    // MARK: - Fixture corpus

    func testFixturesCorpus() throws {
        let url = Bundle(for: Self.self).url(forResource: "SwissNumberFormatter.fixtures", withExtension: "json")
        let data = try Data(contentsOf: try XCTUnwrap(url, "fixture must ship"))
        struct Pair: Decodable { let input: String; let expected: String }
        let pairs = try JSONDecoder().decode([Pair].self, from: data)
        XCTAssertGreaterThanOrEqual(pairs.count, 4)
        for p in pairs {
            XCTAssertEqual(SwissNumberFormatter.format(p.input), p.expected,
                           "Fixture failed: input='\(p.input)'")
        }
    }

    // MARK: - Phase 20.06 F-20-UAT-02 — fold idempotency + no-Euro-Euro

    func testFoldCurrencyUnitsIsIdempotent() {
        let inputs = [
            "15 Franken 50 Rappen",
            "10 Euro 25 Cent",
            "CHF 15.50",
            "€10.25",
            "110.57 €",
            "4.50 Franken",
            "Hello world",
            "1250 Franken",
            "ich habe 5 Franken bezahlt"
        ]
        for input in inputs {
            let once = SwissNumberFormatter.foldCurrencyUnits(input)
            let twice = SwissNumberFormatter.foldCurrencyUnits(once)
            XCTAssertEqual(once, twice,
                "foldCurrencyUnits must be idempotent — failed for input: '\(input)' once='\(once)' twice='\(twice)'")
        }
    }

    func testFoldDoesNotProduceEuroEuroOnGlyphPrefixed() {
        let result = SwissNumberFormatter.format("110.57 €")
        XCTAssertFalse(result.contains("Euro Euro"),
            "F-20-UAT-02: must not duplicate Euro token. Got: '\(result)'")
        XCTAssertFalse(result.contains("€ Euro"),
            "F-20-UAT-02: must not emit '€ Euro'. Got: '\(result)'")
        XCTAssertFalse(result.contains("Euro €"),
            "F-20-UAT-02: must not emit 'Euro €'. Got: '\(result)'")
    }

    func testFoldDoesNotAppendWordWhenGlyphAdjacent() {
        let result = SwissNumberFormatter.format("ich habe 110.57 € ausgegeben")
        XCTAssertFalse(result.contains("Euro Euro"), "Got: '\(result)'")
        XCTAssertFalse(result.contains("€ Euro"), "Got: '\(result)'")
        XCTAssertFalse(result.contains("Euro €"), "Got: '\(result)'")
    }

    func testFoldStillCollapsesSpokenOutCHF() {
        // Existing Phase 20.03 contract — must not regress.
        XCTAssertEqual(SwissNumberFormatter.foldCurrencyUnits("15 Franken 50 Rappen"), "CHF 15.50")
    }

    func testFoldStillCollapsesSpokenOutEUR() {
        // Existing Phase 20.03 contract — must not regress.
        XCTAssertEqual(SwissNumberFormatter.foldCurrencyUnits("10 Euro 25 Cent"), "€10.25")
    }
}
