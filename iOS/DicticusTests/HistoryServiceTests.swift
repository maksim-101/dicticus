import XCTest
@testable import Dicticus

/// HistoryService fallback tests (Phase 20.01 — Wave 0 RED).
///
/// References surface that does NOT exist yet — `HistoryService.appGroupAvailable`
/// and the injectable `HistoryService.makeForTesting(containerURLProvider:)`
/// factory both land in plan 20.04 (ACT-4-RESILIENCE). Today
/// `HistoryService.init()` calls `fatalError` when the App Group container
/// is missing; plan 20.04 swaps that for graceful fallback to
/// `applicationSupportDirectory` and exposes `appGroupAvailable: Bool`
/// for the visibility surface (plan 20.05).
///
/// Contract being locked:
///   ```
///   extension HistoryService {
///       static private(set) var appGroupAvailable: Bool
///       static func makeForTesting(containerURLProvider: () -> URL?) -> HistoryService
///   }
///   ```
/// The factory accepts a provider closure so the test can inject `nil`
/// (forcing the fallback path) without depending on entitlements.
@MainActor
final class HistoryServiceTests: XCTestCase {

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
}
