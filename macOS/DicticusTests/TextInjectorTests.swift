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
}
