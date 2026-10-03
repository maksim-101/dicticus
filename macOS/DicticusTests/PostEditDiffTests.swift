#if DEBUG_RECORDER
import XCTest
@testable import Dicticus

/// Quick task 261003-jvq: pure logic of the post-paste edit log. Invented text only.
final class PostEditDiffTests: XCTestCase {

    private let bordered = "│ > Ask the robot to │\n│   water it twice   │\n"

    private func offset(of word: String, in s: String) -> Int {
        (s as NSString).range(of: word).location
    }

    private func located(_ r: Result<(range: Range<Int>, matchKind: PostEditDiff.MatchKind), PostEditDiff.LocateFailure>,
                         file: StaticString = #filePath, line: UInt = #line) -> (range: Range<Int>, matchKind: PostEditDiff.MatchKind)? {
        if case .success(let v) = r { return v }
        XCTFail("expected success, got \(r)", file: file, line: line)
        return nil
    }

    // MARK: tokenize

    func testTokenizeSplitsOnBoxDrawingAndKeepsUTF16Offsets() {
        let tokens = PostEditDiff.tokenize(bordered)
        XCTAssertEqual(tokens.map(\.text), [">", "Ask", "the", "robot", "to", "water", "it", "twice"])
        guard tokens.count == 8 else { return }
        XCTAssertEqual(tokens[1].utf16Start, offset(of: "Ask", in: bordered))
        XCTAssertEqual(tokens[1].utf16End, offset(of: "Ask", in: bordered) + 3)
        XCTAssertEqual(tokens[5].utf16Start, offset(of: "water", in: bordered))
    }

    func testTokenizePlainWhitespace() {
        XCTAssertEqual(PostEditDiff.tokenize("one  two\tthree").map(\.text), ["one", "two", "three"])
    }

    // MARK: exclusion

    func testExclusionOrder() {
        XCTAssertEqual(PostEditDiff.exclusion(bundleID: "com.1password.1password", role: "AXTextArea", subrole: nil), .excludedApp)
        XCTAssertEqual(PostEditDiff.exclusion(bundleID: "com.example.notes", role: "AXTextField", subrole: "AXSecureTextField"), .secure)
        XCTAssertNil(PostEditDiff.exclusion(bundleID: "com.example.notes", role: "AXTextArea", subrole: nil))
        XCTAssertEqual(PostEditDiff.exclusion(bundleID: "com.1password.1password", role: "AXTextField", subrole: "AXSecureTextField"), .excludedApp)
    }

    // MARK: locateAtPaste

    func testLocatePlainField() {
        let field = "Intro line. Ask the robot to water it "
        let tokens = PostEditDiff.tokenize(field)
        let r = PostEditDiff.locateAtPaste(pasted: "Ask the robot to water it", field: field,
                                           fieldTokens: tokens, caretUTF16: field.utf16.count)
        guard let v = located(r) else { return }
        XCTAssertEqual(v.range, 2..<8)
        XCTAssertEqual(v.matchKind, .exact)
    }

    func testLocateDuplicatePrefersOccurrenceNearestCaret() {
        let field = "Ask the robot to water it and then Ask the robot to water it "
        let tokens = PostEditDiff.tokenize(field)
        let pasted = "Ask the robot to water it"
        let firstEnd = (field as NSString).range(of: "it").upperBound
        let secondEnd = field.utf16.count - 1
        let atSecond = located(PostEditDiff.locateAtPaste(pasted: pasted, field: field, fieldTokens: tokens, caretUTF16: secondEnd))
        XCTAssertEqual(atSecond?.range, 8..<14)
        let atFirst = located(PostEditDiff.locateAtPaste(pasted: pasted, field: field, fieldTokens: tokens, caretUTF16: firstEnd))
        XCTAssertEqual(atFirst?.range, 0..<6)
        let noCaret = located(PostEditDiff.locateAtPaste(pasted: pasted, field: field, fieldTokens: tokens, caretUTF16: nil))
        XCTAssertEqual(noCaret?.range, 8..<14)
    }

    func testLocateBorderedWrapMatchesByTokens() {
        let tokens = PostEditDiff.tokenize(bordered)
        let caret = offset(of: "twice", in: bordered) + 5
        let r = PostEditDiff.locateAtPaste(pasted: "Ask the robot to water it twice", field: bordered,
                                           fieldTokens: tokens, caretUTF16: caret)
        guard let v = located(r) else { return }
        XCTAssertEqual(v.range, 1..<8)
        XCTAssertEqual(v.matchKind, .tokens)
    }

    func testLocateFailures() {
        let field = "Something else entirely here "
        let tokens = PostEditDiff.tokenize(field)
        if case .failure(let f) = PostEditDiff.locateAtPaste(pasted: "Water it", field: field, fieldTokens: tokens, caretUTF16: nil) {
            XCTAssertEqual(f, .tooShort)
        } else { XCTFail("expected too_short") }
        if case .failure(let f) = PostEditDiff.locateAtPaste(pasted: "Ask the robot to water it", field: field, fieldTokens: tokens, caretUTF16: nil) {
            XCTAssertEqual(f, .pasteTime)
        } else { XCTFail("expected paste_time") }
    }

    // MARK: record encoding

    func testRecordEncodingOmitsNilKeys() throws {
        let r = PostEditDiff.Record(
            ts: "2026-10-03T10:00:01.000Z", paste_ts: "2026-10-03T10:00:00.000Z",
            dictation_ts: nil, dictation_emission: nil, bundle_id: "com.example.notes", mode: "plain",
            pasted_words: 5, outcome: .spanNotFound, reason: "paste_time", located_at_paste: false,
            match_kind: nil, end: nil, polls: 0, located_polls: 0, observed_ms: nil, last_located_ms: nil,
            ax_ms_max: 1.5, role: "AXTextArea", subrole: nil, field_utf16: 40, secure_input_enabled: false,
            changes: nil, changes_truncated: nil, word_edits: 0, observable_edit: false)
        let data = try XCTUnwrap(PostEditDiff.encodeLine(r))
        XCTAssertEqual(data.last, 0x0A)
        XCTAssertEqual(data.filter { $0 == 0x0A }.count, 1)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(obj["outcome"] as? String, "span-not-found")
        XCTAssertEqual(obj["reason"] as? String, "paste_time")
        XCTAssertEqual(obj["observable_edit"] as? Bool, false)
        XCTAssertEqual(obj["word_edits"] as? Int, 0)
        for key in ["dictation_ts", "changes", "end"] { XCTAssertNil(obj[key], key) }
        let back = try JSONDecoder().decode(PostEditDiff.Record.self, from: data)
        XCTAssertEqual(back.outcome, .spanNotFound)
        XCTAssertEqual(back.reason, "paste_time")
        XCTAssertEqual(back.pasted_words, 5)
    }

    // MARK: relocate

    private let sentence = ["Ask", "the", "robot", "to", "water", "it", "twice"]

    private func toks(_ s: String) -> [PostEditDiff.Token] { PostEditDiff.tokenize(s) }

    func testRelocateToleratesOneChangedWordAnywhere() {
        XCTAssertEqual(PostEditDiff.relocate(pasted: sentence, fieldTokens: toks("Ask the rover to water it twice"), caretUTF16: nil), 0..<7)
        XCTAssertEqual(PostEditDiff.relocate(pasted: sentence, fieldTokens: toks("Tell the robot to water it twice"), caretUTF16: nil), 0..<7)
    }

    func testRelocateReturnsNilWithoutTheSentence() {
        XCTAssertNil(PostEditDiff.relocate(pasted: sentence, fieldTokens: toks("completely unrelated words here today"), caretUTF16: nil))
    }

    func testRelocateTwiceChoosesRegionNearestCaret() {
        let field = "Ask the robot to water it twice and then Ask the robot to water it twice"
        let firstEnd = (field as NSString).range(of: "twice").upperBound
        XCTAssertEqual(PostEditDiff.relocate(pasted: sentence, fieldTokens: toks(field), caretUTF16: firstEnd), 0..<7)
        XCTAssertEqual(PostEditDiff.relocate(pasted: sentence, fieldTokens: toks(field), caretUTF16: field.utf16.count), 9..<16)
    }

    func testRelocateBoundIsTwoEditsForSevenTokens() {
        XCTAssertEqual(PostEditDiff.relocate(pasted: sentence, fieldTokens: toks("Ask the rover to water it thrice"), caretUTF16: nil), 0..<7)
        XCTAssertNil(PostEditDiff.relocate(pasted: sentence, fieldTokens: toks("Ask the rover to drink it thrice"), caretUTF16: nil))
    }

    // MARK: diff

    private func swapChange() -> PostEditDiff.Change {
        PostEditDiff.Change(kind: "word", from: ["robot"], to: ["rover"], before: ["Ask", "the"],
                            after: ["to", "water", "it"], from_n: 1, to_n: 1)
    }

    func testDiffSingleSwap() {
        let d = PostEditDiff.diff(pasted: sentence, current: ["Ask", "the", "rover", "to", "water", "it", "twice"])
        XCTAssertEqual(d.changes, [swapChange()])
        XCTAssertEqual(d.truncated, 0)
    }

    func testDiffContextIsClampedToTheSpan() {
        let d = PostEditDiff.diff(pasted: sentence, current: ["Tell", "the", "robot", "to", "water", "it", "twice"])
        XCTAssertEqual(d.changes, [PostEditDiff.Change(kind: "word", from: ["Ask"], to: ["Tell"], before: [],
                                                       after: ["the", "robot", "to"], from_n: 1, to_n: 1)])
    }

    func testDiffCasePunctInsertAndDelete() {
        let cp = PostEditDiff.diff(pasted: sentence, current: ["Ask", "the", "robot", "to", "water", "it", "twice."])
        XCTAssertEqual(cp.changes, [PostEditDiff.Change(kind: "case_punct", from: ["twice"], to: ["twice."],
                                                        before: ["to", "water", "it"], after: [], from_n: 1, to_n: 1)])
        let ins = PostEditDiff.diff(pasted: sentence, current: ["Ask", "the", "new", "robot", "to", "water", "it", "twice"])
        XCTAssertEqual(ins.changes, [PostEditDiff.Change(kind: "word", from: [], to: ["new"], before: ["Ask", "the"],
                                                         after: ["robot", "to", "water"], from_n: 0, to_n: 1)])
        let del = PostEditDiff.diff(pasted: sentence, current: ["Ask", "the", "to", "water", "it", "twice"])
        XCTAssertEqual(del.changes, [PostEditDiff.Change(kind: "word", from: ["robot"], to: [], before: ["Ask", "the"],
                                                         after: ["to", "water", "it"], from_n: 1, to_n: 0)])
    }

    func testDiffCaps() {
        let big = PostEditDiff.diff(pasted: sentence, current: ["Ask", "a1", "b2", "c3", "d4", "e5", "f6", "g7", "twice"])
        XCTAssertEqual(big.changes, [PostEditDiff.Change(kind: "rewrite", from: nil, to: nil, before: nil, after: nil,
                                                         from_n: 5, to_n: 7)])
        var pasted: [String] = [], current: [String] = []
        for i in 0..<9 {
            pasted.append("a\(i)"); current.append("b\(i)")
            if i < 8 { pasted.append("s\(i)"); current.append("s\(i)") }
        }
        let many = PostEditDiff.diff(pasted: pasted, current: current)
        XCTAssertEqual(many.changes.count, 8)
        XCTAssertEqual(many.truncated, 1)
    }

    // MARK: session

    private func read(_ s: String, focused: Bool = true) -> PostEditDiff.FieldRead {
        .read(tokens: toks(s), caretUTF16: nil, stillFocused: focused)
    }

    func testSessionSendBoxEditThenClearedFieldIsEdited() {
        var s = PostEditDiff.Session(pasted: sentence)
        XCTAssertNil(s.ingest(read("Ask the rover to water it twice"), elapsedMs: 500))
        XCTAssertNil(s.ingest(read(""), elapsedMs: 1000))
        XCTAssertEqual(s.ingest(read(""), elapsedMs: 1500), .spanLost)
        let r = s.result()
        XCTAssertEqual(r.outcome, .edited)
        XCTAssertEqual(r.changes, [swapChange()])
        XCTAssertEqual(r.wordEdits, 1)
        XCTAssertEqual(s.polls, 3)
        XCTAssertEqual(s.locatedPolls, 1)
    }

    func testSessionElementGone() {
        var s = PostEditDiff.Session(pasted: sentence)
        XCTAssertEqual(s.ingest(.gone, elapsedMs: 500), .elementGone)
        XCTAssertEqual(s.result().outcome, .fieldGone)
    }

    func testSessionNeverRelocated() {
        var s = PostEditDiff.Session(pasted: sentence)
        XCTAssertNil(s.ingest(read("nothing to see"), elapsedMs: 500))
        XCTAssertEqual(s.ingest(read("nothing to see"), elapsedMs: 1000), .spanLost)
        let r = s.result()
        XCTAssertEqual(r.outcome, .spanNotFound)
        XCTAssertEqual(r.reason, "lost")
    }

    func testSessionFocusLeftUsesThatPollsTokens() {
        var s = PostEditDiff.Session(pasted: sentence)
        XCTAssertEqual(s.ingest(read("Ask the rover to water it twice", focused: false), elapsedMs: 500), .focusLeft)
        XCTAssertEqual(s.result().outcome, .edited)
        XCTAssertEqual(s.result().changes, [swapChange()])
    }

    func testSessionUnchanged() {
        var s = PostEditDiff.Session(pasted: sentence)
        XCTAssertNil(s.ingest(read("Ask the robot to water it twice"), elapsedMs: 500))
        let r = s.result()
        XCTAssertEqual(r.outcome, .unchanged)
        XCTAssertNil(r.changes)
        XCTAssertEqual(r.wordEdits, 0)
    }

    // MARK: record flags and privacy

    private func finalizedRecord(_ s: PostEditDiff.Session) -> PostEditDiff.Record {
        let base = PostEditDiff.Record(
            ts: "t", paste_ts: "t", dictation_ts: nil, dictation_emission: nil, bundle_id: "com.example.notes",
            mode: "plain", pasted_words: 7, outcome: .unchanged, reason: nil, located_at_paste: true,
            match_kind: .exact, end: "paste", polls: 0, located_polls: 0, observed_ms: nil, last_located_ms: nil,
            ax_ms_max: 0.4, role: "AXTextArea", subrole: nil, field_utf16: 30, secure_input_enabled: false,
            changes: nil, changes_truncated: nil, word_edits: 0, observable_edit: false)
        return base.finalized(result: s.result(), end: .focusLeft, polls: s.polls, locatedPolls: s.locatedPolls,
                              observedMs: 1500, lastLocatedMs: 1000, axMsMax: 0.9, ts: "t2")
    }

    func testRecordFlags() {
        var punct = PostEditDiff.Session(pasted: sentence)
        _ = punct.ingest(read("Ask the robot to water it twice."), elapsedMs: 500)
        let p = finalizedRecord(punct)
        XCTAssertEqual(p.outcome, .edited)
        XCTAssertTrue(p.observable_edit)
        XCTAssertEqual(p.word_edits, 0)
        XCTAssertEqual(p.end, "focus_left")
        var word = PostEditDiff.Session(pasted: sentence)
        _ = word.ingest(read("Ask the rover to water it twice"), elapsedMs: 500)
        XCTAssertEqual(finalizedRecord(word).word_edits, 1)
        var same = PostEditDiff.Session(pasted: sentence)
        _ = same.ingest(read("Ask the robot to water it twice"), elapsedMs: 500)
        let u = finalizedRecord(same)
        XCTAssertFalse(u.observable_edit)
        XCTAssertNil(u.changes)
    }

    func testPrivacySentinelFieldTextOutsideTheSpanNeverReachesTheRecord() throws {
        let field = "ZEBRAQUARTZ said hello. Ask the rover to water it twice"
        let tokens = toks(field)
        let range = try XCTUnwrap(PostEditDiff.relocate(pasted: sentence, fieldTokens: tokens, caretUTF16: nil))
        let d = PostEditDiff.diff(pasted: sentence, current: tokens[range].map(\.text))
        var s = PostEditDiff.Session(pasted: sentence)
        _ = s.ingest(.read(tokens: tokens, caretUTF16: nil, stillFocused: true), elapsedMs: 500)
        let line = String(decoding: try XCTUnwrap(PostEditDiff.encodeLine(finalizedRecord(s))), as: UTF8.self)
        XCTAssertEqual(d.changes, [swapChange()])
        XCTAssertTrue(line.contains("rover"))
        for leaked in ["ZEBRAQUARTZ", "said", "hello"] { XCTAssertFalse(line.contains(leaked), leaked) }
    }
}
#endif
