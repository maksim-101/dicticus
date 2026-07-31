import XCTest
@testable import Dicticus

// Phase 36.3 Plan 01 — Wave 0 contract test (SC2: macOS)
// DicticusDefaults is created in Plan 02. This test will fail to compile until
// Plan 02 lands (intended RED state).
//
// SC2 contract: on macOS, DicticusDefaults.suite MUST be === UserDefaults.standard.
// No app-group suite is involved — the macOS target drops the application-groups
// entitlement in Plan 04, so any group-suite access would start prompting TCC.

@MainActor
final class DicticusDefaultsTests: XCTestCase {

    /// SC2: macOS must resolve storage to UserDefaults.standard, not a group suite.
    /// The invariant is about the PRODUCTION path — under XCTest,
    /// DicticusTestBootstrap installs overrideForTesting (260724-9v8 isolation),
    /// so the assertion runs with the override temporarily removed.
    func testSuiteIsStandardOnMacOS() {
        let restored = DicticusDefaults.overrideForTesting
        DicticusDefaults.overrideForTesting = nil
        defer { DicticusDefaults.overrideForTesting = restored }
        XCTAssertTrue(
            DicticusDefaults.suite === UserDefaults.standard,
            "macOS: DicticusDefaults.suite must be === UserDefaults.standard — no app-group entitlement"
        )
    }
}
