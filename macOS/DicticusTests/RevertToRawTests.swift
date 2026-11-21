import XCTest
import KeyboardShortcuts
@testable import Dicticus

/// R-06: the revert-to-raw hotkey has no default binding. The Home button and its
/// enable/disable seam went in slice 52; the CGEvent paste itself is Accessibility-gated
/// and is verified on-device, not here.
@MainActor
final class RevertToRawTests: XCTestCase {

    func testRevertToRawHotkeyHasNoDefaultBinding() {
        XCTAssertNil(KeyboardShortcuts.getShortcut(for: .revertToRaw))
    }
}
