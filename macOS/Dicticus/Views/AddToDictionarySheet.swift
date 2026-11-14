import SwiftUI

/// What the "Add to Dictionary" sheet shows and does, apart from its layout (slice 52,
/// mockup `history-pick` variant A). Kept out of the view so tests can drive it.
@MainActor
final class AddToDictionaryModel: ObservableObject, Identifiable {
    @Published var heard: String
    @Published var correct: String = ""
    let service: DictionaryService

    /// The key and its state before the last save, for Undo.
    private(set) var undoState: (key: String, previous: DictionaryMetadata?)? = nil

    init(heard: String, service: DictionaryService) {
        self.heard = heard
        self.service = service
    }

    private var trimmedHeard: String { WordPick.trimmed(heard) }
    private var trimmedCorrect: String { correct.trimmingCharacters(in: .whitespacesAndNewlines) }

    var note: String {
        guard !trimmedCorrect.isEmpty else { return "" }
        let count = service.dictionary.values.filter { $0.replacement == trimmedCorrect }.count
        if count == 0 { return "New word in the dictionary." }
        return "Joins “\(trimmedCorrect)”, which has \(count) heard \(count == 1 ? "form" : "forms")."
    }

    var warnings: [String] {
        let h = trimmedHeard
        guard !h.isEmpty else { return [] }
        var result: [String] = []
        if service.isEverydayWord(h) {
            result.append("“\(h)” is an everyday word. This entry would change every “\(h)” you dictate, also where you mean \(h).")
        }
        if let key = service.existingKey(for: h), let current = service.dictionary[key]?.replacement, current != trimmedCorrect {
            result.append("“\(key)” is already in the dictionary and becomes “\(current)”. Adding it here changes that entry to “\(trimmedCorrect.isEmpty ? "…" : trimmedCorrect)”.")
        }
        return result
    }

    var canAdd: Bool {
        !trimmedHeard.isEmpty && !trimmedCorrect.isEmpty && trimmedHeard != trimmedCorrect
    }

    var spellings: [String] {
        Array(Set(service.dictionary.values.map(\.replacement))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Saves and returns the confirmation line, or nil when nothing was saved.
    func save() -> String? {
        guard canAdd else { return nil }
        let h = trimmedHeard, c = trimmedCorrect
        let key = service.existingKey(for: h) ?? h
        let previous = service.dictionary[key]
        guard service.addHeardForm(h, to: c) == .saved else { return nil }
        undoState = (key, previous)
        return "Added: “\(h)” → “\(c)”. Applies from your next dictation."
    }

    func undo() {
        guard let state = undoState else { return }
        service.restoreEntry(state.key, to: state.previous)
        undoState = nil
    }
}

struct AddToDictionarySheet: View {
    @ObservedObject var model: AddToDictionaryModel
    var onDone: (String?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add to Dictionary").font(.headline)

            Text("Heard as").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            TextField("Heard as", text: $model.heard)
                .textFieldStyle(.roundedBorder)
                .labelsHidden()

            Text("Correct spelling").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                TextField("Type how it should be written", text: $model.correct)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .onSubmit(save)
                Menu {
                    ForEach(model.spellings, id: \.self) { spelling in
                        Button(spelling) { model.correct = spelling }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(model.spellings.isEmpty)
                .help("Pick a spelling already in the dictionary")
            }
            Text(model.note)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minHeight: 14, alignment: .leading)

            ForEach(model.warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.1)))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.orange, lineWidth: 1))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onDone(nil) }
                    .keyboardShortcut(.cancelAction)
                Button("Add", action: save)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canAdd)
            }
            .padding(.top, 8)
        }
        .padding(24)
        .frame(width: 380)
    }

    private func save() {
        if let confirmation = model.save() { onDone(confirmation) }
    }
}
