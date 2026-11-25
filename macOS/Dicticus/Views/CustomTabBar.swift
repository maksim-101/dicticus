import SwiftUI

/// Manual bottom tab bar for the popover (Q-04 fallback — native TabView clips inside MenuBarExtra).
///
/// Renders equal-width tab buttons (Home / Dictionary). Selected tab is tinted
/// with AccentColor; unselected tabs use `.secondary`. The switch is not animated: during the
/// cross-fade a focused text field of the old pane stayed drawn over the new one.
///
/// The selection-tint idiom mirrors the iPad sidebar in ContentView.swift (lines 17–24).
struct CustomTabBar: View {

    @Binding var selection: PopoverTab

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 0) {
                tabButton(.home,       "Home",       "mic")
                tabButton(.dictionary, "Dictionary", "book")
            }
            .background(Color(NSColor.windowBackgroundColor))
        }
    }

    @ViewBuilder
    private func tabButton(_ tab: PopoverTab, _ label: String, _ symbol: String) -> some View {
        Button {
            selection = tab
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
