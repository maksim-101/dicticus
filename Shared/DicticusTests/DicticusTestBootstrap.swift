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
///
/// 2026-10-31 (quick task 261031-nil): the `Dicticus-Debug-Recorder` scheme's test
/// host used to carry `com.dicticus.app`, so raw `UserDefaults.standard` writes in
/// tests hit the real domain and the DEBUG_RECORDER recorders appended fixture
/// lines to the real DebugRecordings corpus. That scheme now tests under the
/// `Debug-Recorder-Test` configuration (host `com.dicticus.app.xctest`); this
/// bootstrap additionally refuses to run in a `com.dicticus.app` host (a
/// `-configuration Debug-Recorder` flag overrides the scheme) and redirects the
/// recorders to a per-run temp directory.
final class DicticusTestBootstrap: NSObject {
    /// Asserted by `TestIsolationCanaryTests.testBootstrapRan` — true only if
    /// this principal class was actually instantiated before the test run.
    /// `nonisolated(unsafe)`: written once from `init()` (runs before any
    /// Swift-concurrency context is established, as the NSPrincipalClass hook),
    /// read from `@MainActor` test methods afterward — no concurrent access.
    nonisolated(unsafe) static var didBootstrap = false

    private static let ephemeralSuiteName = "com.dicticus.tests.ephemeral"

#if DEBUG_RECORDER
    static let recorderDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("com.dicticus.tests.DebugRecordings", isDirectory: true)
#endif

    override init() {
        super.init()
#if os(macOS)
        if Bundle.main.bundleIdentifier == "com.dicticus.app" {
            fatalError("DicticusTestBootstrap: the test host carries the production bundle id com.dicticus.app, so tests would write the real UserDefaults domain. Usually a -configuration Debug-Recorder flag overrode the scheme's Debug-Recorder-Test config; run without -configuration. Refusing before any test runs.")
        }
#endif
#if DEBUG_RECORDER
        try? FileManager.default.removeItem(at: Self.recorderDirectory)
        DebugRecorder.directoryOverrideForTesting = Self.recorderDirectory
#endif
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
