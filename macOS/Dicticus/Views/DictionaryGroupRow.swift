import SwiftUI

/// One row of the Manage Dictionary window: a correct spelling and its heard forms as chips
/// (slice 52, mockup `dictionary-rows` variant A).
struct DictionaryGroupRow: View {
    @EnvironmentObject var dictionaryService: DictionaryService
    let group: DictionaryService.DictionaryGroup
    @Binding var renamingSpelling: String?
    var onMessage: (String?) -> Void
    /// The removed entries and a line describing them, for the window's Undo.
    var onRemoved: ([String: DictionaryMetadata], String) -> Void = { _, _ in }

    @State private var isAdding = false
    @State private var newForm = ""
    @State private var pendingMove: String? = nil
    @State private var renameText = ""
    @FocusState private var addFocused: Bool
    @FocusState private var renameFocused: Bool

    static let spellingColumnWidth: CGFloat = 160

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            spellingCell
                .frame(width: Self.spellingColumnWidth, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                WrappingLayout {
                    ForEach(group.forms, id: \.self) { form in
                        chip(form)
                    }
                    if isAdding {
                        TextField("heard form", text: $newForm)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                            .frame(width: 140)
                            .focused($addFocused)
                            .onSubmit(addForm)
                            .onExitCommand(perform: cancelAdd)
                    } else {
                        Button {
                            isAdding = true
                            addFocused = true
                        } label: {
                            Text("+").font(.system(size: 12))
                                .padding(.horizontal, 8)
                                .overlay(Capsule().strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [3])))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                        .help("Add a heard form for \(group.spelling)")
                    }
                }
                if let pendingMove {
                    Text("'\(pendingMove)' already becomes '\(dictionaryService.dictionary[dictionaryService.existingKey(for: pendingMove) ?? ""]?.replacement ?? "")'. Press Return again to move it here.")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 4)
        .onChange(of: renamingSpelling) { _, value in
            if value == group.spelling {
                renameText = group.spelling
                renameFocused = true
            }
        }
    }

    @ViewBuilder private var spellingCell: some View {
        if renamingSpelling == group.spelling {
            TextField("Correct spelling", text: $renameText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, weight: .semibold))
                .focused($renameFocused)
                .onSubmit(rename)
                .onExitCommand { renamingSpelling = nil; onMessage(nil) }
        } else {
            // The double-click is the List's primary action (DictionaryView); a tap gesture
            // here swallowed the clicks inside the selectable List (F1g).
            Text(group.spelling)
                .font(.system(size: 13, weight: .semibold))
                .help("Double-click to change the spelling for all its heard forms")
        }
    }

    private func chip(_ form: String) -> some View {
        let everyday = dictionaryService.isEverydayWord(form)
        return HStack(spacing: 4) {
            Text(form).font(.system(size: 12))
            Button {
                onRemoved(dictionaryService.removeHeardForm(form), "Removed “\(form)” from \(group.spelling).")
            } label: {
                Image(systemName: "xmark").font(.system(size: 8, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Remove '\(form)'")
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .padding(.vertical, 1)
        .background(Capsule().fill(Color.secondary.opacity(everyday ? 0.0 : 0.1)))
        .background(Capsule().fill(Color.orange.opacity(everyday ? 0.1 : 0.0)))
        .overlay(Capsule().strokeBorder(everyday ? Color.orange : Color.secondary.opacity(0.25), lineWidth: 1))
        .help(everyday ? "'\(form)' is an everyday word: this entry changes every '\(form)' you dictate." : "")
    }

    private func addForm() {
        let form = newForm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !form.isEmpty else { cancelAdd(); return }
        if let key = dictionaryService.existingKey(for: form),
           dictionaryService.dictionary[key]?.replacement != group.spelling,
           pendingMove != form {
            pendingMove = form
            return
        }
        switch dictionaryService.addHeardForm(form, to: group.spelling) {
        case .saved: cancelAdd(); onMessage(nil)
        case .invalid(let reason): onMessage(reason)
        case .collision(let key): onMessage("'\(key)' already exists.")
        case .notFound: onMessage("This word no longer exists.")
        }
    }

    private func cancelAdd() {
        isAdding = false
        newForm = ""
        pendingMove = nil
        onMessage(nil)
    }

    private func rename() {
        switch dictionaryService.renameSpelling(from: group.spelling, to: renameText) {
        case .saved: renamingSpelling = nil; onMessage(nil)
        case .invalid(let reason): onMessage(reason)
        case .collision(let key): onMessage("'\(key)' already exists.")
        case .notFound: renamingSpelling = nil; onMessage("This word no longer exists.")
        }
    }
}
