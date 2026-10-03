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
}
#endif
