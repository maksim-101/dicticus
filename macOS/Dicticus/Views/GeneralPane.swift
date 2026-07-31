import SwiftUI
import LaunchAtLogin

/// Settings → General pane.
///
/// Group "Startup & behavior": Launch at login + Media pause toggle.
/// Group "History": Copy-mode (Raw/Polished) picker with footer.
/// Last row (Q-01 fallback): Quit Dicticus.
///
/// Relocates controls from SettingsSection per UIORG-04 (bindings unchanged).
struct GeneralPane: View {

    var body: some View {
        Form {
            Section("Startup & behavior") {
                LaunchAtLogin.Toggle("Launch at login")

                MediaPauseToggleRow()
            }

            Section {
                Picker("Copy from history rows", selection: copyModeBinding) {
                    Text("Raw").tag(CleanupCopyMode.raw)
                    Text("Polished").tag(CleanupCopyMode.polished)
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Copy mode for history rows")
            } header: {
                Text("History")
            } footer: {
                Text("Raw = unedited ASR. Polished = post-cleanup.")
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

    /// Binding into the cross-platform CleanupCopyMode.current
    /// (UserDefaults.standard, key `cleanupCopyMode`).
    private var copyModeBinding: Binding<CleanupCopyMode> {
        Binding(
            get: { CleanupCopyMode.current },
            set: { CleanupCopyMode.current = $0 }
        )
    }


}
