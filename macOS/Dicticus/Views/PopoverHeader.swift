import SwiftUI
import AppKit
import KeyboardShortcuts

/// Persistent header row for the popover: wordmark and status (Ready / Recording… /
/// Needs Permission) on the left, History, Quit and Settings buttons on the right.
///
/// Per UI-SPEC §macOS — Persistent Header:
///   - Wordmark: "Dicticus" in `.headline`
///   - Gear button: 40×40pt, corner radius 10, Color.primary.opacity(0.07) idle / 0.14 hover,
///     1pt Color.primary.opacity(0.10) stroke, SF Symbol "gear" at 22pt.
///   - Accessibility label: "Settings (Command-Comma)"
///   - Spacing exception `phead`: 10pt top/bottom, 16pt leading, 12pt trailing.
///
/// Gear action uses Q-03 spike-locked mechanism B:
///   NSApp.activate(ignoringOtherApps: true) then openSettings().
///   The NSApp.activate call guards against the .accessory MenuBarExtra first-click
///   foreground pitfall documented in 35-RESEARCH (Pitfall 1).
struct PopoverHeader: View {

    @EnvironmentObject var permissionManager: PermissionManager
    @EnvironmentObject var hotkeyManager: HotkeyManager
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @Environment(\.closePopover) private var closePopover
    @State private var isHoveringGear = false
    @State private var isHoveringQuit = false
    @State private var isHoveringHistory = false

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Dicticus")
                    .font(.headline)

                status

                Spacer()

                Button {
                    openWindow(id: "history")
                    NSApp.activate(ignoringOtherApps: true)
                    closePopover()
                } label: {
                    Image(systemName: "clock")
                        .font(.system(size: 15))
                }
                .buttonStyle(.plain)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(isHoveringHistory ? 0.14 : 0.07))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                )
                .onHover { hovering in
                    isHoveringHistory = hovering
                }
                .accessibilityLabel("Open History")
                .help("Open the History window")

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                        .font(.system(size: 15))
                }
                .buttonStyle(.plain)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(isHoveringQuit ? 0.14 : 0.07))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                )
                .onHover { hovering in
                    isHoveringQuit = hovering
                }
                .accessibilityLabel("Quit Dicticus")
                .help("Quit Dicticus")

                Button {
                    // Q-03 spike-locked mechanism B (35-SPIKE-SETTINGS-OPEN.md):
                    // NSApp.activate guards the .accessory first-click foreground pitfall.
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                    closePopover()
                } label: {
                    Image(systemName: "gear")
                        .font(.system(size: 15))
                }
                .buttonStyle(.plain)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(isHoveringGear ? 0.14 : 0.07))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                )
                .onHover { hovering in
                    isHoveringGear = hovering
                }
                .accessibilityLabel("Settings (Command-Comma)")
                .help("Settings (⌘,)")
            }
            // The first button became first responder when the popover opened and kept a blue
            // focus ring.
            .focusEffectDisabled()
        }
        .padding(.top, 10)
        .padding(.bottom, 10)
        .padding(.leading, 16)
        .padding(.trailing, 12)
    }

    // MARK: - Status

    private var state: HotkeyDisplay.StatusState {
        if hotkeyManager.pipelineState == .recording { return .recording }
        if !permissionManager.allGranted || hotkeyManager.registrationFailed { return .needsPermission }
        return .ready
    }

    private var status: some View {
        let (color, word): (Color, String) = switch state {
        case .ready: (Color(hex: "#2BA471"), "Ready")
        case .recording: (Color(hex: "#E5484D"), "Recording…")
        case .needsPermission: (Color(hex: "#F5A524"), "Needs Permission")
        }
        return HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(word)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(color)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(HotkeyDisplay.voiceOverStatusLabel(
            state: state,
            plainStandard: KeyboardShortcuts.getShortcut(for: .plainDictation)?.description,
            cleanupStandard: KeyboardShortcuts.getShortcut(for: .aiCleanup)?.description
        ))
    }
}
