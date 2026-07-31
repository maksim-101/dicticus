import XCTest
@testable import Dicticus

// Tests for SystemSettingsURL URL constants
// Verifies each URL contains the correct Privacy anchor and uses the expected scheme
final class SystemSettingsURLTests: XCTestCase {

    func testMicrophoneURLScheme() {
        let url = SystemSettingsURL.microphone
        XCTAssertEqual(url.scheme, "x-apple.systempreferences")
    }

    func testMicrophoneURLContainsPrivacyAnchor() {
        let urlString = SystemSettingsURL.microphone.absoluteString
        XCTAssertTrue(urlString.contains("Privacy_Microphone"),
                      "Microphone URL must contain Privacy_Microphone anchor, got: \(urlString)")
    }

    func testAccessibilityURLScheme() {
        let url = SystemSettingsURL.accessibility
        XCTAssertEqual(url.scheme, "x-apple.systempreferences")
    }

    func testAccessibilityURLContainsPrivacyAnchor() {
        let urlString = SystemSettingsURL.accessibility.absoluteString
        XCTAssertTrue(urlString.contains("Privacy_Accessibility"),
                      "Accessibility URL must contain Privacy_Accessibility anchor, got: \(urlString)")
    }


    func testAllURLsAreDistinct() {
        let mic = SystemSettingsURL.microphone.absoluteString
        let acc = SystemSettingsURL.accessibility.absoluteString
        XCTAssertNotEqual(mic, acc)
    }

    // D-15: CTA→pane mapping contract — each missing permission must map to its own
    // exact System Settings URL. These pin what PermissionRow.settingsURL delivers
    // to SystemSettingsURL.open(_:) for every missing-permission row.

    func testMicrophoneSettingsURLMatchesExpectedAnchor() {
        XCTAssertEqual(
            SystemSettingsURL.microphone.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        )
    }

    func testAccessibilitySettingsURLMatchesExpectedAnchor() {
        XCTAssertEqual(
            SystemSettingsURL.accessibility.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
    }

}
