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
}
