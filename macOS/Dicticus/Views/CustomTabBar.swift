import SwiftUI

/// Manual bottom tab bar for the popover (Q-04 fallback — native TabView clips inside MenuBarExtra).
///
/// Renders three equal-width tab buttons (Home / Dictionary / History). Selected tab is tinted
/// with AccentColor; unselected tabs use `.secondary`. Respects Reduce Motion: the selection
/// change animation is suppressed when the user has enabled Reduce Motion in System Settings.
///
/// The selection-tint idiom mirrors the iPad sidebar in ContentView.swift (lines 17–24).
struct CustomTabBar: View {

    @Binding var selection: PopoverTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 0) {
                tabButton(.home,       "Home",       "mic")
                tabButton(.dictionary, "Dictionary", "book")
                tabButton(.history,    "History",    "clock")
            }
            .background(Color(NSColor.windowBackgroundColor))
        }
    }

    @ViewBuilder
    private func tabButton(_ tab: PopoverTab, _ label: String, _ symbol: String) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .default) {
                selection = tab
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 16))
                Text(label)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 9)
            .padding(.bottom, 7)
            .contentShape(Rectangle())
            .foregroundStyle(selection == tab ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) tab")
    }
}
