import SwiftUI
import LaunchAtLogin

/// Settings → General pane.
///
/// Group "Startup & behavior": Launch at login + Media pause toggle + Clipboard fallback toggle + Live transcript toggle.
/// Last row (Q-01 fallback): Quit Dicticus.
///
/// Relocates controls from SettingsSection per UIORG-04 (bindings unchanged).
struct GeneralPane: View {

    var body: some View {
        Form {
            Section("Startup & behavior") {
                LaunchAtLogin.Toggle("Launch at login")

                MediaPauseToggleRow()

                ClipboardFallbackToggleRow()

                LiveOverlayToggleRow()
            }

            Section {
                Button("Quit Dicticus") {
                    NSApplication.shared.terminate(nil)
                }
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

}
