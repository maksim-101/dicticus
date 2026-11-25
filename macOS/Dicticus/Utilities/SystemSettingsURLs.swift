import Foundation
import AppKit

/// URL constants for opening specific Privacy & Security panes in System Settings.
/// Uses the `x-apple.systempreferences:` scheme with Privacy anchors — undocumented
/// but stable since macOS 13 and widely used by other menu bar apps.
enum SystemSettingsURL {
    static let microphone = URL(string:
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
    static let accessibility = URL(string:
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    /// Opens the given System Settings URL via NSWorkspace.
    /// Preferred over openSettings() environment action which is unreliable in menu bar apps.
    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
