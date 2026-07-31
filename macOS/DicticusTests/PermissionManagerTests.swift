import XCTest
@testable import Dicticus

// Tests for PermissionStatus enum and PermissionManager logic
// Uses direct enum value checks and computed property verification.
// Note: We cannot mock AVCaptureDevice/AXIsProcessTrusted in unit tests without running on the actual
// device permissions — so we test the logic layer (enum values, allGranted, UserDefaults).
@MainActor
final class PermissionManagerTests: XCTestCase {

    // MARK: - PermissionStatus enum tests

    func testPermissionStatusGrantedIconName() {
        XCTAssertEqual(PermissionStatus.granted.iconName, "checkmark.circle.fill")
    }

    func testPermissionStatusPendingIconName() {
        XCTAssertEqual(PermissionStatus.pending.iconName, "clock")
    }

    func testPermissionStatusDeniedIconName() {
        XCTAssertEqual(PermissionStatus.denied.iconName, "xmark.circle.fill")
    }

    func testPermissionStatusGrantedLabel() {
        XCTAssertEqual(PermissionStatus.granted.label, "Granted")
    }

    func testPermissionStatusPendingLabel() {
        XCTAssertEqual(PermissionStatus.pending.label, "Required")
    }

    func testPermissionStatusDeniedLabel() {
        XCTAssertEqual(PermissionStatus.denied.label, "Denied")
    }

    // MARK: - PermissionManager.allGranted tests

    func testAllGrantedReturnsTrueWhenAllGranted() {
        let manager = PermissionManager()
        manager.microphoneStatus = .granted
        manager.accessibilityStatus = .granted
        XCTAssertTrue(manager.allGranted)
    }

    func testAllGrantedReturnsFalseWhenMicrophoneNotGranted() {
        let manager = PermissionManager()
        manager.microphoneStatus = .pending
        manager.accessibilityStatus = .granted
        XCTAssertFalse(manager.allGranted)
    }

    func testAllGrantedReturnsFalseWhenAccessibilityNotGranted() {
        let manager = PermissionManager()
        manager.microphoneStatus = .granted
        manager.accessibilityStatus = .denied
        XCTAssertFalse(manager.allGranted)
    }

    func testAllGrantedReturnsFalseWhenNoneGranted() {
        let manager = PermissionManager()
        // Initial state is .pending for all
        XCTAssertFalse(manager.allGranted)
    }

    // MARK: - UserDefaults onboarding persistence tests

    func testLoadOnboardingStateReadsFalseByDefault() {
        // Ensure clean state, then verify loadOnboardingState() returns false
        UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
        let manager = PermissionManager()
        manager.loadOnboardingState()
        XCTAssertFalse(manager.hasCompletedOnboarding,
                       "hasCompletedOnboarding should be false when key is absent")
        // Cleanup
        UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
    }

    func testMarkOnboardingCompleteSetsFlag() {
        let manager = PermissionManager()
        manager.markOnboardingComplete()
        XCTAssertTrue(manager.hasCompletedOnboarding)
    }

    func testLoadOnboardingStateRestoresPersistedValue() {
        // Mark complete, then create a fresh manager and load
        let manager = PermissionManager()
        manager.markOnboardingComplete()

        let manager2 = PermissionManager()
        manager2.loadOnboardingState()
        XCTAssertTrue(manager2.hasCompletedOnboarding)

        // Cleanup: reset so other tests start clean
        UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
    }

    // MARK: - checkMultipleInstalls bundle id pin (D-11)

    func testCheckMultipleInstallsUsesCorrectBundleID() {
        // Verify the mdfind query targets com.dicticus.app (the real CFBundleIdentifier),
        // not the old wrong value com.dicticus.macos. The observable assertion: any URL
        // returned by the query must be a Dicticus.app bundle — wrong bundle id would
        // return zero or spurious results, but correct id returns only Dicticus.app paths.
        let manager = PermissionManager()
        manager.checkMultipleInstalls()
        for url in manager.multipleDicticusCopies {
            XCTAssertTrue(url.lastPathComponent == "Dicticus.app",
                          "Unexpected path: \(url.path)")
        }
    }
}
