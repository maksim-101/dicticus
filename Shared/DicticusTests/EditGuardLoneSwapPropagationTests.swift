import XCTest
@testable import Dicticus

/// Quick task 261003-gp8: punctuation and casing lost to one rejected swapped word.
///
/// The defect: when the AI cleanup swapped a single word for another word
/// and `EditGuard` rejected that swap (`contentWordIdentityChange`),
/// `applySentenceCoupledRevert` returned the whole raw sentence to the raw
/// text, so the commas and capitals the cleanup got right in that sentence
/// were thrown away with the swap.
///
/// The carve-out: a triggered raw sentence whose ONLY trigger is a lone word
/// swap keeps its accepted `punctuationOrCasing` edits. The swap itself stays
/// rejected. A sentence qualifies only when all of these hold:
/// - the swap is a `.substitute` of one word for one word, rejected as
///   `contentWordIdentityChange`, with no other word edit in its keep-bounded
///   cluster (equal token count);
/// - neither side is a coordinator or negator, a pronoun, a number word or
///   contains a digit;
/// - the sentence has no terminal-mark change (`.`, `?`, `!`), except an
///   utterance-final `.` insert, which `applySentenceCoupledRevert` already
///   spares;
/// - it has no second trigger.
/// Only `punctuationOrCasing` is released, and a released casing edit may not
/// lower a capitalised word's first letter. Function-word, inflection, word
/// order, pause-split and contraction edits stay coupled to the sentence, as
/// do the D-15 boundary and the au9 `punctuationMove` loops. Edits sharing the
/// swap's own cluster are reverted by `applyAtomicGroupCoupling` first, so no
/// released mark ends up next to a reverted word.
///
/// Every fixture is an invented sentence about an apiary. Records are cited
/// only by timestamp or `MM-DD:N`. `_RED` in a name means the test fails at
/// the start commit; every other test is a pin that must hold before and after
/// the change. Guard pins and their mutations: M1 lone (`testTwoSwaps...`),
/// M2 word to word (`testWordToCommaSwap...`), M3 coordinator or negator
/// (`testCoordinatorSwap...`, `testNegatorSwap...`), M4 terminal exclusion
/// (`testPeriodSplit...`, `testQuestionMark...`, `testPeriodDeleteMerge...`),
/// M5 release set (`testFunctionWordFix...`), M45 both (`testPauseSplitMerge...`),
/// M6 utterance-final period (`testUtteranceFinalPeriod...`), M9 number words
/// (`testNumberWordSwap...`), M11 lowering (`testLoweringEdit...`), M12 cluster
/// (`testSwapSharingCluster...`). A pronoun-side swap is classified
/// `pronounPersonChange`, not `contentWordIdentityChange`, so the pronoun check
/// in the predicate is defensive and has no test; a mood-lock rejection cannot
/// coexist with a released sentence (the word-order move is flipped first), so
/// it has none either.
@MainActor
final class EditGuardLoneSwapPropagationTests: XCTestCase {

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
        static let commas = Pair("en",
            "after the inspection the beekeeper moved two frames into the weaker hive and then closed the lid.",
            "After the inspection, the beekeeper moved two frames into the weaker hive, and then shut the lid.")
        static let casingAfterPeriod = Pair("en",
            "The smoker is almost empty. we need more pine needles before the next round of hive checks.",
            "The smoker is almost empty. We need more dry needles before the next round of hive checks.")
        static let adjacentComma = Pair("en",
            "the queen laid eggs in the lower frame and the workers capped the honey yesterday evening.",
            "The queen laid eggs in the lower frame, and the workers sealed, the honey yesterday evening.")
        static let german = Pair("de",
            "ich glaube dass der Imker die Waben morgen früh kontrollieren muss weil das Volk unruhig ist.",
            "Ich glaube, dass der Imker die Waben morgen früh prüfen muss, weil das Volk unruhig ist.")
        static let finalPeriod = Pair("en",
            "the drone cells are capped so we can move the frame to the new box",
            "The drone cells are capped, so we can shift the frame to the new box.")
        static let lowering = Pair("de",
            "ich glaube dass wir die Waben Stück für Stück zählen müssen und den Honig prüfen.",
            "Ich glaube, dass wir die Waben stück für Stück zählen müssen und den Honig testen.")

        // Negatives
        static let clusterWithInsert = Pair("en",
            "- Yes, we can check the hive, and later I wanna light the smoker because the bees are restless.",
            "Yes, we can check the hive, and later I want to light the smoker because the bees are restless.")
        static let twoSwaps = Pair("en",
            "after the inspection the beekeeper moved two frames into the weaker hive and then closed the lid.",
            "After the inspection, the beekeeper shifted two frames into the weaker hive, and then shut the lid.")
        static let wordToComma = Pair("en",
            "the keeper lifted the roof then checked the frames and added a super before dusk.",
            "The keeper lifted the roof, checked the frames, and added a super before dusk.")
        static let coordinator = Pair("en",
            "after the rain we need smoke and a veil before the inspection starts today.",
            "After the rain, we need smoke or a veil before the inspection starts today.")
        static let negator = Pair("de",
            "heute haben wir nicht Honig geschleudert weil der Regen kam.",
            "Heute haben wir kein Honig geschleudert, weil der Regen kam.")
        static let periodSplit = Pair("en",
            "the frames are heavy and we should lift them together because the lids are loose.",
            "The frames are heavy. We should lift them together because the lids are tight.")
        static let questionMark = Pair("en",
            "the queen is laying well in the new box.",
            "The queen is laying fine in the new box?")
        static let periodDeleteMerge = Pair("en",
            "The bees are calm today. and the queen is laying well.",
            "The bees are quiet today and the queen is laying well.")
        static let functionWordFix = Pair("de",
            "Der Honig schleudere ich morgen mit dem Imkerverein Bergblick",
            "Den Honig verkaufe ich morgen mit dem Imkerverein Bergblick.")
        static let pauseSplit = Pair("de",
            "Mir fehlt dafür die Zeit oder Geschick. dass ich die Völker allein betreue glaube ich nicht.",
            "Mir fehlt dafür die Zeit oder Geduld dass ich die Völker allein betreue, glaube ich nicht.")
        static let numberWord = Pair("en",
            "we moved two frames into the weaker hive and closed the lid.",
            "We moved three frames into the weaker hive, and closed the lid.")
    }

    // MARK: - Helpers

    private func run(_ p: Pair) -> EditGuard.GuardResult {
        let r = EditGuard.apply(rulesCleaned: p.baseline, llmOutput: p.llm, language: p.lang, lexicon: TestSpellLexicon.allKnown)
        let v = EditGuardMergeAtomicityTests.neitherSourceViolations(output: r.text, sourceA: p.baseline, sourceB: p.llm)
        XCTAssertTrue(v.tier1.isEmpty, "tier-1 neither-source violation(s) \(v.tier1) in: \(r.text)")
        return r
    }

    private func swap(_ r: EditGuard.GuardResult, _ from: String, _ to: String) -> EditGuard.ClassifiedEdit? {
        r.edits.first { $0.kind == "substitute" && $0.from == from && $0.to == to }
    }

    /// Output equals `expected`, the named swap is rejected as a content change, and every accepted non-keep edit
    /// carries `punctuationOrCasing`.
    private func assertShips(_ p: Pair, _ expected: String, swapFrom: String, swapTo: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        let r = run(p)
        XCTAssertEqual(r.text, expected, file: file, line: line)
        guard let s = swap(r, swapFrom, swapTo) else {
            return XCTFail("no substitute \(swapFrom) -> \(swapTo) in \(r.edits)", file: file, line: line)
        }
        XCTAssertFalse(s.accepted, "\(s)", file: file, line: line)
        XCTAssertEqual(s.rejectClass, EditGuard.RejectionClass.contentWordIdentityChange.rawValue, file: file, line: line)
        let accepted = r.edits.filter { $0.kind != "keep" && $0.accepted }
        XCTAssertFalse(accepted.isEmpty, "\(r.edits)", file: file, line: line)
        XCTAssertTrue(accepted.allSatisfy { $0.acceptClass == EditGuard.AcceptClass.punctuationOrCasing.rawValue },
                      "\(accepted)", file: file, line: line)
    }

    /// Output equals `expected` (the raw text, plus whatever bbz keeps) and a sentenceCoupledRevert line is present.
    private func assertCouples(_ p: Pair, _ expected: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        let r = run(p)
        XCTAssertEqual(r.text, expected, file: file, line: line)
        XCTAssertTrue(r.edits.contains { $0.rejectClass == EditGuard.RejectionClass.sentenceCoupledRevert.rawValue },
                      "\(r.edits)", file: file, line: line)
    }

    // MARK: - Positives

    /// Two keep-separated commas and a first-word capital ship next to the rejected swap.
    func testLoneSwapKeepsKeepSeparatedCommas_RED() {
        assertShips(Fx.commas,
                    "After the inspection, the beekeeper moved two frames into the weaker hive, and then closed the lid.",
                    swapFrom: "closed", swapTo: "shut")
    }

    /// A capital after a kept period ships; the swap in the same raw sentence reverts.
    func testLoneSwapKeepsCasingAfterKeptPeriod_RED() {
        assertShips(Fx.casingAfterPeriod,
                    "The smoker is almost empty. We need more pine needles before the next round of hive checks.",
                    swapFrom: "pine", swapTo: "dry")
    }

    /// A comma directly after the swapped word shares its cluster and reverts with it; the keep-separated comma ships.
    func testLoneSwapAdjacentCommaStaysWithSwap_RED() {
        let p = Fx.adjacentComma
        assertShips(p,
                    "The queen laid eggs in the lower frame, and the workers capped the honey yesterday evening.",
                    swapFrom: "capped", swapTo: "sealed")
        let r = run(p)
        let commas = r.edits.filter { $0.kind == "insert" && $0.to == "," }
        XCTAssertEqual(commas.count, 2, "\(r.edits)")
        XCTAssertEqual(commas.filter { !$0.accepted }.map(\.rejectClass),
                       [EditGuard.RejectionClass.atomicGroupRevert.rawValue])
    }

    func testGermanLoneSwapKeepsComma_RED() {
        assertShips(Fx.german,
                    "Ich glaube, dass der Imker die Waben morgen früh kontrollieren muss, weil das Volk unruhig ist.",
                    swapFrom: "kontrollieren", swapTo: "prüfen")
    }

    /// M6: no final mark in the raw; the LLM appends `.`. The period does not disqualify the sentence.
    func testUtteranceFinalPeriodDoesNotBlock_RED() {
        assertShips(Fx.finalPeriod,
                    "The drone cells are capped, so we can move the frame to the new box.",
                    swapFrom: "move", swapTo: "shift")
    }

    /// M11: the capitalised noun `Stück` lowered to `stück` stays reverted; the comma and the capital `Ich` ship.
    func testLoweringEditStaysReverted_RED() {
        let p = Fx.lowering
        assertShips(p,
                    "Ich glaube, dass wir die Waben Stück für Stück zählen müssen und den Honig prüfen.",
                    swapFrom: "prüfen", swapTo: "testen")
        let r = run(p)
        XCTAssertTrue(r.edits.contains { $0.kind == "substitute" && $0.from == "Stück" && $0.to == "stück" && !$0.accepted }, "\(r.edits)")
    }

    // MARK: - Negatives: each keeps the sentence coupled through one guard

    /// M12: the swap `wanna` -> `want` shares its cluster with the inserted `to` (one word for two). Not an equal-count
    /// swap, so the leading-dash delete reverts with the sentence (the shape of a pinned production record).
    func testSwapSharingClusterWithWordInsertStillCouples() {
        let p = Fx.clusterWithInsert
        assertCouples(p, p.baseline)
    }

    /// M1: a second swap in the same sentence.
    func testTwoSwapsStillCouple() {
        let p = Fx.twoSwaps
        assertCouples(p, p.baseline)
    }

    /// M2: the swap's target is a comma, not a word.
    func testWordToCommaSwapStillCouples() {
        let p = Fx.wordToComma
        assertCouples(p, p.baseline)
    }

    /// M3: `and` -> `or` changes the clause relation.
    func testCoordinatorSwapStillCouples() {
        let p = Fx.coordinator
        assertCouples(p, p.baseline)
    }

    /// M3: `nicht` -> `kein` changes polarity.
    func testNegatorSwapStillCouples() {
        let p = Fx.negator
        assertCouples(p, p.baseline)
    }

    /// M4: a mid-sentence `.` with the next word capitalised.
    func testPeriodSplitInSentenceStillCouples() {
        let p = Fx.periodSplit
        assertCouples(p, p.baseline)
    }

    /// M4: the raw final `.` becomes `?` (statement to question).
    func testQuestionMarkStillCouples() {
        let p = Fx.questionMark
        assertCouples(p, p.baseline)
    }

    /// M4: a `.` delete merging two raw sentences, with a swap in the first.
    func testPeriodDeleteMergeStillCouples() {
        let p = Fx.periodDeleteMerge
        assertCouples(p, p.baseline)
    }

    /// M5: an article case change keep-separated from the swap is not released (it can be conditioned on the swapped
    /// verb). The utterance-final `.` still stands (260926-bbz).
    func testFunctionWordFixStillRevertsWithLoneSwap() {
        let p = Fx.functionWordFix
        assertCouples(p, p.baseline + ".")
    }

    /// M45: a pause-split period delete is held by the terminal exclusion and by the release set; only the comma in
    /// the next raw sentence, which is outside the lone-swap sentence, ships.
    func testPauseSplitMergeStillRevertsWithLoneSwap() {
        let p = Fx.pauseSplit
        assertCouples(p, "Mir fehlt dafür die Zeit oder Geschick. dass ich die Völker allein betreue, glaube ich nicht.")
    }

    /// M9: a number word swap (`two` -> `three`) is a content change of quantity.
    func testNumberWordSwapStillCouples() {
        let p = Fx.numberWord
        assertCouples(p, p.baseline)
    }
}
