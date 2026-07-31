import SwiftUI

/// Dictionary pane of the popover: inline quick-add form + link to full manager.
///
/// "+ Add Entry" reveals an inline form (Heard / Replace with fields + Save/Cancel)
/// directly in the popover without opening the full manager window. On Save, the
/// entry is written via DictionaryService.shared.setReplacement and the form collapses.
///
/// Import / Export remain in the full manager window only — they are not surfaced here
/// to keep the popover height budget (Q-04, 320pt fixed) intact.
struct DictionaryPane: View {

    @Environment(\.openWindow) private var openWindow

    /// Entry count from the shared DictionaryService for the section header badge.
    @ObservedObject private var dictionaryService = DictionaryService.shared

    @State private var showingAddForm = false
    @State private var heardText = ""
    @State private var replaceText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header with entry count badge
            HStack {
                Text("Custom Dictionary")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                    .textCase(.uppercase)

                Spacer()

                let count = dictionaryService.dictionary.count
                Text("\(count) \(count == 1 ? "entry" : "entries")")
                    .font(.caption2)
                    .foregroundStyle(Color.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            if showingAddForm {
                // Inline add-entry form — fits within the fixed popover height
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Heard (original)", text: $heardText)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)

                    TextField("Replace with", text: $replaceText)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)

                    HStack(spacing: 8) {
                        Button("Save") {
                            let original = heardText.trimmingCharacters(in: .whitespacesAndNewlines)
                            let replacement = replaceText.trimmingCharacters(in: .whitespacesAndNewlines)
                            DictionaryService.shared.setReplacement(for: original, with: replacement)
                            collapseForm()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(heardText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("Save dictionary entry")

                        Button("Cancel") {
                            collapseForm()
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Cancel adding entry")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            } else {
                // Default action area
                VStack(alignment: .leading, spacing: 8) {
                    Button("+ Add Entry") {
                        showingAddForm = true
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Add dictionary entry")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }

            Divider()

            // Manage Full Dictionary link + description
            VStack(alignment: .leading, spacing: 6) {
                Button("Manage Full Dictionary…") {
                    openDictionaryWindow()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Open full dictionary manager")

                Text("Open the full dictionary to browse, edit, import/export, and add starter packs.")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 12)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func collapseForm() {
        heardText = ""
        replaceText = ""
        showingAddForm = false
    }

    private func openDictionaryWindow() {
        openWindow(id: "dictionary")
        NSApp.activate(ignoringOtherApps: true)
    }
}
