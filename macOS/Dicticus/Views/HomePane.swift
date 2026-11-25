import SwiftUI

/// Home pane of the popover: the last dictation card (D-06). The status word is in the
/// popover header, and the hotkey line left Home.
///
/// Degraded-state block (D-12/13/14): when Needs Permission, shows one PermissionRow per
/// missing permission, each with its own correct System Settings deep link. When all TCC
/// permissions are granted but hotkey registration failed, shows a distinct hotkey message.
struct HomePane: View {

    @EnvironmentObject var permissionManager: PermissionManager
    @EnvironmentObject var hotkeyManager: HotkeyManager
    @ObservedObject var historyService: HistoryService
    @ObservedObject var notificationService = NotificationService.shared

    // Used by the hotkey-registration-failed branch to open the Settings window (Hotkeys pane).
    @Environment(\.openSettings) private var openSettings
    @Environment(\.closePopover) private var closePopover
    @Environment(\.openWindow) private var openWindow

    /// Which dictation the card shows: 0 is the last one, the ‹ chevron counts up.
    @State private var cardIndex = 0

    /// `historyService` is a seam for the popover-size test.
    init(historyService: HistoryService = .shared) {
        self.historyService = historyService
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if needsPermission {
                permissionBlock
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                Divider()
                    .padding(.horizontal, 16)
            }

            if let notice = notificationService.unreadNotice {
                noticeRow(for: notice)
            }

            lastTranscriptionSection
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 12)
        }
        .onAppear {
            cardIndex = 0
        }
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

    // MARK: - Permission block

    /// The status word itself is in the popover header; Home lists what is missing (D-12/13/14).
    @ViewBuilder
    private var permissionBlock: some View {
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
        } else {
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
        }
    }

    private var needsPermission: Bool {
        !permissionManager.allGranted || hotkeyManager.registrationFailed
    }

    // MARK: - Last dictation card

    private var cardEntry: TranscriptionEntry? {
        historyService.entries.indices.contains(cardIndex) ? historyService.entries[cardIndex] : nil
    }

    @ViewBuilder
    private var lastTranscriptionSection: some View {
        if let entry = cardEntry {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 4) {
                    Text(cardIndex == 0 ? "Last Dictation" : "Earlier Dictation")
                        .font(.caption.weight(.semibold))
                    Text("· \(entry.createdAt.formatted(date: .omitted, time: .shortened)) · \(entry.language.uppercased())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    ControlGroup {
                        Button { cardIndex += 1 } label: { Label("Earlier dictation", systemImage: "chevron.left").labelStyle(.iconOnly) }
                            .disabled(cardIndex + 1 >= historyService.entries.count)
                            .help("Show the dictation before this one")
                        Button { cardIndex -= 1 } label: { Label("Later dictation", systemImage: "chevron.right").labelStyle(.iconOnly) }
                            .disabled(cardIndex == 0)
                            .help("Show the next dictation")
                    }
                    .controlSize(.small)
                    .fixedSize()
                }

                // With a permission missing, the card gives up its text to stay inside the popover.
                if !needsPermission {
                    FixWordView(text: entry.text, maxLines: 4)
                        .environmentObject(DictionaryService.shared)
                }

                // Copy is the common action, so it is the only filled button (board B).
                HStack(spacing: 8) {
                    Button("Fix a word…") {
                        FixWordRequest.open(entry, with: openWindow)
                        closePopover()
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
                    .help("Open the dictation in a larger window to mark a misheard word")
                    Spacer()
                    CopyToClipboardButton(text: entry.text)
                }
            }
            .padding(12)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        } else {
            Text("No recent dictation.")
                .font(.body)
                .foregroundStyle(Color.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - CopyToClipboardButton

/// Prominent copy button with a transient "Copied!" label.
private struct CopyToClipboardButton: View {

    let text: String
    @State private var showCopied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            showCopied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                showCopied = false
            }
        } label: {
            Label(showCopied ? "Copied!" : "Copy", systemImage: showCopied ? "checkmark" : "doc.on.doc")
                .frame(minWidth: 90)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .accessibilityLabel("Copy to Clipboard: \(text.prefix(40))")
    }
}

// MARK: - Color(hex:) helper (macOS only; also used by PopoverHeader)

extension Color {
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
