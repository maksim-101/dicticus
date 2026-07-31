import SwiftUI

/// Three-state tab identifier for the manual popover tab switch (Q-04 fallback).
enum PopoverTab: String, CaseIterable {
    case home
    case dictionary
    case history
}

/// Root container for the menu bar popover (replaces monolithic MenuBarView).
///
/// Architecture per RESEARCH Pattern 1 (Q-04 fallback):
///   - Fixed-height 348×320pt surface — ONE explicit frame, never per-pane (Pitfall 2).
///   - Manual @State-driven tab switch using Group { switch } — NOT a native TabView.
///   - Always opens to Home (Discretion default; tab is not persisted across opens).
///   - Lifecycle re-attached here (Pitfall 3): startPolling / loadOnboardingState /
///     checkMultipleInstalls fire on every popover open via .onAppear.
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
                    case .history:
                        HistoryPane()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                Divider()

                CustomTabBar(selection: $tab)
            }
        }
        .frame(width: 348, height: 320)
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        .onAppear {
            // Start permission polling so changes in System Settings are detected live.
            permissionManager.startPolling()

            // Load persisted onboarding state and show flow if not yet completed.
            permissionManager.loadOnboardingState()

            // Launch-only mdfind probe for stale Dicticus.app copies on disk.
            permissionManager.checkMultipleInstalls()

            if !permissionManager.hasCompletedOnboarding {
                showOnboarding = true
            }
        }
    }
}
