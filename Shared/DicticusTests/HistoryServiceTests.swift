import XCTest
@testable import Dicticus

/// Lives in Shared/DicticusTests, so it runs in both the macOS and iOS test bundles.
@MainActor
final class HistoryServiceTests: XCTestCase {
    
    var service: HistoryService!
    private var tempContainer: URL!

    override func setUp() {
        super.setUp()
        // CRITICAL: isolate from the real App Group database. Using HistoryService.shared
        // here ran clearAll() against the user's live history and wiped it on every test
        // run. makeForTesting + a unique temp container keeps tests fully isolated.
        let container = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("HistoryServiceTests-\(UUID().uuidString)", isDirectory: true)
        tempContainer = container
        service = HistoryService.makeForTesting(containerURLProvider: { container })
        service.clearAll()
    }

    override func tearDown() {
        service = nil
        if let tempContainer { try? FileManager.default.removeItem(at: tempContainer) }
        tempContainer = nil
        super.tearDown()
    }
    
    func testSaveAndFetch() {
        let entry = TranscriptionEntry(
            text: "Hello testing history",
            rawText: "hello testing history",
            language: "en",
            mode: "plain",
            confidence: 0.95
        )
        
        service.save(entry)
        XCTAssertEqual(service.entries.count, 1)
        XCTAssertEqual(service.entries.first?.text, "Hello testing history")
    }
    
    func testSearchFTS5() {
        let entry1 = TranscriptionEntry(text: "The quick brown fox", rawText: "the quick brown fox", language: "en", mode: "plain", confidence: 1.0)
        let entry2 = TranscriptionEntry(text: "Jumped over the lazy dog", rawText: "jumped over the lazy dog", language: "en", mode: "plain", confidence: 1.0)
        
        service.save(entry1)
        service.save(entry2)
        
        // Search for 'fox'
        service.load(query: "fox")
        XCTAssertEqual(service.entries.count, 1)
        XCTAssertEqual(service.entries.first?.text, "The quick brown fox")
        
        // Search for 'jumped'
        service.load(query: "jumped")
        XCTAssertEqual(service.entries.count, 1)
        XCTAssertEqual(service.entries.first?.text, "Jumped over the lazy dog")
        
        // Search for something non-existent
        service.load(query: "cat")
        XCTAssertEqual(service.entries.count, 0)
    }
    
    func testDelete() {
        let entry = TranscriptionEntry(text: "Delete me", rawText: "delete me", language: "en", mode: "plain", confidence: 1.0)
        service.save(entry)
        XCTAssertEqual(service.entries.count, 1)
        
        if let id = service.entries.first?.id {
            service.delete(id: id)
            XCTAssertEqual(service.entries.count, 0)
        } else {
            XCTFail("Entry should have a database ID after saving")
        }
    }
    
    func testClearAll() {
        service.save(TranscriptionEntry(text: "1", rawText: "1", language: "en", mode: "plain", confidence: 1.0))
        service.save(TranscriptionEntry(text: "2", rawText: "2", language: "en", mode: "plain", confidence: 1.0))
        XCTAssertEqual(service.entries.count, 2)
        
        service.clearAll()
        XCTAssertEqual(service.entries.count, 0)
    }

#if os(iOS)
    // iOS only: macOS keeps history in app-local storage (HistoryService.resolveStorage), so it has no App Group fallback, and only iOS Settings reads appGroupAvailable.

    /// In a normally-provisioned simulator/test bundle the App Group
    /// container is available and `appGroupAvailable` reports `true`.
    /// In CI environments without provisioning, skip — the fallback path
    /// is exercised by `testFallbackFlagSettableForUI` which does not
    /// depend on the entitlement.
    func testAppGroupAvailableFlagDefaultsTrue() throws {
        let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.dicticus"
        )
        try XCTSkipIf(containerURL == nil,
            "CI environment without App Group provisioning — fallback path covered by testFallbackFlagSettableForUI")
        // Touch the singleton so its init runs and sets the flag.
        _ = HistoryService.shared
        XCTAssertTrue(HistoryService.appGroupAvailable,
            "When App Group container is provisioned, appGroupAvailable must report true")
    }

    /// Inject a provider that returns `nil` to simulate App Group absence.
    /// The resulting instance MUST:
    ///   1. Construct successfully (no fatalError) — the resilience contract.
    ///   2. Report `appGroupAvailable == false` — the visibility flag.
    ///   3. Place its SQLite file under `applicationSupportDirectory`
    ///      (the documented fallback location).
    ///
    /// This is the primary contract test for ACT-4-RESILIENCE. Without
    /// the injectable factory there is no deterministic way to exercise
    /// the fallback path in a unit test.
    func testFallbackFlagSettableForUI() throws {
        let service = HistoryService.makeForTesting(containerURLProvider: { nil })

        // 2. Visibility flag flipped.
        XCTAssertFalse(HistoryService.appGroupAvailable,
            "When containerURL provider returns nil, appGroupAvailable must report false (fallback path active)")

        // 3. Fallback storage path lives under applicationSupportDirectory.
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        let dbURL = service.databaseFileURL  // Plan 20.04 must expose this for the assertion.
        XCTAssertTrue(
            dbURL.path.hasPrefix(appSupport.path),
            "Fallback DB path must live under applicationSupportDirectory. Got: \(dbURL.path), expected prefix: \(appSupport.path)"
        )
    }
#endif
}
