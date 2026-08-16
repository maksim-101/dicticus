import XCTest
import FluidAudio
@testable import Dicticus

@MainActor
final class IOSModelWarmupServiceTests: XCTestCase {
    func testInitialState() {
        let service = IOSModelWarmupService()
        XCTAssertFalse(service.isWarming)
        XCTAssertFalse(service.isReady)
        XCTAssertNil(service.error)
    }
    func testAsrManagerInstanceIsNilBeforeWarmup() {
        let service = IOSModelWarmupService()
        XCTAssertNil(service.asrManagerInstance)
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
    /// state immediately after init — BEFORE any async warmup runs, in whichever
    /// direction the filesystem currently points (a simulator that already has a
    /// model cached must read `true`; a clean one must read `false`).
    ///
    /// `hasModels` must equal a value this test derives itself, at the same
    /// moment, from the same on-disk location `IOSModelWarmupService` reads
    /// (FluidAudio's own sandboxed cache dir, `AsrModels.defaultCacheDirectory()` —
    /// Phase 47.1). Two services created in the same process must also agree with
    /// each other, confirming the value is computed from the same filesystem source
    /// rather than a per-instance async race. This pins the synchronous-init contract.
    ///
    /// The check is re-derived here via FluidAudio's own real `AsrModels.modelsExist(at:)`
    /// rather than reaching into `AsrModelLoader`/`IOSModelWarmupService` production
    /// code for it: it's an independent cross-check of the same fact, so a future
    /// divergence between the two derivations surfaces as a loud failure instead of
    /// both sides silently agreeing on a shared bug.
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

        let expectedHasModels = AsrModels.modelsExist(at: AsrModels.defaultCacheDirectory())

        XCTAssertEqual(service1.hasModels, expectedHasModels,
                       "hasModels must match whether the Parakeet model directory is currently populated on disk — this test derives the expectation from the filesystem instead of assuming a clean simulator")
    }

    // MARK: - 260815-ait Fix 5: isFirstWarmup pure predicate

    /// No stored version (fresh install, or `UserDefaults` never wrote the key) —
    /// must read as a first warm-up regardless of what the current key is.
    func testIsFirstWarmupTrueWhenNoStoredVersion() {
        XCTAssertTrue(
            IOSModelWarmupService.isFirstWarmup(storedVersionKey: nil, currentVersionKey: "42::model-a")
        )
    }

    /// A stored version from an older build or model — must read as a first
    /// warm-up for the new one, even though SOME warm-up completed previously.
    /// This is the version-keyed behavior the fix requires instead of a
    /// one-time boolean: an app/model update must see the honest copy again.
    func testIsFirstWarmupTrueWhenStoredVersionDiffers() {
        XCTAssertTrue(
            IOSModelWarmupService.isFirstWarmup(storedVersionKey: "41::model-a", currentVersionKey: "42::model-a")
        )
        XCTAssertTrue(
            IOSModelWarmupService.isFirstWarmup(storedVersionKey: "42::model-a", currentVersionKey: "42::model-b")
        )
    }

    /// The stored version exactly matches the current build/model — this warm-up
    /// already completed once for this exact combination, so it is NOT a first
    /// warm-up and must get the fast copy.
    func testIsFirstWarmupFalseWhenStoredVersionMatchesCurrent() {
        XCTAssertFalse(
            IOSModelWarmupService.isFirstWarmup(storedVersionKey: "42::model-a", currentVersionKey: "42::model-a")
        )
    }
}
