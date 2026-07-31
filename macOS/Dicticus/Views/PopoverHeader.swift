import SwiftUI
import AppKit

/// Persistent header row for the popover: wordmark on the left, gear button on the right.
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

    @EnvironmentObject var hotkeyManager: HotkeyManager
    @Environment(\.openSettings) private var openSettings
    @State private var isHoveringGear = false
    @State private var isHoveringQuit = false

    /// Phase 38 Plan 04 (D-10): the live-resolution label text, e.g.
    /// "Auto · Code" when the pin is Auto and the resolver currently
    /// resolves to `.code`, or just "Code" when the pin itself is Code
    /// (the pin already IS the answer — no "Auto ·" prefix needed).
    private var resolutionLabelText: String {
        let resolved = hotkeyManager.liveResolvedContext()
        if hotkeyManager.contextPin == nil {
            return "Auto · \(resolved.rawValue.capitalized)"
        }
        return resolved.rawValue.capitalized
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Dicticus")
                    .font(.headline)

                Spacer()

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

            // Phase 38 Plan 04 (D-09/D-10, CTXFMT-03): session-scoped
            // Auto/Code/Prose/Default pin + live-resolution readout.
            // `contextPin` is a plain in-memory @Published on HotkeyManager
            // (shared EnvironmentObject) — never persisted, resets to Auto
            // on relaunch.
            HStack {
                Picker("Formatting context", selection: $hotkeyManager.contextPin) {
                    Text("Auto").tag(DictationContext?.none)
                    Text("Code").tag(DictationContext?.some(.code))
                    Text("Prose").tag(DictationContext?.some(.prose))
                    Text("Default").tag(DictationContext?.some(.default))
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .accessibilityLabel("Formatting context")

                Spacer()

                Text(resolutionLabelText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Current resolution: \(resolutionLabelText)")
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 10)
        .padding(.leading, 16)
        .padding(.trailing, 12)
    }
}
