import XCTest
@testable import Dicticus

final class HotkeyDisplayTests: XCTestCase {

    // MARK: - hotkeySubline branches

    func testBothSet() {
        let result = HotkeyDisplay.hotkeySubline(plainStandard: "⌃⇧S", cleanupStandard: "⌃⇧D")
        XCTAssertEqual(result, "Press ⌃⇧S to dictate · ⌃⇧D with AI cleanup")
    }

    func testPlainOnly() {
        let result = HotkeyDisplay.hotkeySubline(plainStandard: "⌃⇧S", cleanupStandard: nil)
        XCTAssertEqual(result, "Press ⌃⇧S to dictate")
    }

    func testCleanupOnly() {
        let result = HotkeyDisplay.hotkeySubline(plainStandard: nil, cleanupStandard: "⌃⇧D")
        XCTAssertEqual(result, "Press ⌃⇧D with AI cleanup")
    }

    func testNoneSet() {
        let result = HotkeyDisplay.hotkeySubline(plainStandard: nil, cleanupStandard: nil)
        XCTAssertEqual(result, "Set a hotkey in Settings →")
    }

    // MARK: - voiceOverStatusLabel branches

    func testVoiceOverRecording() {
        let result = HotkeyDisplay.voiceOverStatusLabel(
            state: .recording,
            plainStandard: "⌃⇧S",
            cleanupStandard: "⌃⇧D"
        )
        XCTAssertEqual(result, "Status: Recording.")
    }

    func testVoiceOverNeedsPermission() {
        let result = HotkeyDisplay.voiceOverStatusLabel(
            state: .needsPermission,
            plainStandard: nil,
            cleanupStandard: nil
        )
        XCTAssertEqual(result, "Status: Needs Permission. Tap to open System Settings.")
    }

    func testVoiceOverReadyBothSet() {
        let result = HotkeyDisplay.voiceOverStatusLabel(
            state: .ready,
            plainStandard: "⌃⇧S",
            cleanupStandard: "⌃⇧D"
        )
        XCTAssertTrue(result.hasPrefix("Status: Ready."), "Should start with 'Status: Ready.'")
        XCTAssertTrue(result.contains("Control-Shift-S"), "Should contain spelled-out plain hotkey")
        XCTAssertTrue(result.contains("Control-Shift-D"), "Should contain spelled-out cleanup hotkey")
    }
}
