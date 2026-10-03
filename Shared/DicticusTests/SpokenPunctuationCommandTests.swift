import XCTest
@testable import Dicticus

/// Quick task 261003-p7e: spoken punctuation commands (brackets, ellipsis, ? ! ; and
/// line breaks). Unit tests on `ITNUtility.applySpokenPunctuationCommands(to:)`, plus
/// pipeline tests through `TextProcessingService.process`. Every fixture is invented.
///
/// Tests whose names end in `_RED` fail on the stub and pass once the pass is wired in.
///
/// Compiled into both the macOS and the iOS test target.
@MainActor
final class SpokenPunctuationCommandTests: XCTestCase {

    final class MockProvider: CleanupProvider {
        var isLoaded: Bool = true
        var returnValue: String = ""
        var echo: Bool = false
        var trimLineBreaks: Bool = false

        func cleanup(text: String, language: String, dictionaryContext: [String: String]?, context: DictationContext = .default) async -> String {
            if trimLineBreaks { return text.trimmingCharacters(in: .newlines) }
            return echo ? text : returnValue
        }
    }

    var dictionaryService: DictionaryService!
    var testHistory: HistoryService!
    var savedUseSwissGerman: Bool = false

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: DictionaryService.dictionaryKey)
        dictionaryService = DictionaryService.shared
        dictionaryService.removeAll()
        let historyContainer = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("SPCTests-\(UUID().uuidString)", isDirectory: true)
        testHistory = HistoryService.makeForTesting(containerURLProvider: { historyContainer })
        savedUseSwissGerman = DicticusDefaults.suite.bool(forKey: "useSwissGerman")
        DicticusDefaults.suite.set(false, forKey: "useSwissGerman")
    }

    override func tearDown() {
        DicticusDefaults.suite.set(savedUseSwissGerman, forKey: "useSwissGerman")
        testHistory = nil
        super.tearDown()
    }

    private func f(_ s: String) -> String { ITNUtility.applySpokenPunctuationCommands(to: s) }

    private func expect(_ pairs: [(String, String)], file: StaticString = #filePath, line: UInt = #line) {
        for (input, expected) in pairs {
            XCTAssertEqual(f(input), expected, "input: \(input)", file: file, line: line)
        }
    }

    private func service(_ provider: MockProvider) -> TextProcessingService {
        TextProcessingService(dictionaryService: dictionaryService, cleanupService: provider, historyService: testHistory)
    }

    // MARK: - Positives

    static let positives: [(String, String)] = [
        ("The patch is out, parentheses open, build 4a1b2c3, parentheses closed, and tested", "The patch is out (build 4a1b2c3) and tested"),
        ("open parenthesis optional close parenthesis", "(optional)"),
        ("Parenthesis open draft paren closed", "(draft)"),
        ("open parenthesis this or that close parenthesis", "(this or that)"),
        ("Das gilt Klammer auf vorläufig Klammer zu für alle", "Das gilt (vorläufig) für alle"),
        ("runde Klammer auf eins runde Klammer zu", "(eins)"),
        ("The list, open square bracket, draft, close square bracket, is ready", "The list [draft] is ready"),
        ("Status eckige Klammer auf offen eckige Klammer zu", "Status [offen]"),
        ("it stopped there dot dot dot not sure why", "it stopped there... not sure why"),
        ("the log shows one item, two item, dot, dot, dot.", "the log shows one item, two item..."),
        ("Ich weiss nicht, Punkt, Punkt, Punkt, vielleicht morgen", "Ich weiss nicht... vielleicht morgen"),
        ("Are you coming question mark", "Are you coming?"),
        ("Are you coming, question mark.", "Are you coming?"),
        ("Are you coming? Question mark.", "Are you coming?"),
        ("Is it ready question mark . Then we go", "Is it ready? Then we go"),
        ("Kommst du morgen Fragezeichen", "Kommst du morgen?"),
        ("That works exclamation mark", "That works!"),
        ("That works exclamation point", "That works!"),
        ("Das ist super, Ausrufezeichen.", "Das ist super!"),
        ("Das ist super Ausrufzeichen", "Das ist super!"),
        ("Dear team, new line, the garden plan is ready", "Dear team,\nthe garden plan is ready"),
        ("First point new line new line second point", "First point\n\nsecond point"),
        ("Thanks. New line. Best wishes", "Thanks.\nBest wishes"),
        ("Best wishes newline", "Best wishes\n"),
        ("Hallo zusammen neue Zeile danke für alles", "Hallo zusammen\ndanke für alles"),
        ("Danke Zeilenumbruch", "Danke\n"),
        ("Really question mark new line Next topic", "Really?\nNext topic"),
        ("Parentheses open see the notes. Parentheses closed. Next item", "(see the notes). Next item"),
        ("x semicolon y", "x; y"),
        ("first part, semicolon, second part", "first part; second part"),
        ("The patch is out, parentheses open, build 4a1b2c3, parentheses closed, semicolon, then tests follow", "The patch is out (build 4a1b2c3); then tests follow"),
    ]

    func testBracketPositives_RED() {
        expect(Array(Self.positives[0..<8]))
    }

    func testEllipsisPositives_RED() {
        expect(Array(Self.positives[8..<11]))
    }

    func testQuestionAndExclamationPositives_RED() {
        expect(Array(Self.positives[11..<20]))
    }

    func testLineBreakPositives_RED() {
        expect(Array(Self.positives[20..<26]))
    }

    func testCombinedPositives_RED() {
        expect(Array(Self.positives[26..<28]))
    }

    func testSemicolonPositives_RED() {
        expect(Array(Self.positives[28..<31]))
    }

    /// One ASR comma between the two words of a bracket command ("parentheses, open").
    static let innerCommaPositives: [(String, String)] = [
        ("This works, parentheses, open, mostly parentheses, closed, semicolon, the rest, question mark, new line, next line.",
         "This works (mostly); the rest?\nnext line."),
        ("Ship it, parenthesis, open, see notes, parenthesis, close, now", "Ship it (see notes) now"),
        ("Ship it, open, parenthesis, see notes, closing, parenthesis, now", "Ship it (see notes) now"),
        ("The list, square brackets, open, draft, square brackets, close, is ready", "The list [draft] is ready"),
        ("Das gilt Klammer, auf vorläufig Klammer, zu für alle", "Das gilt (vorläufig) für alle"),
        ("Status eckige Klammer, auf offen eckige Klammer, zu", "Status [offen]"),
    ]

    func testBracketInnerCommaPositives_RED() {
        expect(Self.innerCommaPositives)
    }

    // MARK: - Negatives (byte-identical before and after)

    func testSemicolonNegatives() {
        let inputs = [
            "the semicolon key sticks",
            "a semicolon would fit here",
            "names like comma or semicolon or colon",
            "use semicolons sparingly",
        ]
        for s in inputs { XCTAssertEqual(f(s), s) }
    }

    func testCorpusShapedNegatives() {
        let inputs = [
            "the sign carries an exclamation mark beside the arrow",
            "perhaps a new line under the heading helps",
            "count the digit plus the question mark. Then stop",
            "spoken names like parenthesis open or parenthesis closed and dot dot dot stayed words",
            "please list question mark, exclamation point, or new line here.",
            "das sorgt für ein bisschen Fragezeichen bei mir",
        ]
        for s in inputs { XCTAssertEqual(f(s), s) }
    }

    func testAdversarialNegatives() {
        let inputs = [
            "they sell a new line of garden chairs",
            "she runs the new line team",
            "we print new line of text",
            "a big question mark hangs over the budget",
            "she wrote a question mark next to it",
            "bitte eine neue Zeile in der Tabelle",
            "die Klammer auf dem Tisch",
            "ein grosses Fragezeichen hinter dem Plan",
            "mit Ausrufezeichen am Ende",
            "put them in square brackets",
            "in parentheses I would say",
            "the bracket open toward the wall",
        ]
        for s in inputs { XCTAssertEqual(f(s), s) }
    }

    func testBracketInnerCommaNegatives() {
        let inputs = [
            "the parentheses, open questions remain",
            "in square brackets, open items are marked",
            "Die Klammer, auf die du zeigst, ist falsch",
            "wegen der Klammer, zu der es keine Regel gibt",
            "note parentheses. Open items follow",
            "see parentheses; open the file",
        ]
        for s in inputs { XCTAssertEqual(f(s), s) }
    }

    func testNoPhraseTextIsByteIdentical() {
        let s = "plain  text\twith   odd gaps\nand a second line  "
        XCTAssertEqual(f(s), s)
    }

    func testIdempotentOnPositives() {
        for (input, _) in Self.positives + Self.innerCommaPositives {
            let once = f(input)
            XCTAssertEqual(f(once), once, "input: \(input)")
        }
    }

    // MARK: - Pipeline

    func testPipelinePlainLineBreak_RED() async {
        let mock = MockProvider()
        let out = await service(mock).process(text: "Dear team new line the garden plan is ready", language: "en", mode: .plain)
        XCTAssertEqual(out, "Dear team\nthe garden plan is ready")
    }

    func testPipelinePlainQuestionMark_RED() async {
        let mock = MockProvider()
        let out = await service(mock).process(text: "Are you coming question mark. yes we are", language: "en", mode: .plain)
        XCTAssertEqual(out, "Are you coming? Yes we are")
    }

    func testPipelinePlainSemicolon_RED() async {
        let mock = MockProvider()
        let out = await service(mock).process(text: "first part semicolon second part", language: "en", mode: .plain)
        XCTAssertEqual(out, "First part; second part")
    }

    func testPipelineAiEchoKeepsOneLineBreak_RED() async {
        let mock = MockProvider()
        mock.echo = true
        let out = await service(mock).process(text: "Dear team new line the garden plan is ready", language: "en", mode: .aiCleanup)
        XCTAssertEqual(out.components(separatedBy: "\n").count - 1, 1, "output: \(out)")
    }

    func testPipelineAiKeepsTrailingLineBreak_RED() async {
        let mock = MockProvider()
        mock.trimLineBreaks = true
        let out = await service(mock).process(text: "Best wishes new line", language: "en", mode: .aiCleanup)
        XCTAssertTrue(out.hasSuffix("\n"), "output: \(out.debugDescription)")
    }

    func testPipelineAiKeepsDictatedBrackets_RED() async {
        let mock = MockProvider()
        mock.returnValue = "The patch is out (build 4a1b2c3) and tested."
        let out = await service(mock).process(
            text: "The patch is out parentheses open build 4a1b2c3 parentheses closed and tested", language: "en", mode: .aiCleanup)
        XCTAssertTrue(out.contains("(build 4a1b2c3)"), "output: \(out)")
    }

    func testPipelineAiEditToAsrMarkIsNotAFallback_RED() async {
        let mock = MockProvider()
        mock.returnValue = "Is the patch out. (build 4a1b2c3) and tested."
        let out = await service(mock).process(
            text: "is the patch out? parentheses open build 4a1b2c3 parentheses closed and tested", language: "en", mode: .aiCleanup)
        XCTAssertTrue(out.contains("(build 4a1b2c3)"), "output: \(out)")
        XCTAssertTrue(out.hasSuffix("tested."), "output: \(out)")
    }

    func testPipelineAiDroppedLineBreakFallsBack_RED() async {
        let mock = MockProvider()
        mock.returnValue = "Dear team, the garden plan is ready."
        let out = await service(mock).process(text: "Dear team new line the garden plan is ready", language: "en", mode: .aiCleanup)
        XCTAssertTrue(out.contains("\n"), "output: \(out.debugDescription)")
    }

    func testPipelineAiDroppedBracketsFallBack_RED() async {
        let mock = MockProvider()
        mock.returnValue = "The patch is out, build 4a1b2c3, and tested."
        let out = await service(mock).process(
            text: "The patch is out parentheses open build 4a1b2c3 parentheses closed and tested", language: "en", mode: .aiCleanup)
        XCTAssertTrue(out.contains("(") && out.contains(")"), "output: \(out)")
    }

    // MARK: - dictatedMarkShortfall

    func testShortfallIgnoresKindsThePassDidNotAdd() {
        XCTAssertEqual(
            TextProcessingService.dictatedMarkShortfall(thresholds: ["(": 1, ")": 1], rulesCleaned: "a (b) c?", output: "A (b) c."), [])
    }

    func testShortfallLostBrackets_RED() {
        XCTAssertEqual(
            TextProcessingService.dictatedMarkShortfall(thresholds: ["(": 1, ")": 1], rulesCleaned: "a (b) c", output: "A, b, c."), ["(", ")"])
    }

    func testShortfallQuestionMarkBothDictatedAndAsr_RED() {
        XCTAssertEqual(
            TextProcessingService.dictatedMarkShortfall(thresholds: ["?": 2], rulesCleaned: "ok? fine?", output: "Ok. Fine?"), ["?"])
    }

    func testShortfallCappedAtRulesCleanedCount() {
        XCTAssertEqual(
            TextProcessingService.dictatedMarkShortfall(thresholds: ["(": 2], rulesCleaned: "x (y", output: "X (y."), [])
    }

    func testShortfallLineBreak_RED() {
        XCTAssertEqual(
            TextProcessingService.dictatedMarkShortfall(thresholds: ["\n": 1], rulesCleaned: "a\nb", output: "A b."), ["\n"])
    }

    // MARK: - RulesCleanupService whitespace collapse

    func testRulesCleanKeepsLineBreak_RED() {
        XCTAssertEqual(RulesCleanupService().clean("first part\nsecond  part", language: "en"), "first part\nsecond part")
    }

    func testRulesCleanStillCollapsesSpaces() {
        XCTAssertEqual(RulesCleanupService().clean("one  two", language: "en"), "one two")
    }
}
