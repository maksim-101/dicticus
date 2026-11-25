import SwiftUI

/// Tab identifier for the manual popover tab switch (Q-04 fallback); History opens its
/// window from the header's clock button.
enum PopoverTab: String, CaseIterable {
    case home
    case dictionary
}

extension EnvironmentValues {
    /// Closes the menu bar popover; MenuBarExtra has no dismiss of its own, and a popover
    /// left open covers the window it just opened.
    @Entry var closePopover: () -> Void = {}
}

/// Root container for the menu bar popover (replaces monolithic MenuBarView).
///
/// Architecture per RESEARCH Pattern 1 (Q-04 fallback):
///   - Fixed-height 348×320pt surface — ONE explicit frame, never per-pane (Pitfall 2).
///   - Manual @State-driven tab switch using Group { switch } — NOT a native TabView.
///   - Always opens to Home (Discretion default; tab is not persisted across opens).
///   - Lifecycle re-attached here (Pitfall 3): startPolling / loadOnboardingState fire on
///     every popover open via .onAppear. (The synchronous mdfind probe that used to run here
///     blocked the main thread whenever Spotlight stalled; removed 2026-10-17.)
///
/// The onboarding gate still routes to OnboardingView when hasCompletedOnboarding is false,
/// matching MenuBarView behaviour (lines 32–34).
struct PopoverRoot: View {
    @EnvironmentObject var permissionManager: PermissionManager
    @EnvironmentObject var warmupService: ModelWarmupService
    @EnvironmentObject var hotkeyManager: HotkeyManager
    @EnvironmentObject var modifierListener: ModifierHotkeyListener
    @EnvironmentObject var updater: SparkleUpdater
    @Environment(\.openWindow) private var openWindow

    @State private var tab: PopoverTab = .home
    @State private var showOnboarding = false
    @State private var panel: NSWindow?

    var body: some View {
        VStack(spacing: 0) {
            if showOnboarding {
                OnboardingView(isPresented: $showOnboarding)
                    .environmentObject(permissionManager)
            } else {
                PopoverHeader()

                Divider()

                Group {
                    switch tab {
                    case .home:
                        HomePane()
                    case .dictionary:
                        DictionaryPane()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipped()

                Divider()

                CustomTabBar(selection: $tab)
            }
        }
        // One size on every tab, and nothing scrolls: a height that changes
        // between tabs is distracting.
        .frame(width: 348, height: 320)
        // Half-strength window colour over the system glass, so less of what lies behind shows
        // through (DESIGN.md's popover exception).
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        .background(WindowAccessor { panel = $0 })
        .environment(\.closePopover, { [panel] in panel?.close() })
        .onAppear {
            // Start permission polling so changes in System Settings are detected live.
            permissionManager.startPolling()

            // Load persisted onboarding state and show flow if not yet completed.
            permissionManager.loadOnboardingState()

            if !permissionManager.hasCompletedOnboarding {
                showOnboarding = true
            }
        }
    }
}
