import SwiftUI

/// Settings → About pane.
///
/// Shows Dicticus version, Check for Updates button (Sparkle), and Full Changelog link.
/// Relocates version/changelog block from SettingsSection + Check-for-Updates from
/// MenuBarView per UIORG-04 (bindings unchanged).
struct AboutPane: View {
    @EnvironmentObject var updater: SparkleUpdater

    var body: some View {
        Form {
            Section {
                LabeledContent("Dicticus") {
                    Text(AppBuildInfo.displayVersion)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Updates") {
                    Button("Check for Updates…") {
                        updater.checkForUpdates()
                    }
                    .disabled(!updater.canCheckForUpdates)
                }

                LabeledContent("Recent changes") {
                    Button("Full Changelog ›") {
                        NSWorkspace.shared.open(AppBuildInfo.releasesURL)
                    }
                    .buttonStyle(.link)
                }
            }

            Section("Recent Changes") {
                ForEach(AppBuildInfo.recentChanges, id: \.self) { note in
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}
