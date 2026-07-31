import XCTest
import GRDB
@testable import Dicticus

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
}
