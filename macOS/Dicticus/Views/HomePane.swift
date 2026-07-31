import SwiftUI
import KeyboardShortcuts

/// Home pane of the popover: live status block + last transcription (D-06, D-07).
///
/// Status block maps the pipeline + permission state to exactly three visual states:
///   Ready / Recording… / Needs Permission (color-independent: dot + headline + glow ring all change).
///
/// The hotkey subline is produced by HotkeyDisplay.hotkeySubline (Plan 35-01) and
/// re-renders on every KeyboardShortcuts rebind via NotificationCenter observation.
/// Fn-combos from @EnvironmentObject modifierListener already republish via @Published.
///
/// Degraded-state block (D-12/13/14): when Needs Permission, shows one PermissionRow per
/// missing permission, each with its own correct System Settings deep link. When all TCC
/// permissions are granted but hotkey registration failed, shows a distinct hotkey message.
struct HomePane: View {

    @EnvironmentObject var permissionManager: PermissionManager
    @EnvironmentObject var hotkeyManager: HotkeyManager
    @EnvironmentObject var modifierListener: ModifierHotkeyListener
    @ObservedObject var historyService = HistoryService.shared

    // Used by the hotkey-registration-failed branch to open the Settings window (Hotkeys pane).
    @Environment(\.openSettings) private var openSettings

    // Re-render the subline whenever a standard hotkey binding changes.
    @State private var shortcutChangeToken: AnyObject? = nil
    @State private var sublineText: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                statusBlock
                    .padding(16)

                Divider()
                    .padding(.horizontal, 16)

                lastTranscriptionSection
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
            }
        }
        .onAppear {
            refreshSubline()
            observeShortcutChanges()
        }
        // Re-render when Fn-combo bindings change (already @Published on modifierListener).
        .onChange(of: modifierListener.plainDictationCombo) { _, _ in refreshSubline() }
        .onChange(of: modifierListener.cleanupCombo) { _, _ in refreshSubline() }
    }

    // MARK: - Status block

    private var statusBlock: some View {
        let state = derivedState
        let (dotColor, glowColor, glowOpacity, headline) = stateVisuals(for: state)
        let needsPermission = (state == .needsPermission)

        return Group {
            if needsPermission {
                // D-12/D-13/D-14: per-missing-permission rows with correct deep links,
                // or distinct hotkey-registration message when all TCC is granted.
                VStack(alignment: .leading, spacing: 0) {
                    statusContent(
                        dotColor: dotColor,
                        glowColor: glowColor,
                        glowOpacity: glowOpacity,
                        headline: headline
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(voiceOverLabel(for: state))

                    // D-14: all TCC granted but hotkey registration failed
                    if permissionManager.allGranted && hotkeyManager.registrationFailed {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Hotkey registration failed.")
                                .font(.body)
                                .foregroundStyle(.primary)
                            Text("Another app may be using the same key combination. Open Hotkeys settings to reassign.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Open Hotkeys Settings") {
                                NSApp.activate(ignoringOtherApps: true)
                                openSettings()
                            }
                            .controlSize(.small)
                            .accessibilityLabel("Open Hotkeys Settings to reassign key combination")
                        }
                        .padding(.top, 8)
                    } else {
                        // D-12: one PermissionRow per MISSING permission, fixed order
                        VStack(alignment: .leading, spacing: 8) {
                            if permissionManager.microphoneStatus != .granted {
                                PermissionRow(
                                    title: "Microphone",
                                    status: permissionManager.microphoneStatus,
                                    grantAction: { Task { await permissionManager.requestMicrophone() } },
                                    settingsURL: SystemSettingsURL.microphone,
                                    showRestartHint: true
                                )
                            }
                            if permissionManager.accessibilityStatus != .granted {
                                PermissionRow(
                                    title: "Accessibility",
                                    status: permissionManager.accessibilityStatus,
                                    grantAction: { permissionManager.requestAccessibility() },
                                    settingsURL: SystemSettingsURL.accessibility,
                                    showRestartHint: false
                                )
                            }
                        }
                        .padding(.top, 8)
                    }
                }
            } else {
                statusContent(
                    dotColor: dotColor,
                    glowColor: glowColor,
                    glowOpacity: glowOpacity,
                    headline: headline
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(voiceOverLabel(for: state))
            }
        }
    }

    @ViewBuilder
    private func statusContent(
        dotColor: Color,
        glowColor: Color,
        glowOpacity: Double,
        headline: String
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(glowColor.opacity(glowOpacity))
                    .frame(width: 20, height: 20)
                Circle()
                    .fill(dotColor)
                    .frame(width: 12, height: 12)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(.headline)
                    .foregroundStyle(dotColor)

                Text(sublineText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.secondary)
            }
        }
    }

    // MARK: - Last Transcription

    @ViewBuilder
    private var lastTranscriptionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LAST TRANSCRIPTION")
                .font(.caption)
                .foregroundStyle(Color.secondary)

            if let text = hotkeyManager.lastTranscriptionText, !text.isEmpty {
                Text(text)
                    .font(.body)
                    .foregroundStyle(Color.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    CopyToClipboardButton(text: text)
                        .frame(maxWidth: .infinity)
                    RevertToRawButton(entry: historyService.entries.first)
                        .frame(maxWidth: .infinity)
                }
            } else {
                Text("No recent transcription.")
                    .font(.body)
                    .foregroundStyle(Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    Button("Copy to Clipboard") {}
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                        .disabled(true)
                        .accessibilityLabel("Copy to Clipboard")
                    RevertToRawButton(entry: historyService.entries.first)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: - State derivation

    private enum StatusState: Equatable {
        case ready
        case recording
        case needsPermission
    }

    private var derivedState: StatusState {
        if hotkeyManager.pipelineState == .recording {
            return .recording
        }
        if !permissionManager.allGranted || hotkeyManager.registrationFailed {
            return .needsPermission
        }
        return .ready
    }

    private func stateVisuals(for state: StatusState) -> (dotColor: Color, glowColor: Color, glowOpacity: Double, headline: String) {
        switch state {
        case .ready:
            return (Color(hex: "#2BA471"), Color(hex: "#2BA471"), 0.16, "Ready")
        case .recording:
            return (Color(hex: "#E5484D"), Color(hex: "#E5484D"), 0.18, "Recording…")
        case .needsPermission:
            return (Color(hex: "#F5A524"), Color(hex: "#F5A524"), 0.16, "Needs Permission")
        }
    }

    // MARK: - Accessibility label

    private func voiceOverLabel(for state: StatusState) -> String {
        let hotkeyState: HotkeyDisplay.StatusState
        switch state {
        case .ready:         hotkeyState = .ready
        case .recording:     hotkeyState = .recording
        case .needsPermission: hotkeyState = .needsPermission
        }
        let (plain, cleanup) = resolvedShortcutDescriptions()
        return HotkeyDisplay.voiceOverStatusLabel(
            state: hotkeyState,
            plainStandard: plain,
            cleanupStandard: cleanup
        )
    }

    // MARK: - Subline helpers

    private func refreshSubline() {
        let (plain, cleanup) = resolvedShortcutDescriptions()
        sublineText = HotkeyDisplay.hotkeySubline(
            plainStandard: plain,
            cleanupStandard: cleanup
        )
    }

    private func resolvedShortcutDescriptions() -> (plain: String?, cleanup: String?) {
        let plain = KeyboardShortcuts.getShortcut(for: .plainDictation)?.description
        let cleanup = KeyboardShortcuts.getShortcut(for: .aiCleanup)?.description
        return (plain, cleanup)
    }

    private func observeShortcutChanges() {
        // RESEARCH "Don't Hand-Roll": observe KeyboardShortcuts' own change notification
        // so the subline re-renders on rebind without polling or parsing UserDefaults.
        let token = NotificationCenter.default.addObserver(
            forName: .init("KeyboardShortcuts_shortcutByNameDidChange"),
            object: nil,
            queue: .main
        ) { [self] _ in
            // Capture is safe: this closure is dispatched on main queue and HomePane
            // is a value type — Swift captures a copy, so no retain cycle.
            refreshSubline()
        }
        shortcutChangeToken = token as AnyObject
    }
}

// MARK: - CopyToClipboardButton

/// Full-width bordered-prominent copy button with a transient "Copied!" label.
private struct CopyToClipboardButton: View {

    let text: String
    @State private var showCopied = false

    var body: some View {
        Button(showCopied ? "Copied!" : "Copy to Clipboard") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            showCopied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                showCopied = false
            }
        }
        .buttonStyle(.borderedProminent)
        .accessibilityLabel("Copy to Clipboard: \(text.prefix(40))")
    }
}

// MARK: - RevertToRawButton

/// Secondary (.bordered) button that re-pastes the raw ASR text of the last
/// dictation via TextInjector, with a transient "Reverted!" label — mirrors
/// CopyToClipboardButton's @State + asyncAfter pattern (R-06 / CLEANRD-02).
private struct RevertToRawButton: View {

    let entry: TranscriptionEntry?
    @State private var showReverted = false

    var body: some View {
        let decision = RevertToRawState.evaluate(entry: entry)

        Button {
            Task {
                await revertToRaw()
                showReverted = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    showReverted = false
                }
            }
        } label: {
            Label(showReverted ? "Reverted!" : "Revert to Raw", systemImage: "arrow.uturn.backward")
        }
        .buttonStyle(.bordered)
        .disabled(!decision.enabled)
        .help(decision.help)
        .accessibilityLabel("Revert to Raw")
    }
}

// MARK: - Color(hex:) helper (local, macOS only)

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: Double
        switch hex.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255
            g = Double((int >> 8)  & 0xFF) / 255
            b = Double(int         & 0xFF) / 255
        default:
            r = 0; g = 0; b = 0
        }
        self.init(red: r, green: g, blue: b)
    }
}
