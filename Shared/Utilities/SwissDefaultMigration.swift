import Foundation

/// One-time migration that flips the `useSwissGerman` AppGroup default to ON
/// for installs that have never explicitly set it. Per Phase 19.5 D-A3.
///
/// Idempotency contract: gated by `swissDefaultMigratedV2_1` flag. After the
/// first run on any device, subsequent calls are no-ops — even if the user
/// later flips the toggle back to OFF, the migration will NOT re-flip it.
///
/// Called from these sites (per B1/B2/B4 fixes):
///   1. `iOS/Dicticus/DicticusApp.swift` — first line inside the
///      `scenePhase == .active` handler AND on `ContentView()`'s `.onAppear`
///      (belt-and-suspenders so first launch migrates before scenePhase fires).
///   2. `macOS/Dicticus/DicticusApp.swift` — first line of the `.task`
///      modifier on `MenuBarExtra`, before `permissionManager.checkAll()`
///      and `warmupService.warmup()`.
///   3. `macOS/Dicticus/Views/SwissGermanToggleRow.swift` — first line of
///      `currentValue()` static helper (B4 self-heal — view-construction
///      may race ahead of `MenuBarExtra.task` on first render).
///
/// Must run BEFORE any service that reads `useSwissGerman`
/// (`TextProcessingService`, `CleanupPrompt`, `CleanupService`, the Settings
/// UI bindings).
public enum SwissDefaultMigration {
    public static let migratedKey = "swissDefaultMigratedV2_1"
    public static let toggleKey = "useSwissGerman"

    public static func runIfNeeded() {
        let suite = DicticusDefaults.suite
        guard !suite.bool(forKey: migratedKey) else { return }
        if suite.object(forKey: toggleKey) == nil {
            suite.set(true, forKey: toggleKey)
        }
        suite.set(true, forKey: migratedKey)
    }
}
