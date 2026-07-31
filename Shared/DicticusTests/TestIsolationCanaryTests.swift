import XCTest
@testable import Dicticus

/// Guards the 2026-07-24 test-isolation fix (quick task 260724-9v8). These four
/// tests must ALL pass on every `xcodebuild test` invocation, including a plain
/// invocation with NO custom CLI settings — the isolation must be a property of
/// the build configuration and the test bundle's runtime, not of a CLI flag that
/// can silently stop applying (as happened on 2026-07-24).
///
/// If any of these fail, DO NOT run the rest of the suite — the real
/// `com.dicticus.app` / `group.com.dicticus` UserDefaults domain (and the user's
/// real dictionary data) may be reachable from the test process.
@MainActor
final class TestIsolationCanaryTests: XCTestCase {

    private static let ephemeralSuiteName = "com.dicticus.tests.ephemeral"

    /// The NSPrincipalClass hook must have run before this test executes.
    func testBootstrapRan() {
        XCTAssertTrue(
            DicticusTestBootstrap.didBootstrap,
            "Test bootstrap did not run — tests are NOT isolated from the real user domain. DO NOT run the suite until fixed."
        )
    }

    /// DicticusDefaults.suite must be routed through the ephemeral store, not
    /// through .standard (macOS) or the group.com.dicticus suite (iOS).
    func testSuiteIsEphemeral() {
        let sentinelKey = "9v8-canary-sentinel-\(UUID().uuidString)"
        DicticusDefaults.suite.set("canary", forKey: sentinelKey)
        defer { DicticusDefaults.suite.removeObject(forKey: sentinelKey) }

        let ephemeral = UserDefaults(suiteName: Self.ephemeralSuiteName)
        XCTAssertEqual(
            ephemeral?.string(forKey: sentinelKey),
            "canary",
            "DicticusDefaults.suite is not routing through the ephemeral test store."
        )
    }

    /// A sentinel written through the FULL DictionaryService.shared path (the
    /// exact path DictionaryServiceTests exercises — including removeAll()-style
    /// setUp() calls) must never reach the real UserDefaults/CFPreferences domain.
    func testRealDomainUnreachable() {
        let sentinel = "9v8-canary-\(UUID().uuidString)"
        DictionaryService.shared.setReplacement(for: sentinel, with: "should-never-reach-real-domain")
        defer { DictionaryService.shared.removeReplacement(for: sentinel) }

#if os(macOS)
        let raw = CFPreferencesCopyAppValue(
            DictionaryService.dictionaryKey as CFString,
            "com.dicticus.app" as CFString
        )
        let data = raw as? Data
#else
        let data = UserDefaults(suiteName: "group.com.dicticus")?.data(forKey: DictionaryService.dictionaryKey)
#endif
        guard let data,
              let decoded = try? JSONDecoder().decode([String: DictionaryMetadata].self, from: data) else {
            // No readable dictionary blob in the real domain at all — the
            // sentinel cannot possibly be in it.
            return
        }
        XCTAssertNil(
            decoded[sentinel],
            "Sentinel leaked into the REAL dictionary domain — test isolation is broken."
        )
    }

#if os(macOS)
    /// The unsigned test host must never claim the production bundle id — that
    /// is exactly the class of breakage that poisoned the user's TCC grants on
    /// 2026-07-24.
    func testHostIdentityIsNotProduction() {
        XCTAssertNotEqual(
            Bundle.main.bundleIdentifier,
            "com.dicticus.app",
            "Unsigned test host is claiming the production bundle id — this poisons the user's TCC grants (2026-07-24 incident)."
        )
    }
#endif
}
