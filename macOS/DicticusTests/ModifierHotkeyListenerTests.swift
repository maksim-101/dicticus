import XCTest
import AppKit
import CoreGraphics
@testable import Dicticus

/// Unit tests for ModifierHotkeyListener flag transition logic.
///
/// Tests the pure function `detectTransition(from:to:plainCombo:cleanupCombo:)`
/// without any hardware input or CGEventTap plumbing. All tests are synchronous
/// and deterministic.
///
/// Test scenarios cover:
/// - Activation: both combo flags appear together
/// - Release: one combo flag disappears
/// - Partial press: only one of the two required flags is held
/// - Extra modifiers: additional flags prevent activation
/// - Mode routing: different combos map to correct DictationMode
final class ModifierHotkeyListenerTests: XCTestCase {

    // MARK: - Test 1: Fn+Shift activation triggers plain dictation

    func testFnShiftActivation_triggersPlainDictation() {
        // Pressing Fn then Shift produces flags [.maskSecondaryFn, .maskShift].
        // The transition from [] to those flags should fire a press for fnShift.
        let result = ModifierHotkeyListener.detectTransition(
            from: [],
            to: [.maskSecondaryFn, .maskShift],
            plainCombo: .fnShift,
            cleanupCombo: .fnControl
        )

        XCTAssertNotNil(result, "Expected combo activation to be detected")
        XCTAssertEqual(result?.mode, .plain)
        XCTAssertTrue(result?.isPress ?? false, "Expected isPress == true for activation")
    }

    // MARK: - Test 2: Fn+Shift release triggers plain dictation release

    func testFnShiftRelease_triggersPlainDictationRelease() {
        // Releasing shift (or fn) while both were held triggers a release event.
        let result = ModifierHotkeyListener.detectTransition(
            from: [.maskSecondaryFn, .maskShift],
            to: [],
            plainCombo: .fnShift,
            cleanupCombo: .fnControl
        )

        XCTAssertNotNil(result, "Expected combo release to be detected")
        XCTAssertEqual(result?.mode, .plain)
        XCTAssertFalse(result?.isPress ?? true, "Expected isPress == false for release")
    }

    // MARK: - Test 3: Fn alone does NOT trigger activation

    func testFnAlone_doesNotTriggerActivation() {
        // Only one modifier held — combo not complete yet. Should not fire.
        let result = ModifierHotkeyListener.detectTransition(
            from: [],
            to: [.maskSecondaryFn],
            plainCombo: .fnShift,
            cleanupCombo: .fnControl
        )

        XCTAssertNil(result, "Expected no transition for partial modifier press")
    }

    // MARK: - Test 4: Shift released while Fn held triggers combo release

    func testShiftReleasedWhileFnHeld_triggersRelease() {
        // Transition from [Fn+Shift] to [Fn] — Shift was released while Fn is still held.
        // This should be treated as a release of the fnShift combo.
        let result = ModifierHotkeyListener.detectTransition(
            from: [.maskSecondaryFn, .maskShift],
            to: [.maskSecondaryFn],
            plainCombo: .fnShift,
            cleanupCombo: .fnControl
        )

        XCTAssertNotNil(result, "Expected combo release when shift is dropped while fn held")
        XCTAssertEqual(result?.mode, .plain)
        XCTAssertFalse(result?.isPress ?? true, "Expected isPress == false for partial release")
    }

    // MARK: - Test 5: Extra modifier present at start prevents activation on subset

    func testExtraModifier_preventsActivation() {
        // [Fn+Shift+Option] -> [Fn+Shift]: option was released, fnShift flags remain.
        // fnShift should NOT be treated as newly activated — it was already present
        // in the previous state (prev.isSuperset(of: fnShift.flags) is true).
        // Neither combo was cleanupCombo (fnControl), so no release fires for that either.
        // Result: nil — no activation and no release of any configured combo.
        let result = ModifierHotkeyListener.detectTransition(
            from: [.maskSecondaryFn, .maskShift, .maskAlternate],
            to: [.maskSecondaryFn, .maskShift],
            plainCombo: .fnShift,
            cleanupCombo: .fnControl
        )

        XCTAssertNil(result, "Expected no activation when fnShift was already held before extra modifier was released")
    }

    // MARK: - Test 6: Fn+Control routes to aiCleanup mode

    func testFnControlActivation_routesToAiCleanup() {
        let result = ModifierHotkeyListener.detectTransition(
            from: [],
            to: [.maskSecondaryFn, .maskControl],
            plainCombo: .fnShift,
            cleanupCombo: .fnControl
        )

        XCTAssertNotNil(result, "Expected combo activation for fnControl")
        XCTAssertEqual(result?.mode, .aiCleanup)
        XCTAssertTrue(result?.isPress ?? false, "Expected isPress == true for aiCleanup activation")
    }

    // MARK: - Additional edge cases

    func testFnControlRelease_routesToAiCleanup() {
        let result = ModifierHotkeyListener.detectTransition(
            from: [.maskSecondaryFn, .maskControl],
            to: [],
            plainCombo: .fnShift,
            cleanupCombo: .fnControl
        )

        XCTAssertNotNil(result, "Expected release detection for fnControl combo")
        XCTAssertEqual(result?.mode, .aiCleanup)
        XCTAssertFalse(result?.isPress ?? true, "Expected isPress == false for aiCleanup release")
    }

    func testNoFlags_noTransition() {
        // No flags in either state — nothing to detect
        let result = ModifierHotkeyListener.detectTransition(
            from: [],
            to: [],
            plainCombo: .fnShift,
            cleanupCombo: .fnControl
        )

        XCTAssertNil(result, "Expected nil when neither previous nor current has any flags")
    }

    func testSameFlags_noTransition() {
        // Flags did not change — no transition event
        let result = ModifierHotkeyListener.detectTransition(
            from: [.maskSecondaryFn, .maskShift],
            to: [.maskSecondaryFn, .maskShift],
            plainCombo: .fnShift,
            cleanupCombo: .fnControl
        )

        XCTAssertNil(result, "Expected nil when flags are identical (no transition)")
    }

    // MARK: - Release debounce — shouldFireRelease (debug session ptt-stops-mid-hold)

    /// Spurious-flag-drop case: the global monitor delivered a `flagsChanged` event whose
    /// flags were missing the combo, but the live system state at debounce time still has
    /// the combo present. This is the bug we're guarding against — release MUST be suppressed.
    func testShouldFireRelease_liveFlagsStillContainCombo_returnsFalse() {
        let combo: NSEvent.ModifierFlags = [.function, .control]
        let live: NSEvent.ModifierFlags = [.function, .control]

        XCTAssertFalse(
            ModifierHotkeyListener.shouldFireRelease(liveFlags: live, comboFlags: combo),
            "Transient flag drop: live system state still contains combo — release must be discarded"
        )
    }

    /// Genuine release case: live system flags no longer contain the combo at debounce time.
    func testShouldFireRelease_liveFlagsMissingCombo_returnsTrue() {
        let combo: NSEvent.ModifierFlags = [.function, .control]
        let live: NSEvent.ModifierFlags = []

        XCTAssertTrue(
            ModifierHotkeyListener.shouldFireRelease(liveFlags: live, comboFlags: combo),
            "Real release: live system state missing combo flags — release must fire"
        )
    }

    /// Partial release case: one combo flag dropped, the other still held.
    /// Live state lacks the combo as a whole → release should fire.
    func testShouldFireRelease_partialRelease_returnsTrue() {
        let combo: NSEvent.ModifierFlags = [.function, .control]
        let live: NSEvent.ModifierFlags = [.function]

        XCTAssertTrue(
            ModifierHotkeyListener.shouldFireRelease(liveFlags: live, comboFlags: combo),
            "Partial release: live state lacks at least one combo flag — release must fire"
        )
    }

    /// Irrelevant flags (e.g. CapsLock) on top of the combo must not be misread as a release.
    func testShouldFireRelease_irrelevantFlagsIgnored_returnsFalse() {
        let combo: NSEvent.ModifierFlags = [.function, .control]
        let live: NSEvent.ModifierFlags = [.function, .control, .capsLock, .command]

        XCTAssertFalse(
            ModifierHotkeyListener.shouldFireRelease(liveFlags: live, comboFlags: combo),
            "Irrelevant flags (CapsLock/Command) must be masked out before the superset check"
        )
    }
}
