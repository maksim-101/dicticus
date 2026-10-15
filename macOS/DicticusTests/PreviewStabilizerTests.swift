import XCTest
@testable import Dicticus

final class PreviewStabilizerTests: XCTestCase {

    private func words(_ range: ClosedRange<Int>) -> String {
        range.map { "w\($0)" }.joined(separator: " ")
    }

    private func shown(_ s: PreviewStabilizer) -> [String] { s.settled + s.tentative }

    private func assertNoRepeatedWord(_ s: PreviewStabilizer, file: StaticString = #filePath, line: UInt = #line) {
        let all = shown(s)
        XCTAssertEqual(all.count, Set(all).count, "a word appears twice: \(all)", file: file, line: line)
    }

    // MARK: - Agreement and hold-back

    func testFirstHypothesisIsAllTentative() {
        var s = PreviewStabilizer()
        s.ingest("the quick brown")
        XCTAssertEqual(s.settledText, "")
        XCTAssertEqual(s.tentativeText, "the quick brown")
    }

    func testAgreedWordsSettleAndTheNewestTwoStayTentative() {
        var s = PreviewStabilizer()
        s.ingest("the quick brown")
        s.ingest("the quick brown fox jumps")
        XCTAssertEqual(s.settledText, "the quick brown")
        XCTAssertEqual(s.tentativeText, "fox jumps")
    }

    func testTheLastTwoWordsNeverSettleEvenWhenEveryDecodeAgrees() {
        var s = PreviewStabilizer()
        for _ in 0..<5 { s.ingest("a b c d e") }
        XCTAssertEqual(s.settledText, "a b c")
        XCTAssertEqual(s.tentativeText, "d e")
    }

    func testARevisedTailWordStaysTentative() {
        var s = PreviewStabilizer()
        s.ingest("we meet")
        s.ingest("we meeting at")
        XCTAssertEqual(s.settledText, "we")
        XCTAssertEqual(s.tentativeText, "meeting at")
        XCTAssertFalse(s.settled.contains("meet"))
    }

    func testAnUnsharedWordNeverSettles() {
        var s = PreviewStabilizer()
        s.ingest("one two three four")
        s.ingest("one two tree four five")
        XCTAssertEqual(s.settledText, "one two")
        XCTAssertEqual(s.tentativeText, "tree four five")
    }

    func testSettleAllMovesEveryTentativeWordToSettled() {
        var s = PreviewStabilizer()
        s.ingest("alpha beta gamma")
        s.ingest("alpha beta gamma delta")
        s.settleAll()
        XCTAssertEqual(s.settledText, "alpha beta gamma delta")
        XCTAssertEqual(s.tentativeText, "")
    }

    func testEmptyHypothesisKeepsSettledAndCountsNothing() {
        var s = PreviewStabilizer()
        for _ in 0..<2 { s.ingest(words(1...8)) }
        let before = s.settled
        s.ingest("   ")
        XCTAssertEqual(s.settled, before)
        XCTAssertTrue(s.tentative.isEmpty)
        XCTAssertEqual(s.conflicts + s.gaps, 0)
    }

    // MARK: - Window slide

    func testWindowSlideKeepsSettledAndAddsNothingTwice() {
        var s = PreviewStabilizer()
        s.ingest(words(1...14))
        s.ingest(words(1...14))
        XCTAssertEqual(s.settledText, words(1...12), "precondition: 12 settled words")

        // The 15 s window moved on: the first 4 words are gone, 2 are new.
        s.ingest(words(5...16))

        XCTAssertEqual(Array(s.settled.prefix(12)), (1...12).map { "w\($0)" }, "settled never changes")
        assertNoRepeatedWord(s)
        XCTAssertEqual(shown(s), (1...16).map { "w\($0)" })
        XCTAssertEqual(s.tentativeText, "w15 w16")
        XCTAssertEqual(s.conflicts + s.gaps, 0, "a plain slide needs no fallback")
    }

    func testWindowSlideKeepsWorkingTickAfterTick() {
        var s = PreviewStabilizer()
        s.ingest(words(1...14))
        s.ingest(words(1...14))
        for end in 15...40 {
            let start = max(1, end - 11)
            s.ingest(words(start...end))
            s.ingest(words(start...end))
        }
        XCTAssertEqual(shown(s), (1...40).map { "w\($0)" })
        XCTAssertEqual(s.conflicts + s.gaps, 0)
    }

    func testShortSettledTextIsAlignedByPositionNotByTheRightmostMatch() {
        var s = PreviewStabilizer()
        s.ingest("the dog sat")
        s.ingest("the dog sat")
        XCTAssertEqual(s.settledText, "the")
        XCTAssertEqual(s.tentativeText, "dog sat")

        s.ingest("the dog sat on the mat")
        XCTAssertEqual(shown(s), ["the", "dog", "sat", "on", "the", "mat"])
    }

    // MARK: - Alignment fallbacks

    func testPunctuationAndCaseChangesOnSettledWordsStillAnchor() {
        var s = PreviewStabilizer()
        s.ingest("Please move it to Thursday afternoon if the room")
        s.ingest("Please move it to Thursday afternoon if the room")
        XCTAssertEqual(s.settledText, "Please move it to Thursday afternoon if")

        s.ingest("please move it to thursday afternoon, if the")
        XCTAssertEqual(s.settledText, "Please move it to Thursday afternoon if")
        XCTAssertEqual(s.tentativeText, "the")
        XCTAssertEqual(s.conflicts, 0)
        XCTAssertEqual(s.gaps, 0)
    }

    func testRevisedSettledWordKeepsSettledAndRepeatsNothing() {
        var s = PreviewStabilizer()
        s.ingest("we go to the meet at noon")
        s.ingest("we go to the meet at noon")
        XCTAssertEqual(s.settledText, "we go to the meet")
        XCTAssertEqual(s.tentativeText, "at noon")

        s.ingest("we go to the meeting at noon")
        XCTAssertEqual(s.settledText, "we go to the meet", "settled text never shrinks or changes")
        XCTAssertEqual(s.tentativeText, "at noon")
        XCTAssertEqual(s.conflicts, 1)
        XCTAssertEqual(s.gaps, 0)
        assertNoRepeatedWord(s)
    }

    func testRecoveryAfterARevisionSettlesNewWordsAndTheConflictCountStopsRising() {
        var s = PreviewStabilizer()
        s.ingest("we go to the meet at noon")
        s.ingest("we go to the meet at noon")
        let revised = "we go to the meeting at noon today please send it now"
        s.ingest(revised)
        XCTAssertEqual(s.conflicts, 1)

        var previous = s.settled.count
        var counts: [Int] = []
        for _ in 0..<8 {
            s.ingest(revised)
            XCTAssertGreaterThanOrEqual(s.settled.count, previous, "settled never shrinks")
            previous = s.settled.count
            counts.append(s.conflicts)
        }
        XCTAssertEqual(s.settledText.hasPrefix("we go to the meet"), true)
        XCTAssertGreaterThan(s.settled.count, 5, "new words settled after the revision")
        XCTAssertEqual(counts.last, counts[counts.count - 2], "the count stops rising once anchored again")
        assertNoRepeatedWord(s)
    }

    func testLongPauseKeepsSettledAndStartsTheNewSpeechAfterIt() {
        var s = PreviewStabilizer()
        s.ingest("a b c d e f g h")
        s.ingest("a b c d e f g h")
        XCTAssertEqual(s.settledText, "a b c d e f")

        // Resumed after a pause longer than the window: nothing of the old words is in the decode.
        s.ingest("completely new words")
        XCTAssertEqual(s.settledText, "a b c d e f", "settled is not replaced on a gap")
        XCTAssertEqual(s.tentativeText, "completely new words")
        XCTAssertEqual(s.gaps, 1)
        XCTAssertEqual(s.conflicts, 0)

        s.ingest("completely new words here")
        XCTAssertEqual(s.settledText, "a b c d e f completely new")
        XCTAssertEqual(s.tentativeText, "words here")
    }

    // MARK: - Invariants

    func testSettledOnlyEverGrowsAcrossRevisionsSlidesAndGaps() {
        var s = PreviewStabilizer()
        let script = [
            words(1...6), words(1...8), words(1...8), words(3...10), words(3...10),
            "x1 x2 w9 w10", words(4...12), words(4...12), "totally different speech now", words(4...12),
            "totally different speech now again", "totally different speech now again and more"
        ]
        var previous: [String] = []
        for hypothesis in script {
            s.ingest(hypothesis)
            XCTAssertEqual(Array(s.settled.prefix(previous.count)), previous, "settled changed on \(hypothesis)")
            previous = s.settled
        }
    }
}
