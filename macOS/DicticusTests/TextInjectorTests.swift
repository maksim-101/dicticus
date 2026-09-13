import XCTest
@testable import Dicticus

@MainActor
final class TextInjectorTests: XCTestCase {

    private let injector = TextInjector()

    // MARK: - Clipboard save/restore

    func testClipboardSaveAndRestoreString() {
        let pasteboard = NSPasteboard.general
        let originalText = "test-original-clipboard-\(UUID().uuidString)"

        // Setup: put known text on clipboard
        pasteboard.clearContents()
        pasteboard.setString(originalText, forType: .string)

        // Save
        let saved = injector.saveClipboard(pasteboard)

        // Overwrite clipboard
        pasteboard.clearContents()
        pasteboard.setString("overwritten", forType: .string)

        // Restore
        injector.restoreClipboard(pasteboard, saved: saved)

        // Verify original text restored
        XCTAssertEqual(pasteboard.string(forType: .string), originalText)
    }

    func testClipboardSaveAndRestoreMultipleTypes() {
        let pasteboard = NSPasteboard.general
        let stringText = "multi-type-test-\(UUID().uuidString)"
        let rtfData = "{\\rtf1 Hello}".data(using: .utf8)!

        // Setup: put string + RTF on clipboard
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(stringText, forType: .string)
        item.setData(rtfData, forType: .rtf)
        pasteboard.writeObjects([item])

        // Save
        let saved = injector.saveClipboard(pasteboard)

        // Overwrite
        pasteboard.clearContents()
        pasteboard.setString("overwritten", forType: .string)

        // Restore
        injector.restoreClipboard(pasteboard, saved: saved)

        // Verify both types restored
        XCTAssertEqual(pasteboard.string(forType: .string), stringText)
        XCTAssertNotNil(pasteboard.data(forType: .rtf))
    }

    func testClipboardSaveEmpty() {
        let pasteboard = NSPasteboard.general

        // Setup: empty clipboard
        pasteboard.clearContents()

        // Save empty state
        let saved = injector.saveClipboard(pasteboard)
        XCTAssertTrue(saved.items.isEmpty)

        // Restore should not crash
        injector.restoreClipboard(pasteboard, saved: saved)
    }

    func testSynthesizePasteDoesNotCrash() {
        // Cannot verify actual paste without a target app,
        // but CGEvent creation and posting should not crash.
        // If Accessibility is not granted, CGEvent.post fails silently (Pitfall 4).
        injector.synthesizePaste()
        // No crash = pass
    }

    // MARK: - Phase 50 D-02: deliveryBlocker pure predicate

    func testDeliveryBlocker_secureInputWins() {
        XCTAssertEqual(
            TextInjector.deliveryBlocker(secureInputEnabled: true, expectedBundleID: "com.a", currentBundleID: "com.a"),
            .secureInput
        )
        XCTAssertEqual(
            TextInjector.deliveryBlocker(secureInputEnabled: true, expectedBundleID: nil, currentBundleID: nil),
            .secureInput
        )
        XCTAssertEqual(
            TextInjector.deliveryBlocker(secureInputEnabled: true, expectedBundleID: "com.a", currentBundleID: "com.b"),
            .secureInput
        )
    }

    func testDeliveryBlocker_frontmostChanged() {
        XCTAssertEqual(
            TextInjector.deliveryBlocker(secureInputEnabled: false, expectedBundleID: "com.a", currentBundleID: "com.b"),
            .frontmostChanged
        )
        XCTAssertNil(
            TextInjector.deliveryBlocker(secureInputEnabled: false, expectedBundleID: "com.a", currentBundleID: "com.a")
        )
        XCTAssertNil(
            TextInjector.deliveryBlocker(secureInputEnabled: false, expectedBundleID: nil, currentBundleID: "com.b")
        )
        XCTAssertNil(
            TextInjector.deliveryBlocker(secureInputEnabled: false, expectedBundleID: "com.a", currentBundleID: nil)
        )
        XCTAssertNil(
            TextInjector.deliveryBlocker(secureInputEnabled: false, expectedBundleID: nil, currentBundleID: nil)
        )
    }

    func testDeliveryBlockerRawValues_matchProbeVocabulary() {
        XCTAssertEqual(TextInjector.DeliveryBlocker.secureInput.rawValue, "secure_input")
        XCTAssertEqual(TextInjector.DeliveryBlocker.frontmostChanged.rawValue, "frontmost_changed")
    }

    // MARK: - Phase 50 D-02: injectText four-exit seam-driven fixtures

    func testInjectText_secureInput_fallsBackToClipboardWithoutPaste() async {
        let pasteboard = NSPasteboard.general
        let originalSaved = injector.saveClipboard(pasteboard)
        defer { injector.restoreClipboard(pasteboard, saved: originalSaved) }

        var pasteCount = 0
        injector.axTrustedProbe = { true }
        injector.secureInputProbe = { true }
        injector.pasteSynthesizer = { pasteCount += 1 }

        let outcome = await injector.injectText("alpha beta", expectedFrontmostBundleID: nil)

        XCTAssertEqual(outcome, .fallbackToClipboard(.secureInput))
        XCTAssertEqual(pasteboard.string(forType: .string), "alpha beta")
        XCTAssertEqual(pasteCount, 0)
    }

    func testInjectText_frontmostChanged_fallsBackToClipboardWithoutPaste() async {
        let pasteboard = NSPasteboard.general
        let originalSaved = injector.saveClipboard(pasteboard)
        defer { injector.restoreClipboard(pasteboard, saved: originalSaved) }

        var pasteCount = 0
        injector.axTrustedProbe = { true }
        injector.secureInputProbe = { false }
        injector.frontmostBundleIDProvider = { "com.example.other" }
        injector.pasteSynthesizer = { pasteCount += 1 }

        let outcome = await injector.injectText("alpha beta", expectedFrontmostBundleID: "com.example.target")

        XCTAssertEqual(outcome, .fallbackToClipboard(.frontmostChanged))
        XCTAssertEqual(pasteboard.string(forType: .string), "alpha beta")
        XCTAssertEqual(pasteCount, 0)
    }

    func testInjectText_delivered_pastesOnceAndRestoresClipboard() async {
        let pasteboard = NSPasteboard.general
        let originalSaved = injector.saveClipboard(pasteboard)
        defer { injector.restoreClipboard(pasteboard, saved: originalSaved) }

        pasteboard.clearContents()
        pasteboard.setString("before", forType: .string)

        var pasteCount = 0
        injector.axTrustedProbe = { true }
        injector.secureInputProbe = { false }
        injector.frontmostBundleIDProvider = { "com.example.target" }
        injector.pasteSynthesizer = { pasteCount += 1 }

        let outcome = await injector.injectText("alpha beta", expectedFrontmostBundleID: "com.example.target")

        XCTAssertEqual(outcome, .delivered)
        XCTAssertEqual(pasteCount, 1)
        XCTAssertEqual(pasteboard.string(forType: .string), "before")
    }

    func testInjectText_axUntrusted_isBlockedWithoutTouchingClipboard() async {
        let pasteboard = NSPasteboard.general
        let originalSaved = injector.saveClipboard(pasteboard)
        defer { injector.restoreClipboard(pasteboard, saved: originalSaved) }

        pasteboard.clearContents()
        pasteboard.setString("before", forType: .string)

        var pasteCount = 0
        injector.axTrustedProbe = { false }
        injector.pasteSynthesizer = { pasteCount += 1 }

        let outcome = await injector.injectText("alpha beta")

        XCTAssertEqual(outcome, .blocked)
        XCTAssertEqual(pasteCount, 0)
        XCTAssertEqual(pasteboard.string(forType: .string), "before")
    }

    // MARK: - Phase 50 plan 11: changeCount-guarded restore + delay floor

    func testShouldRestoreClipboard_onlyWhenChangeCountUnchanged() {
        XCTAssertTrue(TextInjector.shouldRestoreClipboard(changeCountAfterWrite: 41, changeCountAtRestore: 41))
        XCTAssertFalse(TextInjector.shouldRestoreClipboard(changeCountAfterWrite: 41, changeCountAtRestore: 42))
        XCTAssertFalse(TextInjector.shouldRestoreClipboard(changeCountAfterWrite: 41, changeCountAtRestore: 40))
    }

    func testClipboardRestoreDelay_floorPinnedAgainstReLowering() {
        XCTAssertGreaterThanOrEqual(TextInjector.clipboardRestoreDelayMilliseconds, 400)
    }

    func testInjectText_delivered_skipsRestoreWhenPasteboardChangedDuringWindow() async {
        let pasteboard = NSPasteboard.general
        let originalSaved = injector.saveClipboard(pasteboard)
        defer { injector.restoreClipboard(pasteboard, saved: originalSaved) }

        pasteboard.clearContents()
        pasteboard.setString("before", forType: .string)

        var pasteCount = 0
        injector.axTrustedProbe = { true }
        injector.secureInputProbe = { false }
        injector.frontmostBundleIDProvider = { "com.example.target" }
        injector.pasteSynthesizer = {
            pasteCount += 1
            // A real third-party write (user Cmd+C, clipboard manager) calls clearContents()
            // before writing — that's what actually bumps NSPasteboard.changeCount; a bare
            // setString() for an already-declared type does not move the counter.
            let thirdParty = NSPasteboard.general
            thirdParty.clearContents()
            thirdParty.setString("copied-meanwhile", forType: .string)
        }

        let outcome = await injector.injectText("alpha beta", expectedFrontmostBundleID: "com.example.target")

        XCTAssertEqual(outcome, .delivered)
        XCTAssertEqual(pasteCount, 1)
        XCTAssertEqual(pasteboard.string(forType: .string), "copied-meanwhile")
    }

    // MARK: - Phase 50 plan 12: overlapping calls (CR-01)

    func testInjectText_overlappingCalls_restoresUserOriginalClipboard() async {
        let pasteboard = NSPasteboard.general
        let originalSaved = injector.saveClipboard(pasteboard)
        defer { injector.restoreClipboard(pasteboard, saved: originalSaved) }

        pasteboard.clearContents()
        pasteboard.setString("user-original", forType: .string)

        var pasteCount = 0
        injector.axTrustedProbe = { true }
        injector.secureInputProbe = { false }
        injector.frontmostBundleIDProvider = { "com.example.target" }
        injector.pasteSynthesizer = { pasteCount += 1 }

        let first = Task { await injector.injectText("alpha", expectedFrontmostBundleID: "com.example.target") }
        try? await Task.sleep(for: .milliseconds(150))
        let second = await injector.injectText("bravo", expectedFrontmostBundleID: "com.example.target")
        let firstOutcome = await first.value

        XCTAssertEqual(firstOutcome, .delivered)
        XCTAssertEqual(second, .delivered)
        XCTAssertEqual(pasteCount, 2)
        XCTAssertEqual(pasteboard.string(forType: .string), "user-original")
    }

    func testInjectText_cancelledDuringBusyWindow_isBlockedWithoutSavingOrPasting() async {
        let pasteboard = NSPasteboard.general
        let originalSaved = injector.saveClipboard(pasteboard)
        defer { injector.restoreClipboard(pasteboard, saved: originalSaved) }

        pasteboard.clearContents()
        pasteboard.setString("user-original", forType: .string)

        var pasteCount = 0
        injector.axTrustedProbe = { true }
        injector.secureInputProbe = { false }
        injector.frontmostBundleIDProvider = { "com.example.target" }
        injector.pasteSynthesizer = { pasteCount += 1 }

        let first = Task { await injector.injectText("alpha", expectedFrontmostBundleID: "com.example.target") }
        try? await Task.sleep(for: .milliseconds(150))
        // Both the test and TextInjector are @MainActor, so `second`'s body cannot start until
        // this test suspends on `await second.value` below — cancellation is already observed
        // when the body reaches the wait loop. No sleep, no polling, no timing race.
        let second = Task { await injector.injectText("bravo", expectedFrontmostBundleID: "com.example.target") }
        second.cancel()

        let secondOutcome = await second.value
        XCTAssertEqual(secondOutcome, .blocked)

        let firstOutcome = await first.value
        XCTAssertEqual(firstOutcome, .delivered)
        XCTAssertEqual(pasteCount, 1)
        XCTAssertEqual(pasteboard.string(forType: .string), "user-original")
    }
}
