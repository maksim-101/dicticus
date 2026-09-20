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

    func testDeliveryBlocker_frontmostChanged() {
        XCTAssertEqual(
            TextInjector.deliveryBlocker(expectedBundleID: "com.a", currentBundleID: "com.b"),
            .frontmostChanged
        )
        XCTAssertNil(
            TextInjector.deliveryBlocker(expectedBundleID: "com.a", currentBundleID: "com.a")
        )
        XCTAssertNil(
            TextInjector.deliveryBlocker(expectedBundleID: nil, currentBundleID: "com.b")
        )
        XCTAssertNil(
            TextInjector.deliveryBlocker(expectedBundleID: "com.a", currentBundleID: nil)
        )
        XCTAssertNil(
            TextInjector.deliveryBlocker(expectedBundleID: nil, currentBundleID: nil)
        )
    }

    func testDeliveryBlockerRawValues_matchProbeVocabulary() {
        XCTAssertEqual(TextInjector.DeliveryBlocker.frontmostChanged.rawValue, "frontmost_changed")
    }

    // MARK: - Phase 50 D-02: injectText four-exit seam-driven fixtures

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

    // MARK: - Phase 50 plan 11 / quick 260920-9m8 D-2: content-compare restore + delay floor

    func testShouldRestoreClipboard_contentCompareTrimmed() {
        XCTAssertTrue(TextInjector.shouldRestoreClipboard(currentString: "alpha beta", writtenText: "alpha beta "))
        XCTAssertTrue(TextInjector.shouldRestoreClipboard(currentString: "alpha beta \n", writtenText: "alpha beta "))
        XCTAssertFalse(TextInjector.shouldRestoreClipboard(currentString: "copied-meanwhile", writtenText: "alpha beta "))
        XCTAssertFalse(TextInjector.shouldRestoreClipboard(currentString: nil, writtenText: "alpha beta "))
    }

    func testClipboardRestoreDelay_floorPinnedAgainstReLowering() {
        XCTAssertGreaterThanOrEqual(TextInjector.clipboardRestoreDelayMilliseconds, 400)
    }

    func testInjectText_delivered_skipsRestoreWhenDifferentContentWrittenDuringWindow() async {
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

    // MARK: - Quick 260920-9m8: secure input delivers; content-compare restore

    func testInjectText_secureInput_stillDeliversAndRestoresClipboard() async {
        let pasteboard = NSPasteboard.general
        let originalSaved = injector.saveClipboard(pasteboard)
        defer { injector.restoreClipboard(pasteboard, saved: originalSaved) }

        pasteboard.clearContents()
        pasteboard.setString("before", forType: .string)

        var pasteCount = 0
        injector.axTrustedProbe = { true }
        injector.secureInputProbe = { true }
        injector.frontmostBundleIDProvider = { "com.example.target" }
        injector.pasteSynthesizer = { pasteCount += 1 }

        let outcome = await injector.injectText("alpha beta", expectedFrontmostBundleID: "com.example.target")

        XCTAssertEqual(outcome, .delivered)
        XCTAssertEqual(pasteCount, 1)
        XCTAssertEqual(pasteboard.string(forType: .string), "before")
    }

    func testInjectText_delivered_restoresWhenSameContentRewrittenDuringWindow() async {
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
            // Pure Paste.app simulation: rewrites the pasteboard as plain text after every
            // write — bumps changeCount but leaves the same content minus the trailing space.
            let thirdParty = NSPasteboard.general
            thirdParty.clearContents()
            thirdParty.setString("alpha beta", forType: .string)
        }

        let outcome = await injector.injectText("alpha beta", expectedFrontmostBundleID: "com.example.target")

        XCTAssertEqual(outcome, .delivered)
        XCTAssertEqual(pasteCount, 1)
        XCTAssertEqual(pasteboard.string(forType: .string), "before")
    }

    // MARK: - Quick 260920-9m8 D-3: clipboard-fallback setting

    func testInjectText_fallbackDisabled_leavesPasteboardUntouchedWithDistinctOutcome() async {
        let pasteboard = NSPasteboard.general
        let originalSaved = injector.saveClipboard(pasteboard)
        defer { injector.restoreClipboard(pasteboard, saved: originalSaved) }

        pasteboard.clearContents()
        pasteboard.setString("before", forType: .string)

        var pasteCount = 0
        injector.axTrustedProbe = { true }
        injector.frontmostBundleIDProvider = { "com.example.other" }
        injector.clipboardFallbackEnabled = { false }
        injector.pasteSynthesizer = { pasteCount += 1 }

        let outcome = await injector.injectText("alpha beta", expectedFrontmostBundleID: "com.example.target")

        XCTAssertEqual(outcome, .undeliverableClipboardUntouched(.frontmostChanged))
        XCTAssertEqual(pasteCount, 0)
        XCTAssertEqual(pasteboard.string(forType: .string), "before")
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
