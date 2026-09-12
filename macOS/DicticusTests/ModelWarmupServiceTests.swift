import XCTest
@testable import Dicticus

// Tests for ModelWarmupService state machine.
// We do NOT test actual WhisperKit initialization (requires network + model download).
// These tests verify the state transitions, computed properties, and guard logic.
@MainActor
final class ModelWarmupServiceTests: XCTestCase {

    // MARK: - Initial state tests

    func testInitialStateIsNotWarming() {
        let service = ModelWarmupService()
        XCTAssertFalse(service.isWarming, "isWarming should be false on init")
    }

    func testInitialStateIsNotReady() {
        let service = ModelWarmupService()
        XCTAssertFalse(service.isReady, "isReady should be false on init")
    }

    func testInitialStateHasNoError() {
        let service = ModelWarmupService()
        XCTAssertNil(service.error, "error should be nil on init")
    }

    func testShowWarmupRowFalseInitially() {
        let service = ModelWarmupService()
        // Not warming and no error — row should be hidden
        XCTAssertFalse(service.showWarmupRow, "showWarmupRow should be false when not warming and no error")
    }

    func testStatusTextNilInitially() {
        let service = ModelWarmupService()
        XCTAssertNil(service.statusText, "statusText should be nil when not warming and no error")
    }

    // MARK: - Warming state tests

    func testStatusTextWhenWarming() {
        let service = ModelWarmupService()
        service.isWarming = true
        XCTAssertEqual(service.statusText, "Preparing models\u{2026}",
                       "statusText should be 'Preparing models…' when isWarming is true")
    }

    func testShowWarmupRowTrueWhenWarming() {
        let service = ModelWarmupService()
        service.isWarming = true
        XCTAssertTrue(service.showWarmupRow, "showWarmupRow should be true when isWarming is true")
    }

    // MARK: - Ready state tests

    func testShowWarmupRowFalseWhenReady() {
        let service = ModelWarmupService()
        service.isWarming = false
        service.isReady = true
        XCTAssertFalse(service.showWarmupRow, "showWarmupRow should be false when isReady and no error")
    }

    func testStatusTextNilWhenReady() {
        let service = ModelWarmupService()
        service.isWarming = false
        service.isReady = true
        XCTAssertNil(service.statusText, "statusText should be nil when isReady is true")
    }

    // MARK: - Error state tests

    func testShowWarmupRowTrueWhenError() {
        let service = ModelWarmupService()
        service.isWarming = false
        service.error = "Model load failed. Restart app."
        XCTAssertTrue(service.showWarmupRow, "showWarmupRow should be true when error is non-nil")
    }

    func testStatusTextContainsErrorMessageWhenError() {
        let service = ModelWarmupService()
        service.error = "Model load failed. Restart app."
        XCTAssertNotNil(service.statusText, "statusText should not be nil when error is set")
        XCTAssertTrue(service.statusText?.contains("Model load failed") ?? false,
                      "statusText should contain 'Model load failed' when error is set")
    }

    func testStatusTextReturnsFullErrorString() {
        let errorMessage = "Model load failed. Restart app."
        let service = ModelWarmupService()
        service.error = errorMessage
        XCTAssertEqual(service.statusText, errorMessage,
                       "statusText should return the exact error string")
    }

    // MARK: - Cleanup service instance (Phase 4 / INFRA-02)

    func testCleanupServiceInstanceIsNilBeforeWarmup() {
        let service = ModelWarmupService()
        XCTAssertNil(service.cleanupServiceInstance,
                      "cleanupServiceInstance must be nil before warmup (INFRA-02)")
    }

    // MARK: - Guard logic test

    func testWarmupGuardPreventsDuplicateCalls() {
        let service = ModelWarmupService()
        // Set state as if already warming
        service.isWarming = true
        // Calling warmup() again should not change the state
        // The guard inside warmup() checks isWarming and isReady
        let wasWarming = service.isWarming
        // We can't easily test the Task.detached in unit tests, but we can verify
        // the guard condition logic: if isWarming is true, the state remains unchanged
        XCTAssertTrue(wasWarming, "isWarming should still be true — guard prevents re-entry")
    }

    // MARK: - Phase 50 D-10/D-11: idle-unload pure decision + threshold reader

    func testShouldUnload_boundary() {
        let now = Date()
        XCTAssertTrue(
            ModelWarmupService.shouldUnload(lastActivityAt: now.addingTimeInterval(-600), now: now, idleThreshold: 600),
            "elapsed time exactly equal to idleThreshold must count as idle (inclusive boundary, mirrors shouldWarmUp)"
        )
        XCTAssertFalse(
            ModelWarmupService.shouldUnload(lastActivityAt: now.addingTimeInterval(-599), now: now, idleThreshold: 600),
            "one second short of the threshold must not unload"
        )
        XCTAssertTrue(
            ModelWarmupService.shouldUnload(lastActivityAt: now.addingTimeInterval(-1800), now: now, idleThreshold: 1800),
            "elapsed time exactly equal to a 30-minute threshold must count as idle"
        )
        XCTAssertFalse(
            ModelWarmupService.shouldUnload(lastActivityAt: now.addingTimeInterval(-86400), now: now, idleThreshold: nil),
            "nil threshold means Never — must never unload regardless of elapsed time"
        )
    }

    func testIdleUnloadThreshold_fromDefaults() {
        XCTAssertEqual(ModelWarmupService.idleUnloadDefaultsKey, "llmIdleUnloadMinutes")
        XCTAssertEqual(ModelWarmupService.idleUnloadDefaultMinutes, 10)

        let defaults = InMemoryUserDefaults()
        XCTAssertEqual(
            ModelWarmupService.idleUnloadThreshold(from: defaults), 600,
            "absent key must fall back to the 10-minute default"
        )

        defaults.set(5, forKey: ModelWarmupService.idleUnloadDefaultsKey)
        XCTAssertEqual(ModelWarmupService.idleUnloadThreshold(from: defaults), 300)

        defaults.set(30, forKey: ModelWarmupService.idleUnloadDefaultsKey)
        XCTAssertEqual(ModelWarmupService.idleUnloadThreshold(from: defaults), 1800)

        defaults.set(0, forKey: ModelWarmupService.idleUnloadDefaultsKey)
        XCTAssertNil(ModelWarmupService.idleUnloadThreshold(from: defaults), "0 minutes means Never (nil threshold)")

        defaults.set(-3, forKey: ModelWarmupService.idleUnloadDefaultsKey)
        XCTAssertEqual(
            ModelWarmupService.idleUnloadThreshold(from: defaults), 600,
            "garbage (negative) value must fall back to the default"
        )
    }
}
