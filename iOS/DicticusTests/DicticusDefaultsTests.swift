import XCTest
@testable import Dicticus

// Phase 36.3 Plan 01 — Wave 0 contract test (SC2: iOS)
// DicticusDefaults is created in Plan 02. This test will fail to compile until
// Plan 02 lands (intended RED state).
//
// SC2 contract: on iOS, DicticusDefaults.suite MUST be the group.com.dicticus suite.
// iOS keeps the app-group entitlement and all IPC channels through the group container
// — this behaviour is UNCHANGED by Phase 36.3.

@MainActor
final class DicticusDefaultsTests: XCTestCase {

    /// SC2: iOS must resolve storage to the group.com.dicticus suite (unchanged from today).
    /// The invariant is about the PRODUCTION path — under XCTest,
    /// DicticusTestBootstrap installs overrideForTesting (260724-9v8 isolation),
    /// so the assertion runs with the override temporarily removed.
    func testSuiteIsGroupSuiteOnIOS() {
        let restored = DicticusDefaults.overrideForTesting
        DicticusDefaults.overrideForTesting = nil
        defer { DicticusDefaults.overrideForTesting = restored }
        guard let groupSuite = UserDefaults(suiteName: "group.com.dicticus") else {
            XCTFail("group.com.dicticus suite must be accessible on iOS (app-group entitlement present)")
            return
        }
        // Both DicticusDefaults.suite and UserDefaults(suiteName:) backed by the same
        // persistent domain — verify they share the same domain identifier.
        XCTAssertTrue(
            DicticusDefaults.suite !== UserDefaults.standard,
            "iOS: DicticusDefaults.suite must NOT be UserDefaults.standard — iOS uses the group suite"
        )
        // Verify the resolved suite is the same persistent domain as "group.com.dicticus".
        // Write a marker through one and read it through the other to confirm identity.
        let testKey = "com.dicticus.test.suiteIdentityCheck"
        let testValue = UUID().uuidString
        groupSuite.set(testValue, forKey: testKey)
        groupSuite.synchronize()
        let readBack = DicticusDefaults.suite.string(forKey: testKey)
        groupSuite.removeObject(forKey: testKey)
        XCTAssertEqual(
            readBack, testValue,
            "iOS: DicticusDefaults.suite must read from the same domain as UserDefaults(suiteName: 'group.com.dicticus')"
        )
    }
}
