import XCTest
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
@testable import Dicticus

/// Quick task 261003-aua: the macOS German spell checker accepts some
/// misheard compounds by splitting them into two real words, so step 6.5
/// (non-word repair) never sees them as unknown. Step 8.5 accepts such a
/// substitute as `compoundRepair` when the string guards and the three
/// checker signals hold. Koma -> Komma stays rejected (SEED-001): a swap
/// between two real words never gets a phonetic path. Live evidence is cited
/// by timestamp only (`2026-10-03T05:13:29`); every sentence below is invented.

/// Stub lexicon: `known` answers `isKnownWord`; `repairable` holds pairs as
/// lowercased `"source>candidate"` and answers `isCompoundAcceptedRepair`
/// regardless of language, so EditGuard's own language gate is what N2 tests.
private struct CompoundSignalLexicon: SpellLexicon {
    let known: Set<String>
    let repairable: Set<String>

    init(source: String, candidate: String, repairable: Bool = true) {
        self.known = [source.lowercased(), candidate.lowercased()]
        self.repairable = repairable ? ["\(source.lowercased())>\(candidate.lowercased())"] : []
    }

    func isKnownWord(_ text: String, language: String) -> Bool {
        known.contains(text.lowercased())
    }

    func isCompoundAcceptedRepair(source: String, candidate: String, language: String) -> Bool {
        repairable.contains("\(source.lowercased())>\(candidate.lowercased())")
    }
}

@MainActor
final class EditGuardCompoundRepairTests: XCTestCase {

    private func run(
        _ baseline: String, _ llm: String, source: String, language: String = "de",
        lexicon: any SpellLexicon, dictProtected: Set<String> = []
    ) -> (result: EditGuard.GuardResult, edit: EditGuard.ClassifiedEdit?) {
        let result = EditGuard.apply(
            rulesCleaned: baseline, llmOutput: llm, language: language,
            dictProtected: dictProtected, lexicon: lexicon
        )
        return (result, result.edits.first { $0.from == source })
    }

    private func assertAccepted(
        _ baseline: String, _ llm: String, source: String,
        lexicon: any SpellLexicon, file: StaticString = #filePath, line: UInt = #line
    ) {
        let (result, edit) = run(baseline, llm, source: source, lexicon: lexicon)
        guard let edit else { return XCTFail("expected a substitute edit from '\(source)'", file: file, line: line) }
        XCTAssertNil(edit.rejectClass, file: file, line: line)
        XCTAssertTrue(edit.accepted, file: file, line: line)
        XCTAssertEqual(edit.acceptClass, "compoundRepair", file: file, line: line)
        XCTAssertEqual(result.text, llm, file: file, line: line)
    }

    private func assertRejected(
        _ baseline: String, _ llm: String, source: String, language: String = "de",
        lexicon: any SpellLexicon, dictProtected: Set<String> = [],
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let (result, edit) = run(
            baseline, llm, source: source, language: language,
            lexicon: lexicon, dictProtected: dictProtected
        )
        guard let edit else { return XCTFail("expected a substitute edit from '\(source)'", file: file, line: line) }
        XCTAssertFalse(edit.accepted, file: file, line: line)
        XCTAssertEqual(edit.rejectClass, "contentWordIdentityChange", file: file, line: line)
        XCTAssertEqual(result.text, baseline, file: file, line: line)
    }

    // MARK: - Positives (stub lexicon)

    private let p1Baseline = "Bitte prüf noch einmal die Schreiweise im Anhang."
    private let p1Llm = "Bitte prüf noch einmal die Schreibweise im Anhang."

    func testP1_insertion_schreiweiseToSchreibweise() {
        assertAccepted(p1Baseline, p1Llm, source: "Schreiweise",
                       lexicon: CompoundSignalLexicon(source: "Schreiweise", candidate: "Schreibweise"))
    }

    func testP2_substitution_reisekastenToReisekosten() {
        assertAccepted(
            "Morgen klären wir die Reisekasten mit der Buchhaltung.",
            "Morgen klären wir die Reisekosten mit der Buchhaltung.",
            source: "Reisekasten",
            lexicon: CompoundSignalLexicon(source: "Reisekasten", candidate: "Reisekosten"))
    }

    func testP3_deletion_gebuehhrenstelleToGebuehrenstelle() {
        assertAccepted(
            "Die Gebühhrenstelle öffnet ab Januar.",
            "Die Gebührenstelle öffnet ab Januar.",
            source: "Gebühhrenstelle",
            lexicon: CompoundSignalLexicon(source: "Gebühhrenstelle", candidate: "Gebührenstelle"))
    }

    func testP4_boundary_sourceExactlyTenLetters() {
        assertAccepted(
            "Wir besprechen die Reiskosten am Freitag.",
            "Wir besprechen die Reisekosten am Freitag.",
            source: "Reiskosten",
            lexicon: CompoundSignalLexicon(source: "Reiskosten", candidate: "Reisekosten"))
    }

    // MARK: - Negatives (stub lexicon claims the pair repairable unless noted)

    /// SEED-001: a swap between two real words stays rejected. The length gate
    /// blocks it; the stub claims the pair repairable to prove that.
    func testN1_kommaRealWordSwapStaysRejected() {
        assertRejected(
            "Am Briefanfang steht nach dem Gruss kein Koma.",
            "Am Briefanfang steht nach dem Gruss kein Komma.",
            source: "Koma",
            lexicon: CompoundSignalLexicon(source: "Koma", candidate: "Komma"))
    }

    func testN2_nonGermanLanguage() {
        assertRejected(
            "Morgen klären wir die Reisekasten mit der Buchhaltung.",
            "Morgen klären wir die Reisekosten mit der Buchhaltung.",
            source: "Reisekasten", language: "en",
            lexicon: CompoundSignalLexicon(source: "Reisekasten", candidate: "Reisekosten"))
    }

    func testN3_firstLetterEdit() {
        assertRejected(
            "Du kannst den letzten Absatz rauslassen.",
            "Du kannst den letzten Absatz auslassen.",
            source: "rauslassen",
            lexicon: CompoundSignalLexicon(source: "rauslassen", candidate: "auslassen"))
    }

    func testN4_lastLetterEdit() {
        assertRejected(
            "Wir treffen uns am Bahnhofsvorplatz um acht.",
            "Wir treffen uns am Bahnhofsvorplatt um acht.",
            source: "Bahnhofsvorplatz",
            lexicon: CompoundSignalLexicon(source: "Bahnhofsvorplatz", candidate: "Bahnhofsvorplatt"))
    }

    func testN5_sourceOfNineLetters() {
        assertRejected(
            "Wir besprechen die Miekosten am Freitag.",
            "Wir besprechen die Mietkosten am Freitag.",
            source: "Miekosten",
            lexicon: CompoundSignalLexicon(source: "Miekosten", candidate: "Mietkosten"))
    }

    func testN6_affixPairTheInteriorGuardCannotSee() {
        assertRejected(
            "Im Comic steht nur Schnarchtonzzz als Text.",
            "Im Comic steht nur Schnarchtonzzzz als Text.",
            source: "Schnarchtonzzz",
            lexicon: CompoundSignalLexicon(source: "Schnarchtonzzz", candidate: "Schnarchtonzzzz"))
    }

    func testN7_dictProtectedCandidate() {
        assertRejected(p1Baseline, p1Llm, source: "Schreiweise",
                       lexicon: CompoundSignalLexicon(source: "Schreiweise", candidate: "Schreibweise"),
                       dictProtected: ["Schreibweise"])
    }

    /// `TestSpellLexicon` has no override, so it takes the protocol default
    /// (false): every existing conformer keeps failing closed.
    func testN8_conformerWithoutOverrideNeverFires() {
        assertRejected(p1Baseline, p1Llm, source: "Schreiweise",
                       lexicon: TestSpellLexicon(known: ["schreiweise", "schreibweise"]))
    }

    func testN9_distanceTwo() {
        assertRejected(
            "Morgen klären wir die Reisekastten mit der Buchhaltung.",
            "Morgen klären wir die Reisekosten mit der Buchhaltung.",
            source: "Reisekastten",
            lexicon: CompoundSignalLexicon(source: "Reisekastten", candidate: "Reisekosten"))
    }

    func testN10_hyphenatedToken() {
        assertRejected(
            "Das ist eine Schrei-weise ohne Sinn.",
            "Das ist eine Schreib-weise ohne Sinn.",
            source: "Schrei-weise",
            lexicon: CompoundSignalLexicon(source: "Schrei-weise", candidate: "Schreib-weise"))
    }

    // MARK: - Real platform checker

    #if canImport(AppKit)
    /// OS pin: the compound-split signal is undocumented `NSSpellChecker`
    /// behaviour. This test exists to fail loudly after an OS update; the
    /// user's learned words can change it too.
    func testR0_checkerSignalsOnThisMac() {
        let checker = NSSpellChecker.shared
        func known(_ w: String) -> Bool {
            checker.checkSpelling(of: w, startingAt: 0, language: "de", wrap: false, inSpellDocumentWithTag: 0, wordCount: nil).length == 0
        }
        func completions(_ w: String) -> [String] {
            checker.completions(forPartialWordRange: NSRange(location: 0, length: (w as NSString).length), in: w, language: "de", inSpellDocumentWithTag: 0) ?? []
        }
        func guesses(_ w: String) -> [String] {
            checker.guesses(forWordRange: NSRange(location: 0, length: (w as NSString).length), in: w, language: "de", inSpellDocumentWithTag: 0) ?? []
        }
        func selfListed(_ w: String) -> Bool { completions(w).contains { $0.lowercased() == w.lowercased() } }

        XCTAssertTrue(known("Schreiweise"))
        XCTAssertFalse(selfListed("Schreiweise"))
        XCTAssertTrue(guesses("Schreiweise").contains { $0.lowercased() == "schreibweise" })
        XCTAssertTrue(known("Schreibweise"))
        XCTAssertTrue(selfListed("Schreibweise"))
        XCTAssertTrue(known("Koma"))
        XCTAssertTrue(selfListed("Koma"))
        XCTAssertTrue(known("Komma"))
        XCTAssertTrue(selfListed("Komma"))
    }

    /// Real checker end to end. Residual, measured and not asserted: obscure
    /// real words the checker knows only unlisted would pass if the LLM
    /// proposed exactly their neighbour (an aufzuzäumen -> aufzuräumen class,
    /// about 1% of long checker-known words).
    func testR1_realChecker_schreiweiseRepaired() {
        assertAccepted(p1Baseline, p1Llm, source: "Schreiweise", lexicon: PlatformSpellLexicon())
    }

    func testR2_realChecker_kommaStaysRejected() {
        assertRejected(
            "Am Briefanfang steht nach dem Gruss kein Koma.",
            "Am Briefanfang steht nach dem Gruss kein Komma.",
            source: "Koma", lexicon: PlatformSpellLexicon())
    }

    func testR3_realChecker_reverseDirectionRejected() {
        assertRejected(p1Llm, p1Baseline, source: "Schreibweise", lexicon: PlatformSpellLexicon())
    }

    func testR4_platformLexiconMethod() {
        let lexicon = PlatformSpellLexicon()
        XCTAssertTrue(lexicon.isCompoundAcceptedRepair(source: "Schreiweise", candidate: "Schreibweise", language: "de"))
        XCTAssertTrue(lexicon.isCompoundAcceptedRepair(source: "Reisekasten", candidate: "Reisekosten", language: "de"))
        XCTAssertFalse(lexicon.isCompoundAcceptedRepair(source: "Koma", candidate: "Komma", language: "de"))
        XCTAssertFalse(lexicon.isCompoundAcceptedRepair(source: "Schreibweise", candidate: "Schreiweise", language: "de"))
        XCTAssertFalse(lexicon.isCompoundAcceptedRepair(source: "Schreiweise", candidate: "Schreibweise", language: "en"))
    }
    #endif

    #if canImport(UIKit) && !canImport(AppKit)
    /// iOS contract: where `UITextChecker` lists no completions for the
    /// candidate (the measured simulator state) the branch never fires; where
    /// it does (a device may), the parity path is active and unpinned.
    func testI1_iosWithoutCompletionsNeverFires() throws {
        let word = "Schreibweise"
        let completions = UITextChecker().completions(
            forPartialWordRange: NSRange(location: 0, length: (word as NSString).length),
            in: word, language: "de") ?? []
        try XCTSkipUnless(completions.isEmpty, "this runtime lists completions, so the parity path is active and unpinned")
        let lexicon = PlatformSpellLexicon()
        XCTAssertFalse(lexicon.isCompoundAcceptedRepair(source: "Schreiweise", candidate: "Schreibweise", language: "de"))
        let result = EditGuard.apply(
            rulesCleaned: p1Baseline, llmOutput: p1Llm, language: "de", lexicon: lexicon)
        XCTAssertEqual(result.text, p1Baseline)
    }
    #endif
}
