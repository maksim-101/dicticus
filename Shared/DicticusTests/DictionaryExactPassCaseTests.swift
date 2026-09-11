import XCTest
@testable import Dicticus

/// Phase 49.7 BRAND-02 / D-07: a single-token, all-uppercase dictionary key
/// (e.g. `HEY`, `HEI` — Whisper's all-caps rendering of a spoken tool name)
/// matches case-sensitively so the capitalised greeting form (`Hey,`) and the
/// lowercase form (`hey`) are left alone. Multi-word all-caps keys (`USB C`,
/// `A I`) and every other key keep the global `isCaseSensitive` toggle's
/// behaviour unchanged.
///
/// D-19: exercises `DictionaryService.applyExactPass` directly — a nonisolated
/// static — never the `.shared` singleton, so this file needs no test
/// isolation of its own.
///
/// Every sentence here is invented; no live dictation or dictionary entry
/// appears in this file.
final class DictionaryExactPassCaseTests: XCTestCase {

    private func entry(_ replacement: String) -> DictionaryMetadata {
        DictionaryMetadata(replacement: replacement, createdAt: Date(), source: .user)
    }

    /// A single-token all-uppercase key already fires on its own all-caps form
    /// under case-insensitive matching — this stays true both before and
    /// after the D-07 predicate lands.
    func testAllCapsSingleTokenKey_firesOnAllCapsForm() {
        let result = DictionaryService.applyExactPass(
            to: "before starting HEY.",
            entries: ["HEY": entry("agy")],
            caseSensitive: false
        )

        XCTAssertEqual(result.text, "before starting agy.")
        XCTAssertEqual(result.replacements.count, 1)
        XCTAssertEqual(result.replacements.first?.key, "HEY")
        XCTAssertEqual(result.replacements.first?.from, "HEY")
        XCTAssertEqual(result.replacements.first?.to, "agy")
    }

    /// RED pre-rule: today the case-insensitive match rewrites the capitalised
    /// greeting into the tool name. The D-07 predicate must leave it alone.
    func testAllCapsSingleTokenKey_leavesCapitalisedGreetingUntouched() {
        let input = "Hey so previously we looked at the totals."
        let result = DictionaryService.applyExactPass(
            to: input,
            entries: ["HEY": entry("agy")],
            caseSensitive: false
        )

        XCTAssertEqual(result.text, input)
    }

    /// RED pre-rule: the lowercase spoken form of the greeting must also be
    /// left alone once the key is single-token all-uppercase.
    func testAllCapsSingleTokenKey_leavesLowercaseFormUntouched() {
        let input = "and then hey presto it worked"
        let result = DictionaryService.applyExactPass(
            to: input,
            entries: ["HEY": entry("agy")],
            caseSensitive: false
        )

        XCTAssertEqual(result.text, input)
    }

    /// D-07 amendment: a multi-word all-caps key (the shipped starter-pack
    /// shape, e.g. `USB C`) stays case-insensitive — the single-token
    /// restriction never touches it.
    func testMultiWordAllCapsKey_staysCaseInsensitive_usbC() {
        let result = DictionaryService.applyExactPass(
            to: "plug in the usb c cable",
            entries: ["USB C": entry("USB-C")],
            caseSensitive: false
        )

        XCTAssertEqual(result.text, "plug in the USB-C cable")
    }

    /// Pins the D-05 two-word exact-key entry pattern (invented shape, no
    /// personal name) — fires only on the full two-word heard form, never on
    /// a bare single-token substring of it.
    func testTwoWordExactKey_firesOnTwoWordHeardForm_onlyAsAWhole() {
        let entries = ["Halden Werk": entry("Haldenwerk")]

        let fired = DictionaryService.applyExactPass(
            to: "the Halden Werk report",
            entries: entries,
            caseSensitive: false
        )
        XCTAssertEqual(fired.text, "the Haldenwerk report")

        let untouched = DictionaryService.applyExactPass(
            to: "the Halden report",
            entries: entries,
            caseSensitive: false
        )
        XCTAssertEqual(untouched.text, "the Halden report")
    }

    /// The global `caseSensitive` toggle still forces every key — including a
    /// multi-word all-caps key — to case-sensitive matching. D-07's predicate
    /// only ever ADDS case-sensitivity, never removes it.
    func testGlobalCaseSensitiveToggle_stillForcesEveryKey() {
        let input = "plug in the usb c cable"
        let result = DictionaryService.applyExactPass(
            to: input,
            entries: ["USB C": entry("USB-C")],
            caseSensitive: true
        )

        XCTAssertEqual(result.text, input)
    }
}
