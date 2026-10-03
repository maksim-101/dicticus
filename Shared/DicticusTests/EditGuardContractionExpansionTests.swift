import XCTest
@testable import Dicticus

/// Quick task 261003-fiu: English contraction expansions that `EditGuard`
/// used to reject.
///
/// The defect: when the AI cleanup wrote the full form of a contraction
/// ("that's" -> "that is", "don't" -> "do not", "we're" -> "we are"), the guard
/// read the host substitute as a changed word (`contentWordIdentityChange` or
/// `pronounPersonChange`) and the inserted expansion word as an invented
/// content word (`contentWordInsertion`). `sentenceCoupledRevert` then threw
/// away every comma, capital, sentence break and merge in the same sentence.
///
/// `AcceptClass.contractionExpansion` accepts the pair only when the candidate
/// holds the FULL expansion in order at the contraction's place, six conditions
/// together: (1) a rejected substitute whose prior class is one of the two
/// above; (2) the contraction is in a closed table (the `n't` rows with `not`,
/// `'re`/`'ve`/`'ll`/`'m`, and `'s` only on it/that/what/where/there/here/who/
/// how/he/she, plus `can't` -> `cannot`); (3) the substitute's target is the
/// host and the next candidate token is an inserted expansion word; (4) the
/// host's case equals the contraction's, or is a capital directly after a
/// candidate `.`/`?`/`!` or at the start of the text; (5) the word before and
/// the word after the span are equal in baseline and candidate; (6) for `'s`,
/// neither of the next two baseline words is a has-participle (`been`, `gone`,
/// a word of four or more letters ending `ed`, ...). Both halves flip together
/// and are context-dependent: an independent content rejection in the same
/// baseline sentence returns the pair to the baseline with the sentence.
/// `verbKeptBaselineOrder` matches a baseline negative contraction to its host,
/// so a sentence-initial "Don't" -> "Do not" does not trip the mood lock.
///
/// Decision 2: `let's` is not accepted ("let us" is the "allow us" reading).
/// Decision 3: German is deferred; the predicate is English-only. Decision 4:
/// a dropped pronoun (`it's` -> `is`), a dropped verb (`there's` -> `there`) or
/// a dropped negation (`don't` -> `do`) stays rejected. Decision 5: a capital
/// mid-sentence stays rejected. Decision 6: membership in the
/// context-dependent set. `'d` has no row (would or had).
///
/// Every fixture is an invented sentence about a pottery studio; records are
/// cited only as `10-03:#N` from `.planning/debug/audit-2026-10-03/SYNTHESIS.md`
/// section 2. `_RED` in a name means the test fails at the start commit; every
/// other test is a pin that must hold before and after the fix. Guard pins and
/// their mutations: M1 full expansion (`testVerbDropped...`,
/// `testNegationDropped...`), M2 host identity (`testPronounDropped...`), M3
/// span (`testCommaBeforeHost...`, `testCommaAfterVerb...`), M4 case
/// (`testMidSentenceCapital...`), M5 has-guard (`testBeen...`, `testEdParticiple...`),
/// M6 window size (`testParticipleAfterAdverb...`), M7 `'s` word (`testThereAre...`,
/// `testWhatDoes...`), M8 `'d` (`testHad...`), M9 host set (`testNounHost...`),
/// M10 membership (`testExpansionCoupledWithRejectionInSameSentence_RED`), M11 mood
/// lock (`testSentenceInitialDoNotShips_RED`).
@MainActor
final class EditGuardContractionExpansionTests: XCTestCase {

    private struct Pair {
        let lang: String
        let baseline: String
        let llm: String
        init(_ lang: String, _ baseline: String, _ llm: String) {
            self.lang = lang
            self.baseline = baseline
            self.llm = llm
        }
    }

    private enum Fx {
        // Positives
        static let itIs = Pair("en", "The glaze is thin and it's ready for the second coat.", "The glaze is thin and it is ready for the second coat.")
        static let thatIs = Pair("en", "This slip leaves a finish that's smooth after the bisque firing.", "This slip leaves a finish that is smooth after the bisque firing.")
        static let whatIs = Pair("en", "Before we load the kiln, what's the cone number for this clay?", "Before we load the kiln, what is the cone number for this clay?")
        static let whereIsRunOn = Pair("en", "I weighed the clay again this morning, where's the extra weight getting in isn't that down to the water we add and the studio seems a bit damp.", "I weighed the clay again this morning, where is the extra weight getting in? Isn't that down to the water we add? And the studio seems a bit damp.")
        static let weAre = Pair("en", "The students say we're out of kiln wash again.", "The students say we are out of kiln wash again.")
        static let iHave = Pair("en", "Honestly I've never fired this clay body before.", "Honestly I have never fired this clay body before.")
        static let theyWill = Pair("en", "The glaze crew said they'll unload the kiln tomorrow.", "The glaze crew said they will unload the kiln tomorrow.")
        static let iAm = Pair("en", "Today I'm trimming the foot rings on these cups.", "Today I am trimming the foot rings on these cups.")
        static let doNot = Pair("en", "Please don't stack the bowls near the kiln door.", "Please do not stack the bowls near the kiln door.")
        static let willNot = Pair("en", "The lid won't fit on the jar after firing.", "The lid will not fit on the jar after firing.")
        static let canNot = Pair("en", "The wheel can't spin with that much clay on it.", "The wheel can not spin with that much clay on it.")
        static let cannot = Pair("en", "The wheel can't spin with that much clay on it.", "The wheel cannot spin with that much clay on it.")
        static let sentenceInitialDoNot = Pair("en", "First rinse the sponge. Don't leave the bowls near the damp wall they crack.", "First rinse the sponge. Do not leave the bowls near the damp wall, they crack.")
        static let lowercaseStart = Pair("en", "The glaze is dry. it's ready for the kiln now.", "The glaze is dry. It is ready for the kiln now.")
        static let nextSentenceRejection = Pair("en", "The wheel is slow today and that's fine for trimming. We really need more slip for the handles.", "The wheel is slow today and that is fine for trimming. We need more slip for the handles.")
        static let coupledSameSentence = Pair("en", "The bowl cracked because it's too thick near the rim.", "The bowl cracked because it is too wide near the rim.")
        static let sentenceReleased = Pair("en", "The glaze is mixed in a manner that's easily washable. off the tile with water, while the kiln warms up.", "The glaze is mixed in a manner that is easily washable off the tile with water, while the kiln warms up.")

        // Negatives
        static let pronounDropped = Pair("en", "The glaze is thin and it's ready for the second coat.", "The glaze is thin and is ready for the second coat.")
        static let verbDropped = Pair("en", "The shelf holds two jars and there's a third jar on the floor.", "The shelf holds two jars and there a third jar on the floor.")
        static let verbDroppedRecased = Pair("en", "The wheel stopped. there's a crack in the bat.", "The wheel stopped. There a crack in the bat.")
        static let negationDropped = Pair("en", "Please don't stack the bowls near the kiln door.", "Please do stack the bowls near the kiln door.")
        static let been = Pair("en", "Looks like it's been fired twice already.", "Looks like it is been fired twice already.")
        static let participleAfterAdverb = Pair("en", "The sample says it's already gone from the shelf.", "The sample says it is already gone from the shelf.")
        static let edParticiple = Pair("en", "The potter says she's finished the bowl for the show.", "The potter says she is finished the bowl for the show.")
        static let thereAre = Pair("en", "I counted again and there's two kilns in the back room.", "I counted again and there are two kilns in the back room.")
        static let whatDoes = Pair("en", "Nobody knows what's this mark mean on the old jar.", "Nobody knows what does this mark mean on the old jar.")
        static let had = Pair("en", "Luckily I'd fired the kiln before the power cut.", "Luckily I had fired the kiln before the power cut.")
        static let would = Pair("en", "Honestly I'd rather fire the kiln tomorrow.", "Honestly I would rather fire the kiln tomorrow.")
        static let nounHost = Pair("en", "I think the kiln's hot enough to fire.", "I think the kiln is hot enough to fire.")
        static let letUs = Pair("en", "Okay let's load the kiln now.", "Okay let us load the kiln now.")
        static let midSentenceCapital = Pair("en", "Maybe it's ready for the glaze.", "Maybe It is ready for the glaze.")
        static let commaBeforeHost = Pair("en", "Maybe it's ready for the glaze.", "Maybe, it is ready for the glaze.")
        static let commaAfterVerb = Pair("en", "Maybe it's ready for the glaze.", "Maybe it is, ready for the glaze.")
        static let german = Pair("de", "Sag mal wie geht's dem Ton heute Morgen.", "Sag mal wie geht es dem Ton heute Morgen.")
        static let capitalizedExpansionWord = Pair("en", "The studio says we don't need the kiln today.", "The studio says we do Not need the kiln today.")
    }

    // MARK: - Helpers

    private func run(_ p: Pair) -> EditGuard.GuardResult {
        let r = EditGuard.apply(rulesCleaned: p.baseline, llmOutput: p.llm, language: p.lang, lexicon: TestSpellLexicon.allKnown)
        let v = EditGuardMergeAtomicityTests.neitherSourceViolations(output: r.text, sourceA: p.baseline, sourceB: p.llm)
        XCTAssertTrue(v.tier1.isEmpty, "tier-1 neither-source violation(s) \(v.tier1) in: \(r.text)")
        return r
    }

    private func edit(_ r: EditGuard.GuardResult, from: String?, to: String? = nil, kind: String? = nil) -> EditGuard.ClassifiedEdit? {
        r.edits.first { $0.from == from && (to == nil || $0.to == to) && (kind == nil || $0.kind == kind) }
    }

    private func expansionLines(_ r: EditGuard.GuardResult) -> [EditGuard.ClassifiedEdit] {
        r.edits.filter { $0.accepted && $0.acceptClass == "contractionExpansion" }
    }

    /// Output equals the candidate; the contraction's substitute (and, unless `single`, the inserted expansion word) are
    /// accepted `contractionExpansion` and nothing else carries that class.
    private func assertShipped(_ p: Pair, contraction: String, host: String, word: String? = nil, single: Bool = false,
                               file: StaticString = #filePath, line: UInt = #line) {
        let r = run(p)
        XCTAssertEqual(r.text, p.llm, file: file, line: line)
        let lines = expansionLines(r)
        XCTAssertEqual(lines.count, single ? 1 : 2, "\(r.edits)", file: file, line: line)
        XCTAssertTrue(lines.contains { $0.kind == "substitute" && $0.from == contraction && $0.to == host }, "\(lines)", file: file, line: line)
        if let word {
            XCTAssertTrue(lines.contains { $0.kind == "insert" && $0.to == word }, "\(lines)", file: file, line: line)
        }
    }

    /// Output equals the baseline, no edit carries `contractionExpansion`, and the named substitute carries `cls`.
    private func assertRejected(_ p: Pair, from: String, to: String, _ cls: EditGuard.RejectionClass,
                                file: StaticString = #filePath, line: UInt = #line) {
        let r = run(p)
        XCTAssertEqual(r.text, p.baseline, file: file, line: line)
        XCTAssertTrue(expansionLines(r).isEmpty, "\(r.edits)", file: file, line: line)
        guard let e = edit(r, from: from, to: to, kind: "substitute") else {
            return XCTFail("no substitute \(from) -> \(to) in \(r.edits)", file: file, line: line)
        }
        XCTAssertFalse(e.accepted, "expected rejected: \(e)", file: file, line: line)
        XCTAssertEqual(e.rejectClass, cls.rawValue, file: file, line: line)
    }

    // MARK: - Positives

    func testItIsShips_RED() { assertShipped(Fx.itIs, contraction: "it's", host: "it", word: "is") }
    func testThatIsShips_RED() { assertShipped(Fx.thatIs, contraction: "that's", host: "that", word: "is") }
    func testWhatIsShipsWithCommaKept_RED() {
        assertShipped(Fx.whatIs, contraction: "what's", host: "what", word: "is")
        XCTAssertTrue(run(Fx.whatIs).text.contains("kiln, what is"))
    }

    /// 10-03:#55 shape: the pair is the only trigger in one run-on sentence, so the LLM's commas, question marks and
    /// capitals ship with it.
    func testWhereIsShipsWholeRunOn_RED() {
        assertShipped(Fx.whereIsRunOn, contraction: "where's", host: "where", word: "is")
        XCTAssertTrue(run(Fx.whereIsRunOn).edits.allSatisfy { $0.accepted })
    }

    func testWeAreShips_RED() { assertShipped(Fx.weAre, contraction: "we're", host: "we", word: "are") }
    func testIHaveShips_RED() { assertShipped(Fx.iHave, contraction: "I've", host: "I", word: "have") }
    func testTheyWillShips_RED() { assertShipped(Fx.theyWill, contraction: "they'll", host: "they", word: "will") }
    func testIAmShips_RED() { assertShipped(Fx.iAm, contraction: "I'm", host: "I", word: "am") }

    func testDoNotShips_RED() { assertShipped(Fx.doNot, contraction: "don't", host: "do", word: "not") }
    /// Irregular host: `won't` -> `will not`.
    func testWillNotShips_RED() { assertShipped(Fx.willNot, contraction: "won't", host: "will", word: "not") }
    func testCanNotTwoTokensShips_RED() { assertShipped(Fx.canNot, contraction: "can't", host: "can", word: "not") }
    func testCannotSingleTokenShips_RED() { assertShipped(Fx.cannot, contraction: "can't", host: "cannot", single: true) }

    /// M11: a rebuilt sentence-first `Do` where the baseline had `Don't` is not a fronted verb.
    func testSentenceInitialDoNotShips_RED() {
        assertShipped(Fx.sentenceInitialDoNot, contraction: "Don't", host: "Do", word: "not")
        XCTAssertTrue(run(Fx.sentenceInitialDoNot).text.contains("Do not leave the bowls near the damp wall, they crack."))
    }

    /// Decision 5: a lowercase contraction after a kept period may be recased to a sentence-initial capital.
    func testLowercaseSentenceStartRecasedShips_RED() {
        assertShipped(Fx.lowercaseStart, contraction: "it's", host: "It", word: "is")
    }

    func testExpansionSurvivesRejectionInNextSentence_RED() {
        let p = Fx.nextSentenceRejection
        let r = run(p)
        XCTAssertEqual(r.text, "The wheel is slow today and that is fine for trimming. We really need more slip for the handles.")
        XCTAssertEqual(expansionLines(r).count, 2, "\(r.edits)")
        XCTAssertTrue(r.edits.contains { $0.from == "really" && $0.kind == "delete" && !$0.accepted })
    }

    // MARK: - Audit analogues

    /// 10-03:#37 shape, M10: an independent content substitution in the same baseline sentence returns the pair to the
    /// baseline with it, so the host never renders without its expansion word.
    func testExpansionCoupledWithRejectionInSameSentence_RED() {
        let p = Fx.coupledSameSentence
        let r = run(p)
        XCTAssertEqual(r.text, p.baseline)
        XCTAssertTrue(expansionLines(r).isEmpty, "\(r.edits)")
        XCTAssertTrue(r.edits.contains { $0.kind == "substitute" && $0.from == "it's" && $0.rejectClass == EditGuard.RejectionClass.sentenceCoupledRevert.rawValue }, "\(r.edits)")
        XCTAssertTrue(r.edits.contains { $0.kind == "insert" && $0.to == "is" && $0.rejectClass == EditGuard.RejectionClass.sentenceCoupledRevert.rawValue }, "\(r.edits)")
        XCTAssertTrue(r.edits.contains { $0.from == "thick" && $0.to == "wide" && $0.rejectClass == EditGuard.RejectionClass.contentWordIdentityChange.rawValue }, "\(r.edits)")
    }

    /// 10-03:#41 shape: the stray period before a lowercase continuation is released once the pair no longer fails.
    func testSentenceReleasedByExpansion_RED() {
        let p = Fx.sentenceReleased
        let r = run(p)
        XCTAssertEqual(r.text, p.llm)
        XCTAssertEqual(expansionLines(r).count, 2, "\(r.edits)")
        XCTAssertTrue(r.edits.contains { $0.kind == "delete" && $0.from == "." && $0.accepted && $0.acceptClass == EditGuard.AcceptClass.pauseSplitMerge.rawValue }, "\(r.edits)")
    }

    // MARK: - Negatives: the full expansion in order (M1, M2)

    /// Coordinator shape (M2): the pronoun is dropped, the verb remains.
    func testPronounDroppedStaysRejected() {
        assertRejected(Fx.pronounDropped, from: "it's", to: "is", .contentWordIdentityChange)
    }

    /// Coordinator shape (M1): the verb is dropped, the host remains.
    func testVerbDroppedStaysRejected() {
        assertRejected(Fx.verbDropped, from: "there's", to: "there", .contentWordIdentityChange)
    }

    /// The corpus shape: the verb is dropped and the host is recased.
    func testVerbDroppedRecasedStaysRejected() {
        assertRejected(Fx.verbDroppedRecased, from: "there's", to: "There", .contentWordIdentityChange)
    }

    /// M1: the negation must survive.
    func testNegationDroppedStaysRejected() {
        let r = run(Fx.negationDropped)
        XCTAssertEqual(r.text, Fx.negationDropped.baseline)
        XCTAssertTrue(r.text.contains("don't"))
        XCTAssertTrue(expansionLines(r).isEmpty, "\(r.edits)")
    }

    // MARK: - Negatives: the `'s` reading (M5, M6, M7, M9)

    /// M5: `it's been` is `it has been`.
    func testBeenStaysRejected() { assertRejected(Fx.been, from: "it's", to: "it", .pronounPersonChange) }
    /// M6: the participle is the second word after the contraction.
    func testParticipleAfterAdverbStaysRejected() { assertRejected(Fx.participleAfterAdverb, from: "it's", to: "it", .pronounPersonChange) }
    /// M5: a word of four or more letters ending `ed` reads as a participle.
    func testEdParticipleStaysRejected() { assertRejected(Fx.edParticiple, from: "she's", to: "she", .pronounPersonChange) }
    /// M7: `there's two kilns` -> `there are two kilns` changes the verb.
    func testThereAreStaysRejected() { assertRejected(Fx.thereAre, from: "there's", to: "there", .contentWordIdentityChange) }
    /// M7: `what's` -> `what does` changes the verb.
    func testWhatDoesStaysRejected() { assertRejected(Fx.whatDoes, from: "what's", to: "what", .contentWordIdentityChange) }
    /// M9: a noun host is a possessive or a `has`.
    func testNounHostStaysRejected() { assertRejected(Fx.nounHost, from: "kiln's", to: "kiln", .contentWordIdentityChange) }

    // MARK: - Negatives: contractions outside the tables (M8)

    /// M8: `'d` is `would` or `had`.
    func testHadStaysRejected() { assertRejected(Fx.had, from: "I'd", to: "I", .pronounPersonChange) }
    /// Pin: `would` is an insertable function word, so the insert is already `functionWordInsertion`.
    func testWouldStaysRejected() { assertRejected(Fx.would, from: "I'd", to: "I", .pronounPersonChange) }
    /// Pin: decision 2, excluded twice (host set and the `is`-only word).
    func testLetUsStaysRejected() { assertRejected(Fx.letUs, from: "let's", to: "let", .contentWordIdentityChange) }

    // MARK: - Negatives: case and span (M3, M4)

    /// M4: a capital mid-sentence is rendered verbatim and nothing would undo it.
    func testMidSentenceCapitalStaysRejected() {
        let r = run(Fx.midSentenceCapital)
        XCTAssertEqual(r.text, Fx.midSentenceCapital.baseline)
        XCTAssertFalse(r.text.contains("It is"))
        XCTAssertTrue(expansionLines(r).isEmpty, "\(r.edits)")
    }

    /// M3: a comma inserted before the host is a changed left neighbour.
    func testCommaBeforeHostStaysRejected() {
        let r = run(Fx.commaBeforeHost)
        XCTAssertEqual(r.text, Fx.commaBeforeHost.baseline)
        XCTAssertTrue(expansionLines(r).isEmpty, "\(r.edits)")
    }

    /// M3: a comma inserted after the expansion word is a changed right neighbour.
    func testCommaAfterVerbStaysRejected() {
        let r = run(Fx.commaAfterVerb)
        XCTAssertEqual(r.text, Fx.commaAfterVerb.baseline)
        XCTAssertTrue(expansionLines(r).isEmpty, "\(r.edits)")
    }

    /// Pin, no mutation: the predicate is English-only.
    func testGermanStaysRejected() {
        let r = run(Fx.german)
        XCTAssertEqual(r.text, Fx.german.baseline)
        XCTAssertTrue(expansionLines(r).isEmpty, "\(r.edits)")
    }

    /// Quick task 261003-gp8 (M7): the inserted expansion word must be lowercase. "do Not" mid-sentence was accepted and
    /// shipped a stray capital.
    func testCapitalizedExpansionWordStaysRejected_RED() {
        let r = run(Fx.capitalizedExpansionWord)
        XCTAssertEqual(r.text, Fx.capitalizedExpansionWord.baseline)
        XCTAssertFalse(r.text.contains("do Not"))
        XCTAssertTrue(expansionLines(r).isEmpty, "\(r.edits)")
    }
}
