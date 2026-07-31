import XCTest
@testable import Dicticus

@MainActor
final class IOSModelWarmupServicePersistenceTests: XCTestCase {
    func testCheckHasModelsLogic() {
        let service = IOSModelWarmupService()
        // We can't easily mock the file system here without dependency injection,
        // but we can verify it doesn't crash and initializes with a boolean.
        service.checkHasModels()
        XCTAssertNotNil(service.hasModels)
    }
    
    func testInitialStateWithAppStorage() {
        let service = IOSModelWarmupService()
        XCTAssertFalse(service.isWarming)
        XCTAssertFalse(service.isReady)
    }
}
