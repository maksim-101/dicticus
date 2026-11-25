import SwiftUI

/// Dictionary pane of the popover: the add form is always shown, with the cursor in "Heard as"
/// when the tab opens (board popover-dictionary-and-history, variant B), and a
/// line with the entry count and a link to the full dictionary window.
///
/// Import / Export remain in the full manager window only, to keep the popover's fixed
/// 348 × 320 pt size.
struct DictionaryPane: View {

    @Environment(\.openWindow) private var openWindow
    @Environment(\.closePopover) private var closePopover

    @ObservedObject private var dictionaryService = DictionaryService.shared

    @State private var heardText = ""
    @State private var replaceText = ""
    @State private var refusal: String?
    @State private var confirmation: String?
    /// The input the "already becomes" line was shown for; a second Save of it goes through.
    @State private var warnedInput: String?
    @FocusState private var heardFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Teach Dicticus a word: what it heard, and how it should be written.")
                .font(.system(size: 12))
                .foregroundStyle(Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 10)

            VStack(alignment: .leading, spacing: 8) {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                    GridRow {
                        Text("Heard as")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.secondary)
                            .gridColumnAlignment(.trailing)
                        TextField("e.g. mirror cove", text: $heardText)
                            .textFieldStyle(.roundedBorder)
                            .focused($heardFocused)
                            .accessibilityLabel("Heard as")
                    }
                    GridRow {
                        Text("Correct spelling")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.secondary)
                        TextField("e.g. Miracove", text: $replaceText)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { if canSave { save() } }
                            .accessibilityLabel("Correct spelling")
                    }
                }
                .font(.system(size: 13))
                .onChange(of: heardText) { _, _ in inputChanged() }
                .onChange(of: replaceText) { _, _ in inputChanged() }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let refusal {
                        Text(refusal)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if let confirmation {
                        Text(confirmation)
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    Button("Save", action: save)
                        .buttonStyle(.borderedProminent)
                        .disabled(!canSave)
                        .accessibilityLabel("Save dictionary entry")
                }
            }
            .padding(.horizontal, 16)

            Spacer(minLength: 0)

            Divider()

            HStack {
                let count = dictionaryService.dictionary.count
                Text("\(count) \(count == 1 ? "entry" : "entries")")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary)
                Spacer()
                Button("Open Full Dictionary…") {
                    openDictionaryWindow()
                }
                .buttonStyle(.link)
                .font(.system(size: 12))
                .accessibilityLabel("Open full dictionary manager")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { heardFocused = true }
    }

    private var canSave: Bool {
        let heard = heardText.trimmingCharacters(in: .whitespacesAndNewlines)
        let spelling = replaceText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !heard.isEmpty && !spelling.isEmpty && heard != spelling
    }

    private func inputChanged() {
        refusal = nil
        warnedInput = nil
        if !heardText.isEmpty || !replaceText.isEmpty { confirmation = nil }
    }

    private func save() {
        let input = "\(heardText)\u{0}\(replaceText)"
        let heard = heardText.trimmingCharacters(in: .whitespacesAndNewlines)
        let spelling = replaceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let existing = dictionaryService.existingKey(for: heardText)
        if let existing, dictionaryService.dictionary[existing]?.replacement == spelling {
            // Saving it again still makes a built-in entry the user's own, as the window's add does.
            if dictionaryService.dictionary[existing]?.source == .default {
                _ = dictionaryService.addHeardForm(heardText, to: replaceText)
            }
            refusal = nil
            confirmation = "Already in the dictionary: “\(existing)” → “\(spelling)”."
            heardText = ""
            replaceText = ""
            heardFocused = true
        } else if warnedInput != input,
           let key = existing,
           let current = dictionaryService.dictionary[key]?.replacement, current != spelling {
            refusal = "'\(key)' already becomes '\(current)'. Save again to replace it."
            warnedInput = input
        } else if case .invalid(let reason) = dictionaryService.addHeardForm(heardText, to: replaceText) {
            refusal = reason
        } else {
            heardText = ""
            replaceText = ""
            refusal = nil
            warnedInput = nil
            confirmation = "Added: “\(heard)” → “\(spelling)”."
            heardFocused = true
        }
    }

    private func openDictionaryWindow() {
        openWindow(id: "dictionary")
        NSApp.activate(ignoringOtherApps: true)
        closePopover()
    }
}
