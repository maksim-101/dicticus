import Foundation
@testable import Dicticus

/// `NSPrincipalClass` for both DicticusTests bundles (macOS + iOS), wired via
/// `project.yml`'s `info.properties.NSPrincipalClass`. Xcode instantiates the
/// principal class before any `XCTestCase` runs, which lets this constructor
/// redirect `DicticusDefaults.suite` to an ephemeral `UserDefaults` store for the
/// entire test process — before any test's `setUp()` executes, and regardless of
/// which test class runs first.
///
/// 2026-07-24 incident: `DictionaryServiceTests.setUp()` calls
/// `DictionaryService.shared.removeAll()`, which persists through
/// `DicticusDefaults.suite`. When the CLI bundle-id override
/// (`PRODUCT_BUNDLE_IDENTIFIER=com.dicticus.app.xctest`) silently stopped
/// applying, that call wiped the REAL `com.dicticus.app` dictionary. This
/// bootstrap makes isolation a property of the test bundle's runtime, not of
/// any individual test class's `setUp()` discipline or a CLI flag that can
/// silently stop applying.
final class DicticusTestBootstrap: NSObject {
    /// Asserted by `TestIsolationCanaryTests.testBootstrapRan` — true only if
    /// this principal class was actually instantiated before the test run.
    /// `nonisolated(unsafe)`: written once from `init()` (runs before any
    /// Swift-concurrency context is established, as the NSPrincipalClass hook),
    /// read from `@MainActor` test methods afterward — no concurrent access.
    nonisolated(unsafe) static var didBootstrap = false

    private static let ephemeralSuiteName = "com.dicticus.tests.ephemeral"

    override init() {
        super.init()
        // Clean slate every run — any leak from a prior run is confined to this
        // one throwaway plist and never accumulates across invocations.
        UserDefaults.standard.removePersistentDomain(forName: Self.ephemeralSuiteName)
        guard let ephemeral = UserDefaults(suiteName: Self.ephemeralSuiteName) else {
            fatalError("DicticusTestBootstrap: failed to create the ephemeral UserDefaults suite — tests cannot be guaranteed isolated from the real user domain, so refusing to proceed.")
        }
        DicticusDefaults.overrideForTesting = ephemeral
        Self.didBootstrap = true
    }
}
