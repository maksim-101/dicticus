import SwiftUI

/// A reusable row component showing the status of a single macOS permission.
///
/// Displays:
/// - Status badge icon (checkmark/clock/xmark) with semantic color
/// - Permission name
/// - Status label ("Granted" / "Required" / "Denied")
/// - Action button: "Grant Access" for pending, "Repair in System Settings" for denied
struct PermissionRow: View {
    let title: String
    let status: PermissionStatus
    /// Called when the user taps "Grant Access" in the .pending state.
    let grantAction: () -> Void
    /// The System Settings pane to open when the permission is .denied.
    let settingsURL: URL
    /// If true, show a restart hint when denied (macOS kills audio subsystem on mic toggle).
    var showRestartHint: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: status.iconName)
                    .foregroundColor(status.color)
                    .frame(width: 16)

                Text(title)
                    .font(.body)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                Spacer()

                Text(status.label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: true, vertical: false)

                if status != .granted {
                    Button(status == .denied ? "Repair in System Settings" : "Grant Access") {
                        if status == .denied {
                            SystemSettingsURL.open(settingsURL)
                        } else {
                            grantAction()
                        }
                    }
                    .controlSize(.small)
                    .fixedSize(horizontal: true, vertical: false)
                }
            }

            // macOS kills the audio subsystem when mic permission is toggled —
            // the app must restart for changes to take effect.
            if showRestartHint && status == .denied {
                HStack(spacing: 4) {
                    Text("Restart required after granting")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Restart") {
                        Self.relaunchApp()
                    }
                    .controlSize(.mini)
                    .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.leading, 24)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    /// Relaunch the app by spawning a new process and terminating the current one.
    private static func relaunchApp() {
        let url = Bundle.main.bundleURL
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", url.path]
        try? task.run()
        // Small delay so the new instance starts before we quit
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApplication.shared.terminate(nil)
        }
    }
}
