import XCTest
@testable import Dicticus

/// A never-stored `useSwissGerman` setting means ON in the pipeline, as it does on both
/// settings screens. The migrated flag is set in setUp so the one-shot `SwissDefaultMigration`
/// cannot be what supplies the key. Every fixture is invented.
@MainActor
final class SwissGermanDefaultTests: XCTestCase {

    private static let suiteName = "com.dicticus.tests.swissdefault"

    private var savedOverride: UserDefaults?
    private var testHistory: HistoryService!
    private var service: TextProcessingService!

    override func setUp() {
        super.setUp()
        savedOverride = DicticusDefaults.overrideForTesting
        let suite = UserDefaults(suiteName: Self.suiteName)!
        suite.removePersistentDomain(forName: Self.suiteName)
        DicticusDefaults.overrideForTesting = suite
        suite.set(true, forKey: SwissDefaultMigration.migratedKey)
        DictionaryService.shared.removeAll()
        let historyContainer = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("SGDTests-\(UUID().uuidString)", isDirectory: true)
        testHistory = HistoryService.makeForTesting(containerURLProvider: { historyContainer })
        service = TextProcessingService(
            dictionaryService: DictionaryService.shared,
            cleanupService: EditGuardPipelineTests.PipelineMockCleanupProvider(),
            historyService: testHistory
        )
    }

    override func tearDown() {
        DicticusDefaults.suite.removePersistentDomain(forName: Self.suiteName)
        DicticusDefaults.overrideForTesting = savedOverride
        service = nil
        testHistory = nil
        super.tearDown()
    }

    func testEszettBecomesSsWhenSettingNeverStored() async {
        XCTAssertNil(DicticusDefaults.suite.object(forKey: SwissDefaultMigration.toggleKey))
        let output = await service.process(text: "Die Straße ist groß", language: "de", mode: .plain)
        XCTAssertFalse(output.contains("ß"), output)
        XCTAssertTrue(output.contains("Strasse"), output)
        XCTAssertTrue(output.contains("gross"), output)
    }

    func testCommaDecimalBecomesPointWhenSettingNeverStored() async {
        XCTAssertNil(DicticusDefaults.suite.object(forKey: SwissDefaultMigration.toggleKey))
        let output = await service.process(text: "Es sind 2,5 Kilometer", language: "de", mode: .plain)
        XCTAssertTrue(output.contains("2.5"), output)
        XCTAssertFalse(output.contains("2,5"), output)
    }

    func testEszettStaysWhenSettingStoredAsOff() async {
        DicticusDefaults.suite.set(false, forKey: SwissDefaultMigration.toggleKey)
        let output = await service.process(text: "Die Straße ist groß", language: "de", mode: .plain)
        XCTAssertTrue(output.contains("Straße"), output)
    }
}
