import SwiftUI

/// Root container for the ⌘, Settings window.
///
/// Presents 4 panes in order per UI-SPEC §macOS — Settings Window:
///   Hotkeys (keyboard) / AI Cleanup (sparkles) / General (gear) / About (info.circle)
///
/// Receives the same @EnvironmentObjects the popover uses, injected by the
/// Settings { } scene in DicticusApp.
struct SettingsRoot: View {
    @EnvironmentObject var permissionManager: PermissionManager
    @EnvironmentObject var warmupService: ModelWarmupService
    @EnvironmentObject var hotkeyManager: HotkeyManager
    @EnvironmentObject var modifierListener: ModifierHotkeyListener
    @EnvironmentObject var updater: SparkleUpdater

    var body: some View {
        TabView {
            HotkeysPane()
                .tabItem {
                    Label("Hotkeys", systemImage: "keyboard")
                }
                .accessibilityLabel("Hotkeys settings pane")

            AiCleanupPane()
                .tabItem {
                    Label("AI Cleanup", systemImage: "sparkles")
                }
                .accessibilityLabel("AI Cleanup settings pane")

            GeneralPane()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .accessibilityLabel("General settings pane")

            AboutPane()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .accessibilityLabel("About settings pane")
        }
        .frame(minWidth: 400)
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        .onAppear {
            // Stage Manager fix (Finding 5): notify the App that an auxiliary window
            // opened so it can promote to .regular activation policy.
            NotificationCenter.default.post(name: .dicticusAuxWindowOpened, object: nil)
        }
        .background(
            // WindowAccessor applies collectionBehavior and registers a willCloseNotification
            // observer that fires only on genuine window dismissal (not minimize), so the
            // activation-policy counter stays accurate when the user minimizes this window.
            WindowAccessor { window in
                window.collectionBehavior = [.managed, .moveToActiveSpace]
                NotificationCenter.default.addObserver(
                    forName: NSWindow.willCloseNotification,
                    object: window,
                    queue: .main
                ) { _ in
                    NotificationCenter.default.post(name: .dicticusAuxWindowClosed, object: nil)
                }
            }
        )
    }
}
