import XCTest
@testable import Dicticus

/// Quick 261101-sao: plain-hotkey trailing period (spike 023 rule T).
/// Not named `TextProcessingService*Tests`: see the header of
/// `TextProcessingServiceContextTests` for the cross-platform name collision.
@MainActor
final class TrailingPeriodTests: XCTestCase {

    var testHistory: HistoryService!

    override func setUp() {
        super.setUp()
        DictionaryService.shared.removeAll()
        let historyContainer = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("TrailingPeriodTests-\(UUID().uuidString)", isDirectory: true)
        testHistory = HistoryService.makeForTesting(containerURLProvider: { historyContainer })
    }

    override func tearDown() {
        testHistory = nil
        super.tearDown()
    }

    private func append(_ text: String) -> String {
        TextProcessingService.appendTrailingPeriod(text)
    }

    func testLetterEndGetsPeriod() {
        XCTAssertEqual(append("the sky is blue"), "the sky is blue.")
    }

    func testDigitEndGetsPeriod() {
        XCTAssertEqual(append("we need 3"), "we need 3.")
    }

    func testGermanTextGetsPeriod() {
        XCTAssertEqual(append("Das ist ein guter Plan"), "Das ist ein guter Plan.")
    }

    func testAlreadyTerminatedOrMarkedTextIsUnchanged() {
        let cases = [
            "Done.", "Really?", "Stop!", "a list:", "first, second;", "one,",
            "(see notes)", "[see notes]", "ends with a quote\"", "well\u{2026}", "great \u{1F44D}",
        ]
        for input in cases {
            XCTAssertEqual(append(input), input, "must be unchanged: \(input)")
        }
    }

    func testIdentifierEndIsUnchanged() {
        let cases = [
            "rename it to editGuard", "set max_tokens", "open main.swift",
            "run it with --verbose", "costs 3.5",
        ]
        for input in cases {
            XCTAssertEqual(append(input), input, "must be unchanged: \(input)")
        }
    }

    func testTrailingNewlineIsUnchanged() {
        XCTAssertEqual(append("first line\n"), "first line\n")
        XCTAssertEqual(append("first line \n"), "first line \n")
        XCTAssertEqual(append("first line\n\n"), "first line\n\n")
    }

    func testTrailingSpacesStayAfterThePeriod() {
        XCTAssertEqual(append("the sky is blue  "), "the sky is blue.  ")
        XCTAssertEqual(append("the sky is blue "), "the sky is blue. ")
    }

    func testEmptyAndWhitespaceOnlyAreUnchanged() {
        XCTAssertEqual(append(""), "")
        XCTAssertEqual(append("   "), "   ")
    }

    func testPlainModeAppendsTrailingPeriod() async {
        let service = TextProcessingService(cleanupService: nil, historyService: testHistory)
        let result = await service.process(text: "the sky is blue", language: "en", mode: .plain)
        XCTAssertEqual(result, "The sky is blue.")
    }

    func testAiCleanupModeDoesNotAppendPeriod() async {
        let mock = TextProcessingServiceContextTests.MockCleanupProvider()
        mock.returnValue = "the sky is blue"
        let service = TextProcessingService(cleanupService: mock, historyService: testHistory)
        let result = await service.process(text: "the sky is blue", language: "en", mode: .aiCleanup)
        XCTAssertFalse(result.hasSuffix("."), "AI cleanup output must not gain a trailing period")
        XCTAssertEqual(result, "The sky is blue")
    }
}
