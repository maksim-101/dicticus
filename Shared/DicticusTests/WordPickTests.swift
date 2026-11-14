import XCTest
@testable import Dicticus

/// Slice 52: the text a click or shift-click pick in History's Raw view yields.
final class WordPickTests: XCTestCase {

    private let tokens = WordPick.tokens(of: "can you check whether kwib ly imports the file, from \"flor-dex\" correctly?")

    func testTokensSplitOnAnyWhitespace() {
        XCTAssertEqual(WordPick.tokens(of: " a  b\nc\t"), ["a", "b", "c"])
        XCTAssertEqual(WordPick.tokens(of: ""), [])
    }

    func testSingleWord() {
        XCTAssertEqual(WordPick.text(of: tokens, from: 4, to: 4), "kwib")
    }

    func testShiftExtendedRunInEitherOrder() {
        XCTAssertEqual(WordPick.text(of: tokens, from: 4, to: 5), "kwib ly")
        XCTAssertEqual(WordPick.text(of: tokens, from: 5, to: 4), "kwib ly")
    }

    func testEndPunctuationTrimmedInnerKept() {
        XCTAssertEqual(WordPick.text(of: tokens, from: 8, to: 8), "file")
        XCTAssertEqual(WordPick.text(of: tokens, from: 10, to: 10), "flor-dex")
        XCTAssertEqual(WordPick.text(of: tokens, from: 8, to: 11), "file, from \"flor-dex\" correctly")
    }

    func testGermanUmlautsAndOutOfRange() {
        let de = WordPick.tokens(of: "Öffne die Grüße-Datei.")
        XCTAssertEqual(WordPick.text(of: de, from: 0, to: 0), "Öffne")
        XCTAssertEqual(WordPick.text(of: de, from: 2, to: 2), "Grüße-Datei")
        XCTAssertEqual(WordPick.text(of: de, from: 1, to: 99), "die Grüße-Datei")
        XCTAssertEqual(WordPick.text(of: [], from: 0, to: 0), "")
        XCTAssertEqual(WordPick.text(of: ["…"], from: 0, to: 0), "")
    }
}
