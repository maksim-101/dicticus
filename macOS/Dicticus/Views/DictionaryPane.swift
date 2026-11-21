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
    @Environment(\.closePopover) private var closePopover

    /// Entry count from the shared DictionaryService for the section header badge.
    @ObservedObject private var dictionaryService = DictionaryService.shared

    @State private var showingAddForm = false
    @State private var heardText = ""
    @State private var replaceText = ""
    @State private var refusal: String?

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
                // One row of fields keeps the form inside the fixed popover height (F1b).
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        TextField("Heard as", text: $heardText)
                            .textFieldStyle(.roundedBorder)
                        Image(systemName: "arrow.right")
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                        TextField("Correct spelling", text: $replaceText)
                            .textFieldStyle(.roundedBorder)
                    }
                    .font(.subheadline)

                    HStack(spacing: 8) {
                        Button("Save") {
                            if case .invalid(let reason) = dictionaryService.addHeardForm(heardText, to: replaceText) {
                                refusal = reason
                            } else {
                                collapseForm()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canSave)
                        .accessibilityLabel("Save dictionary entry")

                        Button("Cancel") {
                            collapseForm()
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Cancel adding entry")
                    }

                    if let refusal {
                        Text(refusal)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
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

                if !showingAddForm {
                    Text("Open the full dictionary to browse, edit, import/export, and add starter packs.")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 12)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var canSave: Bool {
        let heard = heardText.trimmingCharacters(in: .whitespacesAndNewlines)
        let spelling = replaceText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !heard.isEmpty && !spelling.isEmpty && heard != spelling
    }

    private func collapseForm() {
        heardText = ""
        replaceText = ""
        refusal = nil
        showingAddForm = false
    }

    private func openDictionaryWindow() {
        openWindow(id: "dictionary")
        NSApp.activate(ignoringOtherApps: true)
        closePopover()
    }
}
