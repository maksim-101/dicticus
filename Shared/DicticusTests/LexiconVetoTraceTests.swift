import XCTest
@testable import Dicticus

/// Quick task 260930-s1e (audit 2026-09-30 A §5): Guard A's real-word veto used to
/// leave no trace, so a suppressed near-match vanished from the debug log. It is now
/// reported in `applyWithTrace(...).vetoed` and, in recorder builds, `lexicon_vetoed`.
/// `blocked` keeps its ratio-cap-only meaning.
@MainActor
final class LexiconVetoTraceTests: XCTestCase {

    var dictionaryService: DictionaryService!
    var testHistory: HistoryService!

    override func setUp() {
        super.setUp()
        dictionaryService = DictionaryService.shared
        dictionaryService.removeAll()
        let historyContainer = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("LVTTests-\(UUID().uuidString)", isDirectory: true)
        testHistory = HistoryService.makeForTesting(containerURLProvider: { historyContainer })
    }

    override func tearDown() {
        dictionaryService.removeAll()
        dictionaryService = nil
        testHistory = nil
        super.tearDown()
    }

    private func makeDict(_ pairs: [(String, String)]) {
        for (key, replacement) in pairs {
            dictionaryService.setReplacement(for: key, with: replacement)
        }
    }

    func testSafeguardVetoIsTraced() {
        makeDict([("SalGuard", "Cellguard")])
        let input = "I checked this safeguard today."
        let trace = dictionaryService.applyWithTrace(to: input)
        XCTAssertEqual(trace.text, input)
        XCTAssertEqual(trace.replacements.count, 0)
        XCTAssertEqual(trace.blocked.count, 0)
        XCTAssertEqual(trace.vetoed.count, 1)
        XCTAssertEqual(trace.vetoed.first?.key, "SalGuard")
        XCTAssertEqual(trace.vetoed.first?.from, "safeguard")
        XCTAssertEqual(trace.vetoed.first?.to, "Cellguard")
        XCTAssertEqual(trace.vetoed.first?.ratio ?? -1, 2.0 / 9.0, accuracy: 0.001)
    }

    func testSafeguardVetoReachesDebugRecord() async {
        makeDict([("SalGuard", "Cellguard")])
        let matcher = BrandMatcher(canonicals: [], enLexicon: [], deLexicon: [])
        let service = TextProcessingService(
            dictionaryService: dictionaryService,
            cleanupService: nil,
            historyService: testHistory,
            brandMatcher: matcher
        )
        matcher.liveDictionaryCanonicalProvider = nil

        let input = "I checked this safeguard today."
        let output = await service.process(text: input, language: "en", mode: .plain)
        XCTAssertEqual(output, input)

        #if DEBUG_RECORDER
        try? await Task.sleep(nanoseconds: 150_000_000)
        let record = await DebugRecorder.shared.lastRecordForTests
        XCTAssertEqual(record?.lexicon_vetoed?.count, 1)
        XCTAssertEqual(record?.lexicon_vetoed?.first?.key, "SalGuard")
        XCTAssertEqual(record?.lexicon_vetoed?.first?.from, "safeguard")
        XCTAssertEqual(record?.lexicon_vetoed?.first?.to, "Cellguard")
        XCTAssertEqual(record?.lexicon_vetoed?.first?.ratio ?? -1, 0.222, accuracy: 0.001)
        #endif
    }
}
