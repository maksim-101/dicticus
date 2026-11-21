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
    @ObservedObject var notificationService = NotificationService.shared

    // Used by the hotkey-registration-failed branch to open the Settings window (Hotkeys pane).
    @Environment(\.openSettings) private var openSettings
    @Environment(\.closePopover) private var closePopover

    // Re-render the subline whenever a standard hotkey binding changes.
    @State private var shortcutChangeToken: AnyObject? = nil
    @State private var sublineText: String = ""
    /// Which dictation the card shows: 0 is the last one, "‹ earlier" counts up.
    @State private var cardIndex = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                statusBlock
                    .padding(16)

                if let notice = notificationService.unreadNotice {
                    noticeRow(for: notice)
                }

                Divider()
                    .padding(.horizontal, 16)

                lastTranscriptionSection
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
            }
        }
        .onAppear {
            cardIndex = 0
            refreshSubline()
            observeShortcutChanges()
        }
        // Re-render when Fn-combo bindings change (already @Published on modifierListener).
        .onChange(of: modifierListener.plainDictationCombo) { _, _ in refreshSubline() }
        .onChange(of: modifierListener.cleanupCombo) { _, _ in refreshSubline() }
        // Phase 50-09 (D-02 gap): closing the popover or leaving the Home tab marks the
        // notice read — the next press also clears it (HotkeyManager.handleKeyDown).
        .onDisappear {
            notificationService.unreadNotice = nil
        }
    }

    // MARK: - Notice row (Phase 50-09, D-02 gap)

    /// In-app notice surface: does not depend on Notification Center delivery, which a Focus
    /// mode the app cannot observe may silently suppress (50-GATE-DIFF.md §7).
    @ViewBuilder
    private func noticeRow(for notice: DicticusNotification) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Color(hex: "#F5A524"))
            VStack(alignment: .leading, spacing: 2) {
                Text(notice.message)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if notificationService.authorizationStatus == .denied {
                    Text("Notifications are off for Dicticus \u{2014} System Settings \u{2192} Notifications.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Notice: \(notice.message)")
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
                                closePopover()
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

    // MARK: - Last dictation card (slice 52 criterion 10, mockup `pointer-r2` A)

    private var cardEntry: TranscriptionEntry? {
        historyService.entries.indices.contains(cardIndex) ? historyService.entries[cardIndex] : nil
    }

    @ViewBuilder
    private var lastTranscriptionSection: some View {
        if let entry = cardEntry {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    Text(cardIndex == 0 ? "Last dictation" : "Earlier dictation")
                        .font(.caption.weight(.semibold))
                    Text("· \(entry.createdAt.formatted(date: .omitted, time: .shortened)) · \(entry.language.uppercased())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("‹ earlier") { cardIndex += 1 }
                        .disabled(cardIndex + 1 >= historyService.entries.count)
                        .help("Show the dictation before this one")
                    if cardIndex > 0 {
                        Button("›") { cardIndex -= 1 }
                            .help("Show the next dictation")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                FixWordView(text: entry.text)
                    .environmentObject(DictionaryService.shared)

                CopyToClipboardButton(text: entry.text)
                    .controlSize(.small)
            }
            .padding(10)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1))
        } else {
            Text("No recent dictation.")
                .font(.body)
                .foregroundStyle(Color.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
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
        Button(showCopied ? "Copied!" : "Copy") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            showCopied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                showCopied = false
            }
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Copy to Clipboard: \(text.prefix(40))")
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
