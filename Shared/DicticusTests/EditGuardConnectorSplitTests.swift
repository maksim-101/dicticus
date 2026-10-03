import XCTest
@testable import Dicticus

/// Quick task 261003-au9: run-on sentence splits and two narrow punctuation
/// moves that `EditGuard` used to reject.
///
/// The defect: when the AI cleanup replaced the connector "and" (or German
/// "und") between two clauses with a period, the guard counted the missing
/// word as a changed word (`contentWordIdentityChange`). `sentenceCoupledRevert`
/// then threw away every comma, capital and inflection fix in that sentence.
/// A rejected punctuation `.move` (a `?` or `.` the AI relocated, a trailing
/// comma replaced by a closing period) failed as `unclassified`.
///
/// Rule A (`AcceptClass.connectorSplit`): `and` (en) / `und` (de) replaced by
/// `.`, same kept words on both sides, continuation lowercase in the baseline
/// and capitalised by the LLM (or an English I-form). Context-dependent, so it
/// reverts with an independent content rejection in its sentence. Rule B
/// (`AcceptClass.punctuationMove`): a terminal-mark move in two shapes (the
/// utterance-final mark replaced at the end; a short jump over quiet words),
/// never after a coordinator or negator, never before a lowercase word after a
/// terminal mark. It is context-dependent too, and the boundary-coupling pass
/// reverts it when the recase of the word after it is itself reverted.
///
/// `;`, `,` and `:` as targets, `but`, `or`, `because`, `so` and their German
/// counterparts, word swaps (D-09), noun coordination, contraction expansion
/// and `which` -> `:` stay rejected; the negatives below pin each.
///
/// Every fixture is an invented sentence with the structural shape of a
/// logged case; records are cited only as `10-03:#N` from
/// `.planning/debug/audit-2026-10-03/SYNTHESIS.md` section 2. No dictated
/// text is quoted. `_RED` in a name means the test fails at the start commit
/// (after 261003-au8 and 261003-aua); every other test is a pin that must hold
/// before and after the fix. Guard pins and their mutations: MA1 neighbour
/// equality (`testNextWordChanged...`, `testPreviousWordChanged...`), MA2 the
/// recased-or-I-form guard (both noun coordination tests), MA3 the `;` mark
/// (`testAudit41...`, `testGermanSemicolon...`), MA4 `so` in the connector list
/// (`testSoToPeriod...`), MA5 context-dependent membership
/// (`testSplitRevertsWithContentRejectionInSameSentence_RED`), MB1 terminal-only
/// jump (`testCommaJump...`), MB2 coordinator destination
/// (`testMoveAfterCoordinator...`), MC1 the boundary rule for moves
/// (`testMoveRevertsWithRevertedRecase_RED`).
@MainActor
final class EditGuardConnectorSplitTests: XCTestCase {

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
        static let audit21 = Pair("en", "The garden shed is full of old tools and I will clear it out so please sort these kind of boxes because the lids are broken and then the thorough check can start.", "The garden shed is full of old tools. I will clear it out, so please sort these kinds of boxes because the lids are broken. Then the thorough check can start.")
        static let audit38 = Pair("en", "Rather we could sail on a calm morning, offering a chance to learn knots,", "Rather, we could sail on a calm morning, offering a chance to learn knots.")
        static let audit71 = Pair("en", "The sailing club meets on friday. Where are the plans? for the new dock are there enough boards to repair it or replace everything", "The sailing club meets on friday. Where are the plans for the new dock? Are there enough boards to repair it or replace everything?")
        static let audit41 = Pair("en", "The oven is hot and the dough is ready.", "The oven is hot; the dough is ready.")
        static let audit22 = Pair("en", "We sell rolls and loaves and buns etc the new shelf is empty.", "We sell rolls and loaves and buns. The new shelf is empty.")
        static let audit24 = Pair("en", "The hull needs sanding and painting and varnishing.", "The hull needs sanding, painting and varnishing.")
        static let audit40 = Pair("en", "The club has two boats which are both old.", "The club has two boats: are both old.")
        static let audit43 = Pair("en", "Please paint the hull here the sails are ready.", "Please paint the hull. The sails are ready.")
        static let audit34 = Pair("en", "The dough looks dry and we need more water because this is flour from last year.", "The dough looks dry. We need more water because it is flour from last year.")
        static let audit47 = Pair("en", "The crates are heavy and we should lift it together because the lids are loose.", "The crates are heavy. We should lift them together because the lids are loose.")
        static let audit55 = Pair("en", "The shelf is empty and we asked where's the flour because the van was late.", "The shelf is empty. We asked where is the flour because the van was late.")
        static let audit63 = Pair("en", "The loaf is cool and we can slice it so the kids get a piece.", "The loaf is cool. We can slice it. The kids get a piece.")
        static let audit73 = Pair("en", "The sails are dry and we agree you know the mast is loose.", "The sails are dry. We agree the mast is loose.")
        static let firstPerson = Pair("en", "The club was closed and I will book the hall", "The club was closed. I will book the hall.")
        static let question = Pair("en", "The oven is ready and is this loaf done", "The oven is ready. Is this loaf done?")
        static let german = Pair("de", "Wir backen das Brot und der Ofen ist schon warm weil wir früh angefangen haben.", "Wir backen das Brot. Der Ofen ist schon warm, weil wir früh angefangen haben.")
        static let negator = Pair("en", "The bakery is open and not the back door needs a new lock.", "The bakery is open. Not the back door needs a new lock.")
        static let nextSentence = Pair("en", "The oven is hot and I will start now. we have really enough rye left for today.", "The oven is hot. I will start now. We have enough rye left for today.")
        static let sameSentence = Pair("en", "The oven is hot and I will start now because the dough is ready.", "The oven is hot. I will start now because the dough is finished.")
        static let but = Pair("en", "The oven is hot but I will wait.", "The oven is hot. I will wait.")
        static let or = Pair("en", "We can bake now or I will wait.", "We can bake now. I will wait.")
        static let because = Pair("en", "We wait because I want the oven hot.", "We wait. I want the oven hot.")
        static let so = Pair("en", "The oven is cold so I will wait.", "The oven is cold. I will wait.")
        static let aber = Pair("de", "Der Ofen ist heiss aber ich möchte warten.", "Der Ofen ist heiss. Ich möchte warten.")
        static let oder = Pair("de", "Wir backen jetzt oder ich möchte warten.", "Wir backen jetzt. Ich möchte warten.")
        static let weil = Pair("de", "Wir warten weil es regnet.", "Wir warten. Es regnet.")
        static let nounEn = Pair("en", "The bakery is closed on Monday and Tuesday for repairs.", "The bakery is closed on Monday. Tuesday for repairs.")
        static let nounDe = Pair("de", "Wir kaufen Brot und Milch für das Fest.", "Wir kaufen Brot. Milch für das Fest.")
        static let semiDe = Pair("de", "Wir kaufen Brot und Milch für das Fest.", "Wir kaufen Brot; Milch für das Fest.")
        static let nextChanged = Pair("en", "The shop is open and sells bread.", "The shop is open. Sold bread.")
        static let prevChanged = Pair("en", "We need one more crate and I will order it.", "We need one more crates. I will order it.")
        static let negDropped = Pair("en", "The gate is open and not the shed is locked.", "The gate is open. The shed is locked.")
        static let commaBefore = Pair("en", "The oven is hot, and I will start.", "The oven is hot. I will start.")
        static let undOder = Pair("de", "Wir backen Brot und der Ofen ist heiss.", "Wir backen Brot oder der Ofen ist heiss.")
        static let moveAfterCoord = Pair("en", "The shop sells no cakes? nor are the buns fresh today.", "The shop sells no cakes nor? Are the buns fresh today.")
        static let moveBeforeLower = Pair("en", "Is the oven hot? enough to bake the bread.", "Is the oven hot enough? to bake the bread.")
        static let commaJump = Pair("en", "We need nets, floats or buoys for example.", "We need nets floats or buoys, for example.")
        static let coupledMove = Pair("en", "Should the club hire a second crew? member or does the club pay for the repairs because by then it is late or sell the old sails.", "Should the club hire a second crew member? Or does the club pay for the repairs, because by then it is late, sell the old sails.")
        static let controlMove = Pair("en", "Should the club hire a second crew? member or does the club pay for the repairs.", "Should the club hire a second crew member? Or does the club pay for the repairs.")
    }

    // MARK: - Helpers

    private func run(_ p: Pair) -> EditGuard.GuardResult {
        let r = EditGuard.apply(rulesCleaned: p.baseline, llmOutput: p.llm, language: p.lang, lexicon: TestSpellLexicon.allKnown)
        let v = EditGuardMergeAtomicityTests.neitherSourceViolations(output: r.text, sourceA: p.baseline, sourceB: p.llm)
        XCTAssertTrue(v.tier1.isEmpty, "tier-1 neither-source violation(s) \(v.tier1) in: \(r.text)")
        return r
    }

    private func edit(_ r: EditGuard.GuardResult, from: String, to: String? = nil, kind: String? = nil) -> EditGuard.ClassifiedEdit? {
        r.edits.first { $0.from == from && (to == nil || $0.to == to) && (kind == nil || $0.kind == kind) }
    }

    private func assertAccepted(_ r: EditGuard.GuardResult, from: String, to: String? = nil, kind: String? = nil, _ cls: String,
                                file: StaticString = #filePath, line: UInt = #line) {
        guard let e = edit(r, from: from, to: to, kind: kind) else {
            return XCTFail("no edit from \(from) -> \(to ?? "*") in \(r.edits)", file: file, line: line)
        }
        XCTAssertTrue(e.accepted, "expected accepted: \(e)", file: file, line: line)
        XCTAssertEqual(e.acceptClass, cls, file: file, line: line)
    }

    private func assertRejected(_ r: EditGuard.GuardResult, from: String, to: String? = nil, kind: String? = nil, _ cls: EditGuard.RejectionClass,
                                file: StaticString = #filePath, line: UInt = #line) {
        guard let e = edit(r, from: from, to: to, kind: kind) else {
            return XCTFail("no edit from \(from) -> \(to ?? "*") in \(r.edits)", file: file, line: line)
        }
        XCTAssertFalse(e.accepted, "expected rejected: \(e)", file: file, line: line)
        XCTAssertEqual(e.rejectClass, cls.rawValue, file: file, line: line)
    }

    private func assertSplitAccepted(_ p: Pair, connector: String, expectedSplits: Int = 1, file: StaticString = #filePath, line: UInt = #line) {
        let r = run(p)
        XCTAssertEqual(r.text, p.llm, file: file, line: line)
        XCTAssertEqual(r.edits.filter { $0.from == connector && $0.to == "." && $0.accepted && $0.acceptClass == "connectorSplit" }.count,
                       expectedSplits, "\(r.edits)", file: file, line: line)
    }

    /// The `and`/`und` -> `.` edit survives as a rejection with this class and the text is the baseline.
    private func assertSplitRejected(_ p: Pair, connector: String, _ cls: EditGuard.RejectionClass, file: StaticString = #filePath, line: UInt = #line) {
        let r = run(p)
        XCTAssertEqual(r.text, p.baseline, file: file, line: line)
        assertRejected(r, from: connector, to: ".", cls, file: file, line: line)
    }

    // MARK: - Audit analogues

    /// 10-03:#21 shape: two splits, an inserted comma and an inflection fix in one dictation.
    func testAudit21_twoSplitsWholeDictation_RED() {
        assertSplitAccepted(Fx.audit21, connector: "and", expectedSplits: 2)
    }

    /// 10-03:#38 shape (Rule B shape 1): trailing comma replaced by a closing period, comma added after the first word.
    func testAudit38_trailingCommaReplacedByClosingPeriod_RED() {
        let r = run(Fx.audit38)
        XCTAssertEqual(r.text, Fx.audit38.llm)
        assertAccepted(r, from: ",", to: ",", kind: "move", "punctuationMove")
    }

    /// 10-03:#71 shape (Rule B shape 2): a question mark moved over three kept words to the clause end.
    func testAudit71_questionMarkMovedToClauseEnd_RED() {
        let r = run(Fx.audit71)
        XCTAssertEqual(r.text, Fx.audit71.llm)
        assertAccepted(r, from: "?", to: "?", kind: "move", "punctuationMove")
    }

    /// 10-03:#41 shape: `and` -> `;` has no capitalisation signal and stays rejected (MA3).
    func testAudit41_semicolonSplitStaysRejected() {
        let r = run(Fx.audit41)
        assertRejected(r, from: "and", to: ";", .contentWordIdentityChange)
    }

    /// 10-03:#22 shape: `etc` -> `.` stays rejected.
    func testAudit22_etcToPeriodStaysRejected() {
        assertRejected(run(Fx.audit22), from: "etc", to: ".", .contentWordIdentityChange)
    }

    /// 10-03:#24 shape: `and` -> `,` stays rejected.
    func testAudit24_andToCommaStaysRejected() {
        assertRejected(run(Fx.audit24), from: "and", to: ",", .contentWordIdentityChange)
    }

    /// 10-03:#40 shape: `which` -> `:` stays rejected.
    func testAudit40_whichToColonStaysRejected() {
        assertRejected(run(Fx.audit40), from: "which", to: ":", .contentWordIdentityChange)
    }

    /// 10-03:#43 shape: `here` -> `.` stays rejected.
    func testAudit43_hereToPeriodStaysRejected() {
        assertRejected(run(Fx.audit43), from: "here", to: ".", .contentWordIdentityChange)
    }

    /// 10-03:#34 shape: a split coupled with a pronoun change (`this` -> `it`) in the same sentence.
    func testAudit34_splitCoupledWithPronounChange_RED() {
        let p = Fx.audit34
        assertSplitRejected(p, connector: "and", .sentenceCoupledRevert)
        assertRejected(run(p), from: "this", to: "it", .pronounPersonChange)
    }

    /// 10-03:#47 shape: coupled with `it` -> `them`.
    func testAudit47_splitCoupledWithPronounChange_RED() {
        let p = Fx.audit47
        assertSplitRejected(p, connector: "and", .sentenceCoupledRevert)
        assertRejected(run(p), from: "it", to: "them", .pronounPersonChange)
    }

    /// 10-03:#55 shape: coupled with a contraction expansion (`where's` -> `where is`), which stays rejected.
    func testAudit55_splitCoupledWithContractionExpansion_RED() {
        let p = Fx.audit55
        assertSplitRejected(p, connector: "and", .sentenceCoupledRevert)
        assertRejected(run(p), from: "where's", .contentWordIdentityChange)
    }

    /// 10-03:#63 shape: coupled with `so` -> `.`, which stays `contentWordIdentityChange`.
    func testAudit63_splitCoupledWithSoToPeriod_RED() {
        let p = Fx.audit63
        assertSplitRejected(p, connector: "and", .sentenceCoupledRevert)
        assertRejected(run(p), from: "so", to: ".", .contentWordIdentityChange)
    }

    /// 10-03:#73 shape: coupled with a `you` deletion, which stays `pronounDeleted`.
    func testAudit73_splitCoupledWithYouKnowDeletion_RED() {
        let p = Fx.audit73
        assertSplitRejected(p, connector: "and", .sentenceCoupledRevert)
        assertRejected(run(p), from: "you", kind: "delete", .pronounDeleted)
    }

    // MARK: - Positives

    func testSplitBeforeFirstPersonPronoun_RED() {
        assertSplitAccepted(Fx.firstPerson, connector: "and")
    }

    func testSplitBeforeQuestion_RED() {
        assertSplitAccepted(Fx.question, connector: "and")
    }

    func testSplitGerman_RED() {
        assertSplitAccepted(Fx.german, connector: "und")
    }

    func testSplitKeepsNegatorInContinuation_RED() {
        let r = run(Fx.negator)
        XCTAssertEqual(r.text, Fx.negator.llm)
        XCTAssertTrue(r.text.contains("Not the back door"))
        assertAccepted(r, from: "and", to: ".", "connectorSplit")
    }

    func testSplitSurvivesContentRejectionInNextSentence_RED() {
        let p = Fx.nextSentence
        let r = run(p)
        XCTAssertEqual(r.text, "The oven is hot. I will start now. we have really enough rye left for today.")
        assertAccepted(r, from: "and", to: ".", "connectorSplit")
        assertRejected(r, from: "really", kind: "delete", .contentWordDeletion)
    }

    /// MA5: without context-dependent membership the split would ship next to the reverted rest of its sentence.
    func testSplitRevertsWithContentRejectionInSameSentence_RED() {
        let p = Fx.sameSentence
        assertSplitRejected(p, connector: "and", .sentenceCoupledRevert)
        assertRejected(run(p), from: "ready", to: "finished", .contentWordIdentityChange)
    }

    // MARK: - Meaning connectors stay rejected

    func testButToPeriodStaysRejected() { assertSplitRejected(Fx.but, connector: "but", .contentWordIdentityChange) }
    func testOrToPeriodStaysRejected() { assertSplitRejected(Fx.or, connector: "or", .contentWordIdentityChange) }
    func testBecauseToPeriodStaysRejected() { assertSplitRejected(Fx.because, connector: "because", .contentWordIdentityChange) }
    /// MA4.
    func testSoToPeriodStaysRejected() { assertSplitRejected(Fx.so, connector: "so", .contentWordIdentityChange) }
    func testAberToPeriodStaysRejected() { assertSplitRejected(Fx.aber, connector: "aber", .contentWordIdentityChange) }
    func testOderToPeriodStaysRejected() { assertSplitRejected(Fx.oder, connector: "oder", .contentWordIdentityChange) }
    func testWeilToPeriodStaysRejected() { assertSplitRejected(Fx.weil, connector: "weil", .contentWordIdentityChange) }

    // MARK: - Noun coordination, marks, neighbours

    /// MA2: an already-capitalised word after `and` is a phrase coordination.
    func testNounCoordinationEnglishStaysRejected() { assertSplitRejected(Fx.nounEn, connector: "and", .contentWordIdentityChange) }
    /// MA2.
    func testNounCoordinationGermanStaysRejected() { assertSplitRejected(Fx.nounDe, connector: "und", .contentWordIdentityChange) }

    /// MA3.
    func testGermanSemicolonStaysRejected() {
        let r = run(Fx.semiDe)
        XCTAssertEqual(r.text, Fx.semiDe.baseline)
        assertRejected(r, from: "und", to: ";", .contentWordIdentityChange)
    }

    /// MA1: the word after the connector changes.
    func testNextWordChangedStaysRejected() { assertSplitRejected(Fx.nextChanged, connector: "and", .contentWordIdentityChange) }
    /// MA1: the word before the connector changes (singular to plural).
    func testPreviousWordChangedStaysRejected() { assertSplitRejected(Fx.prevChanged, connector: "and", .contentWordIdentityChange) }

    func testNegatorDroppedWithSplitStaysRejected() {
        let r = run(Fx.negDropped)
        XCTAssertEqual(r.text, Fx.negDropped.baseline)
        XCTAssertTrue(r.text.contains("and not the shed"))
    }

    /// A comma before the connector makes the `and` edit a delete, which Rule A cannot reach.
    func testCommaBeforeConnectorNotReached() {
        XCTAssertEqual(run(Fx.commaBefore).text, Fx.commaBefore.baseline)
    }

    /// Phase 49.6 D-09: `und` -> `oder` is a word swap and stays rejected.
    func testD09_undToOderStaysRejected() {
        let r = run(Fx.undOder)
        XCTAssertEqual(r.text, Fx.undOder.baseline)
        assertRejected(r, from: "und", to: "oder", .contentWordIdentityChange)
    }

    // MARK: - Moves

    /// MB2: a terminal mark moved to directly after a coordinator.
    func testMoveAfterCoordinatorStaysRejected() {
        let r = run(Fx.moveAfterCoord)
        XCTAssertEqual(r.text, Fx.moveAfterCoord.baseline)
        assertRejected(r, from: "?", to: "?", kind: "move", .unclassified)
    }

    func testMovedPeriodBeforeLowercaseStaysRejected() {
        let r = run(Fx.moveBeforeLower)
        XCTAssertEqual(r.text, Fx.moveBeforeLower.baseline)
        assertRejected(r, from: "?", to: "?", kind: "move", .unclassified)
    }

    /// MB1: a list comma jumping three words is not a terminal mark.
    func testCommaJumpStaysRejected() {
        let r = run(Fx.commaJump)
        XCTAssertEqual(r.text, Fx.commaJump.baseline)
        assertRejected(r, from: ",", to: ",", kind: "move", .unclassified)
    }

    /// MC1: the move is accepted, but the recase of the word after it is reverted together with its sentence
    /// (an independent content rejection sits in the FOLLOWING baseline sentence), so the move reverts too.
    func testMoveRevertsWithRevertedRecase_RED() {
        let r = run(Fx.coupledMove)
        XCTAssertEqual(r.text, Fx.coupledMove.baseline)
        assertRejected(r, from: "?", to: "?", kind: "move", .sentenceCoupledRevert)
        assertRejected(r, from: "or", to: "Or", .sentenceCoupledRevert)
        assertRejected(r, from: "or", to: ",", .contentWordIdentityChange)
    }

    /// Control for MC1: the same pair without the later rejection ships the move and the recase.
    func testMoveAndRecaseShipWithoutLaterRejection_RED() {
        let r = run(Fx.controlMove)
        XCTAssertEqual(r.text, Fx.controlMove.llm)
        assertAccepted(r, from: "?", to: "?", kind: "move", "punctuationMove")
        assertAccepted(r, from: "or", to: "Or", "punctuationOrCasing")
    }
}
