import XCTest
@testable import Dicticus

// Phase 51 D-14: the live-transcript toggle defaults ON and is stored only
// through DicticusDefaults.suite (redirected to an ephemeral store under test).
@MainActor
final class LiveOverlayDefaultsTests: XCTestCase {

    private let key = LivePreviewSession.enabledKey

    override func setUp() {
        super.setUp()
        DicticusDefaults.suite.removeObject(forKey: key)
    }

    override func tearDown() {
        DicticusDefaults.suite.removeObject(forKey: key)
        super.tearDown()
    }

    func testAbsentKeyMeansEnabled() {
        XCTAssertNil(DicticusDefaults.suite.object(forKey: key))
        XCTAssertTrue(LivePreviewSession.isEnabled(DicticusDefaults.suite))
    }

    func testExplicitValuesAreRespected() {
        DicticusDefaults.suite.set(false, forKey: key)
        XCTAssertFalse(LivePreviewSession.isEnabled(DicticusDefaults.suite))
        DicticusDefaults.suite.set(true, forKey: key)
        XCTAssertTrue(LivePreviewSession.isEnabled(DicticusDefaults.suite))
    }

    func testSuiteIsRedirectedDuringTests() {
        XCTAssertFalse(DicticusDefaults.suite === UserDefaults.standard)
    }

    func testWritesNeverReachStandardDomain() {
        let before = UserDefaults.standard.object(forKey: key) as? Bool
        DicticusDefaults.suite.set(before == false ? true : false, forKey: key)
        XCTAssertEqual(UserDefaults.standard.object(forKey: key) as? Bool, before)
    }
}
