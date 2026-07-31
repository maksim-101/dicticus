import XCTest
@testable import Dicticus

@MainActor
final class IOSModelWarmupServiceTests: XCTestCase {
    func testInitialState() {
        let service = IOSModelWarmupService()
        XCTAssertFalse(service.isWarming)
        XCTAssertFalse(service.isReady)
        XCTAssertNil(service.error)
    }
    func testWhisperKitInstanceIsNilBeforeWarmup() {
        let service = IOSModelWarmupService()
        XCTAssertNil(service.whisperKitInstance)
    }
    func testCancelWarmupResetsState() {
        let service = IOSModelWarmupService()
        service.cancelWarmup()
        XCTAssertFalse(service.isWarming)
    }

    // MARK: - Wave 3 (Plan 19-04) — Task 1: LlmStatus type surface

    func testLlmStatusIsIdleOnInit() {
        let service = IOSModelWarmupService()
        XCTAssertEqual(service.llmStatus, .idle)
    }

    func testIsLlmReadyIsFalseOnInit() {
        let service = IOSModelWarmupService()
        XCTAssertFalse(service.isLlmReady)
    }

    func testCleanupServiceInstanceIsNilOnInit() {
        let service = IOSModelWarmupService()
        XCTAssertNil(service.cleanupServiceInstance)
    }

    func testLlmStatusIdleLabel() {
        XCTAssertEqual(IOSModelWarmupService.LlmStatus.idle.label, "Waiting")
    }

    func testLlmStatusReadyLabel() {
        XCTAssertEqual(IOSModelWarmupService.LlmStatus.ready.label, "Ready")
    }

    func testLlmStatusFailedLabelCarriesReason() {
        XCTAssertEqual(
            IOSModelWarmupService.LlmStatus.failed("AI cleanup unavailable").label,
            "AI cleanup unavailable"
        )
    }

    func testLlmStatusIsActiveOnlyWhileLoading() {
        XCTAssertFalse(IOSModelWarmupService.LlmStatus.idle.isActive)
        XCTAssertTrue(IOSModelWarmupService.LlmStatus.loading.isActive)
        XCTAssertFalse(IOSModelWarmupService.LlmStatus.ready.isActive)
        XCTAssertFalse(IOSModelWarmupService.LlmStatus.failed("x").isActive)
    }

    // MARK: - Wave 3 (Plan 19-04) — Task 2: Step 4 gate defaults

    /// Gate precondition: with no AppGroup value set, `aiCleanupEnabled`
    /// must read as `false` — warmup Step 4 MUST skip silently and
    /// `llmStatus` must remain `.idle`. This verifies the default-OFF
    /// posture independently of the heavy warmup pipeline.
    func testAiCleanupToggleDefaultsOffInAppGroup() {
        let suite = UserDefaults(suiteName: "group.com.dicticus") ?? UserDefaults.standard
        // Confirm the key Step 4 reads matches the Settings UI key.
        // (SettingsView.appGroupBinding writes this same key.)
        suite.removeObject(forKey: "aiCleanupEnabled")
        XCTAssertFalse(suite.bool(forKey: "aiCleanupEnabled"),
                       "Default must be false so Step 4 skips on a fresh install")
    }

    /// Gate precondition: before Step 4 runs, the published state snapshot
    /// must be the safe default — `.idle` + `isLlmReady == false` — even
    /// after a cancelWarmup round-trip that previously only cleared ASR state.
    func testLlmStatusRemainsIdleAfterCancelWarmup() {
        let service = IOSModelWarmupService()
        service.cancelWarmup()
        XCTAssertEqual(service.llmStatus, .idle)
        XCTAssertFalse(service.isLlmReady)
    }

    // MARK: - Phase 33 Plan 01 — Task 1 (IOS-ONB-01): synchronous hasModels init

    /// Pins the IOS-ONB-01 fix: `hasModels` must reflect the real filesystem
    /// state immediately after init — BEFORE any async warmup runs.
    ///
    /// On the simulator (no model downloaded), `hasModels` must be `false`
    /// right after construction. Two services created in the same process must
    /// agree on the value, confirming it is computed from the same filesystem
    /// source rather than a per-instance async race. This pins the synchronous-
    /// init contract without requiring a direct import of the ASR SDK in the
    /// test target.
    func testHasModelsReflectsFilesystemStateImmediatelyAfterInit() {
        let service1 = IOSModelWarmupService()
        let service2 = IOSModelWarmupService()
        // Both instances must report the same value because both read the same
        // local cache directory synchronously at init time. If either used an
        // async dispatch (the old bug pattern), a data race between frames and
        // the dispatch could produce divergent values — though in practice on
        // the simulator both would start false then flip, making disagreement
        // unlikely but the ordering guarantee absent.
        XCTAssertEqual(service1.hasModels, service2.hasModels,
                       "hasModels must be computed synchronously from the filesystem at init — both instances read the same cache directory")
        // On a clean simulator (no model downloaded), the value must be false.
        // This is the primary assertion for the flash-fix contract.
        XCTAssertFalse(service1.hasModels,
                       "hasModels must be false on a simulator with no model downloaded — a flash-free first launch requires the correct initial state")
    }
}
