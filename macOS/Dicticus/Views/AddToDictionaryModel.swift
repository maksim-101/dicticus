import SwiftUI

/// What fixing a word shows and does, apart from its layout: join note, warnings, save
/// and Undo (used by `FixWordView`). Kept out of the view so tests can drive it.
@MainActor
final class AddToDictionaryModel: ObservableObject {
    @Published var heard: String
    @Published var correct: String = ""
    let service: DictionaryService

    /// The key, its state before the last save and what the save wrote, for Undo.
    private(set) var undoState: (key: String, previous: DictionaryMetadata?, written: DictionaryMetadata?)? = nil

    init(heard: String, service: DictionaryService) {
        self.heard = heard
        self.service = service
    }

    private var trimmedHeard: String { heard.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedCorrect: String { correct.trimmingCharacters(in: .whitespacesAndNewlines) }

    var note: String {
        guard !trimmedCorrect.isEmpty else { return "" }
        let count = service.dictionary.values.filter { $0.replacement == trimmedCorrect }.count
        if count == 0 {
            // The existing-key warning already says an entry changes; "new word" would contradict it.
            return service.existingKey(for: trimmedHeard) == nil ? "New word in the dictionary." : ""
        }
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
        if let reason = spellingClashReason {
            result.append(reason)
        }
        return result
    }

    private var spellingClashReason: String? {
        guard !trimmedCorrect.isEmpty else { return nil }
        return service.spellingClashReason(trimmedCorrect, allowed: [service.existingKey(for: trimmedHeard) ?? trimmedHeard])
    }

    var canAdd: Bool {
        !trimmedHeard.isEmpty && !trimmedCorrect.isEmpty && trimmedHeard != trimmedCorrect && spellingClashReason == nil
    }

    /// Saves and returns the confirmation line, or nil when nothing was saved.
    func save() -> String? {
        guard canAdd else { return nil }
        let h = trimmedHeard, c = trimmedCorrect
        let key = service.existingKey(for: h) ?? h
        let previous = service.dictionary[key]
        guard service.addHeardForm(h, to: c) == .saved else { return nil }
        undoState = (key, previous, service.dictionary[key])
        return "Added: “\(h)” → “\(c)”. Applies from your next dictation."
    }

    @discardableResult
    func undo() -> Bool {
        guard let state = undoState else { return false }
        undoState = nil
        guard service.dictionary[state.key] == state.written else { return false }
        service.restoreEntry(state.key, to: state.previous)
        return true
    }
}
