import XCTest
#if canImport(AppKit)
import AppKit
#endif
@testable import Dicticus

/// Quick task 261010-8dm: step 6.5 (non-word repair) must not replace a German
/// compound of two words the spell checker knows when the model swaps a whole
/// part. A long shared prefix makes such a swap look like a small edit, so the
/// dictated compound was read as a garble. The rule: German only, the folded
/// edit distance is 3 or more, and the dictated token splits into two parts of
/// at least four letters that the checker knows (capitalised, German or
/// English). A one- or two-letter fix, or a split with an unknown part, is
/// still repaired.
///
/// `_RED` in a name means the test fails at the start commit; every other test
/// is a pin that must hold before and after the change. Mutations: M1 drop the
/// step-6.5 conjunct, M2 drop the distance condition, M3 raise the distance
/// threshold, M4 make the split check always true, M5 drop the German
/// condition, M6 make the protocol default answer true, M7 query the part as
/// given instead of capitalised, M8 query German only.
///
/// Every fixture is an invented sentence about a bicycle repair workshop.
@MainActor
final class EditGuardNonWordCompoundTests: XCTestCase {

    /// `isKnownWord` is false only for `unknown`; `isKnownCompoundPart` is true
    /// only for `parts`. `isListedWord` keeps its default.
    private struct PartLexicon: SpellLexicon {
        let unknown: Set<String>
        let parts: Set<String>

        func isKnownWord(_ text: String, language: String) -> Bool {
            !unknown.contains(text.lowercased())
        }

        func isKnownCompoundPart(_ text: String) -> Bool {
            parts.contains(text.lowercased())
        }
    }

    /// Same as `PartLexicon` without a part oracle: the protocol default answers.
    private struct NoPartOracleLexicon: SpellLexicon {
        let unknown: Set<String>

        func isKnownWord(_ text: String, language: String) -> Bool {
            !unknown.contains(text.lowercased())
        }
    }

    // MARK: - Helpers

    private func run(
        _ lang: String, _ baseline: String, _ llm: String, lexicon: any SpellLexicon
    ) -> EditGuard.GuardResult {
        let r = EditGuard.apply(rulesCleaned: baseline, llmOutput: llm, language: lang, lexicon: lexicon)
        let v = EditGuardMergeAtomicityTests.neitherSourceViolations(output: r.text, sourceA: baseline, sourceB: llm)
        XCTAssertTrue(v.tier1.isEmpty, "tier-1 neither-source violation(s) \(v.tier1) in: \(r.text)")
        return r
    }

    private func assertKept(
        _ lang: String, _ baseline: String, _ llm: String, lexicon: any SpellLexicon,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let r = run(lang, baseline, llm, lexicon: lexicon)
        XCTAssertEqual(r.text, baseline, file: file, line: line)
        XCTAssertFalse(r.edits.contains { $0.acceptClass == "nonWordRepair" }, "\(r.edits)", file: file, line: line)
        XCTAssertTrue(r.edits.contains { $0.kind == "substitute" && !$0.accepted }, "\(r.edits)", file: file, line: line)
    }

    private func assertRepaired(
        _ lang: String, _ baseline: String, _ llm: String, lexicon: any SpellLexicon,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let r = run(lang, baseline, llm, lexicon: lexicon)
        XCTAssertEqual(r.text, llm, file: file, line: line)
        XCTAssertTrue(r.edits.contains { $0.acceptClass == "nonWordRepair" }, "\(r.edits)", file: file, line: line)
    }

    private let headBaseline = "Die Werkstatt bestellt neue Ventilcaps für alle Räder."
    private let headLlm = "Die Werkstatt bestellt neue Ventilkappe für alle Räder."

    // MARK: - RED: a whole-part swap inside a compound of two known parts

    func testNWC_headPartSwapKeepsDictatedCompound_RED() {
        assertKept("de", headBaseline, headLlm,
                   lexicon: PartLexicon(unknown: ["ventilcaps"], parts: ["ventil", "caps"]))
    }

    func testNWC_modifierPartSwapKeepsDictatedCompound_RED() {
        assertKept("de", "Der Mechaniker prüft den Elektrischmotor am Lastenrad.",
                   "Der Mechaniker prüft den Elektromotor am Lastenrad.",
                   lexicon: PartLexicon(unknown: ["elektrischmotor"], parts: ["elektrisch", "motor"]))
    }

    // MARK: - Pins: repairs the rule must keep

    func testNWC_smallEditInsidePartCompoundStillRepaired() {
        assertRepaired("de", "Wir verkaufen heute zwei aufpumpenbaren Schläuche an den Kunden.",
                       "Wir verkaufen heute zwei aufpumpbaren Schläuche an den Kunden.",
                       lexicon: PartLexicon(unknown: ["aufpumpenbaren"], parts: ["aufpumpen", "baren"]))
    }

    func testNWC_unknownPartStillRepaired() {
        assertRepaired("de", "Der Lehrling soll das Teil herausbrost, bevor wir weitermachen.",
                       "Der Lehrling soll das Teil herausbringst, bevor wir weitermachen.",
                       lexicon: PartLexicon(unknown: ["herausbrost"], parts: ["heraus"]))
    }

    func testNWC_englishUtteranceStillRepaired() {
        assertRepaired("en", "The shop sells brakeslips for the old bike.",
                       "The shop sells brakeshoes for the old bike.",
                       lexicon: PartLexicon(unknown: ["brakeslips"], parts: ["brake", "slips"]))
    }

    func testNWC_lexiconWithoutPartOracleNeverBlocks() {
        assertRepaired("de", headBaseline, headLlm, lexicon: NoPartOracleLexicon(unknown: ["ventilcaps"]))
    }

    // MARK: - Real platform checker (macOS)

    #if canImport(AppKit)
    /// Oracle canary: a failure means the platform checker moved, not the code.
    func testNWC_R0_platformPartOracleOnThisMac_RED() {
        let lexicon = PlatformSpellLexicon()
        XCTAssertTrue(lexicon.isKnownCompoundPart("Elektrisch"))
        XCTAssertTrue(lexicon.isKnownCompoundPart("ventil"))
        XCTAssertTrue(lexicon.isKnownCompoundPart("Ersatz"))
        XCTAssertTrue(lexicon.isKnownCompoundPart("heads"))
        XCTAssertFalse(lexicon.isKnownCompoundPart("brost"))
        XCTAssertFalse(lexicon.isKnownWord("Elektrischventil", language: "de"))
        XCTAssertTrue(lexicon.isKnownWord("Elektroventil", language: "de"))
    }

    /// `ventil` is unknown to the German checker in lowercase, known capitalised.
    func testNWC_R1_realChecker_capitalisedGermanPart_RED() {
        assertKept("de", "Das Lager liefert morgen das Elektrischventil für die Bremse.",
                   "Das Lager liefert morgen das Elektroventil für die Bremse.",
                   lexicon: PlatformSpellLexicon())
    }

    /// `Heads` is known to the English checker only.
    func testNWC_R2_realChecker_englishOnlyPart_RED() {
        assertKept("de", "Der Chef kauft einen Ersatzheads für den Lenker.",
                   "Der Chef kauft einen Ersatzhebel für den Lenker.",
                   lexicon: PlatformSpellLexicon())
    }

    /// The only split with both sides of four letters or more has an unknown side.
    func testNWC_R3_realChecker_unknownPartStillRepaired() {
        assertRepaired("de", "Der Lehrling soll das Teil herausbrost, bevor wir weitermachen.",
                       "Der Lehrling soll das Teil herausbringst, bevor wir weitermachen.",
                       lexicon: PlatformSpellLexicon())
    }
    #endif
}
