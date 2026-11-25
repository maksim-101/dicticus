import SwiftUI
import KeyboardShortcuts

/// Settings → Hotkeys pane.
///
/// UIORG-02 consolidation: merges the two formerly-separate hotkey config blocks
/// (HotkeySettingsView standard recorders + SettingsSection modifier pickers) into
/// one Settings pane with two labeled groups per UI-SPEC §Pane: Hotkeys.
///
/// Group 1 "Standard hotkeys — any keyboard": KeyboardShortcuts.Recorder rows.
/// Group 2 "Modifier hotkeys — Mac keyboard with Fn": Fn combo Pickers + Re-register.
struct HotkeysPane: View {
    @EnvironmentObject var hotkeyManager: HotkeyManager
    @EnvironmentObject var modifierListener: ModifierHotkeyListener

    var body: some View {
        Form {
            Section("Standard hotkeys — any keyboard") {
                LabeledContent("Plain Dictation") {
                    KeyboardShortcuts.Recorder(for: .plainDictation)
                }
                .accessibilityLabel("Plain Dictation hotkey recorder")

                LabeledContent("AI Cleanup") {
                    KeyboardShortcuts.Recorder(for: .aiCleanup)
                }
                .accessibilityLabel("AI Cleanup hotkey recorder")

                LabeledContent("Revert to Raw") {
                    KeyboardShortcuts.Recorder(for: .revertToRaw)
                }
                .accessibilityLabel("Revert to Raw hotkey recorder")

                Text("Pastes the original unedited dictation, replacing the last AI-cleaned paste.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Plain Dictation") {
                    Picker("", selection: $modifierListener.plainDictationCombo) {
                        ForEach(ModifierCombo.allCases) { combo in
                            Text(combo.displayName).tag(combo)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .accessibilityLabel("Plain dictation modifier hotkey")
                }

                LabeledContent("AI Cleanup") {
                    Picker("", selection: $modifierListener.cleanupCombo) {
                        ForEach(ModifierCombo.allCases) { combo in
                            Text(combo.displayName).tag(combo)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .accessibilityLabel("AI Cleanup modifier hotkey")
                }

                HStack {
                    Text("If a hotkey stops firing after reinstall, re-register.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Re-register") {
                        hotkeyManager.reregisterAll()
                    }
                    .controlSize(.small)
                }

                Text("Fn-based hotkeys require a Mac keyboard with an Fn key. Standard hotkeys above work on all keyboards.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Modifier hotkeys — Mac keyboard with Fn")
            }
        }
        .formStyle(.grouped)
    }
}
