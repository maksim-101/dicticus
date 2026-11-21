import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum DictionarySortMode: String, CaseIterable, Identifiable {
    case alphabetical = "A-Z"
    case mostRecent = "Recent"
    
    var id: String { self.rawValue }
    var displayName: String {
        switch self {
        case .alphabetical: return "A-Z"
        case .mostRecent: return "Recent"
        }
    }
}

enum DictionaryTab: String, CaseIterable, Identifiable {
    case entries = "Entries"
    case spokenPunctuation = "Spoken Punctuation"
    case voiceCommands = "Voice Commands"

    var id: String { rawValue }
}

/// A window view for managing the custom dictionary find-replace pairs.
struct DictionaryView: View {
    @EnvironmentObject var dictionaryService: DictionaryService
    @State private var groups: [DictionaryService.DictionaryGroup] = []
    /// Selected rows, by spelling (slice 52).
    @State private var selection: Set<String> = []
    @State private var renamingSpelling: String? = nil
    @State private var tab: DictionaryTab = .entries
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    /// The last removal, offered for Undo until the next one (F1f).
    @State private var pendingUndo: (message: String, entries: [String: DictionaryMetadata])? = nil

    @State private var sortMode: DictionarySortMode = .mostRecent
    @State private var isShowingRemoveAllConfirmation = false
    @State private var duplicateWarning: String? = nil
    
    @State private var newOriginal: String = ""
    @State private var newReplacement: String = ""
    @State private var isShowingAddRow = false

    // Import / Export state (Phase 31-02)
    @State private var importResult: String? = nil
    @State private var isShowingImportResult = false
    @State private var isShowingMergeStrategyPicker = false
    // quick task 260801-ftf: the file is read into memory at pick time (inside
    // the security scope) and the parse preview is computed BEFORE the merge
    // dialog ever opens, replacing the old pendingImportURL + late-read design.
    @State private var pendingImportData: Data? = nil
    @State private var pendingImportFormat: String = "csv"
    @State private var pendingImportPreview: DictionaryIOService.ImportPreview? = nil
    @State private var isShowingReplaceAllConfirmation = false

    // Starter pack state (Phase 31-03)
    @State private var starterPackResult: String? = nil
    @State private var isShowingStarterPackResult = false
    @State private var importedPacks: Set<DictionaryService.StarterPack> = []

    private let spokenPunctuationColumns = [
        GridItem(.flexible(), spacing: 16, alignment: .leading),
        GridItem(.flexible(), spacing: 16, alignment: .leading),
    ]

    var body: some View {
        // Each tab fills the whole window and scrolls itself; the reference sections no
        // longer share a non-scrolling stack with the list (criterion 12, ends F1j).
        Group {
            switch tab {
            case .entries: entriesPage
            case .spokenPunctuation: referencePage("Spoken Punctuation") { spokenPunctuationContent }
            case .voiceCommands: referencePage("Voice Commands") { voiceCommandsContent }
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("", selection: $tab) {
                    ForEach(DictionaryTab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
        .frame(minWidth: 550, minHeight: 600)
        .navigationTitle("Custom Dictionary")
        .alert("Remove All Entries?", isPresented: $isShowingRemoveAllConfirmation) {
            Button("Remove All", role: .destructive) {
                dictionaryService.removeAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete all dictionary entries? This cannot be undone.")
        }
        .onAppear {
            refreshEntries()
            // Stage Manager fix (Finding 5): notify the App that an auxiliary window
            // opened so it can promote to .regular activation policy.
            NotificationCenter.default.post(name: .dicticusAuxWindowOpened, object: nil)
        }
        .background(
            // WindowAccessor applies collectionBehavior and registers a willCloseNotification
            // observer that fires only on genuine window dismissal (not minimize), so the
            // activation-policy counter stays accurate when the user minimizes this window.
            WindowAccessor { window in
                window.collectionBehavior = [.managed, .moveToActiveSpace]
                NotificationCenter.default.addObserver(
                    forName: NSWindow.willCloseNotification,
                    object: window,
                    queue: .main
                ) { _ in
                    NotificationCenter.default.post(name: .dicticusAuxWindowClosed, object: nil)
                }
            }
        )
        .onChange(of: dictionaryService.dictionary) { _, _ in
            refreshEntries()
        }
        .onChange(of: sortMode) { _, _ in
            refreshEntries()
        }
        .alert("Import Result", isPresented: $isShowingImportResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importResult ?? "")
        }
        .alert("Starter Pack Imported", isPresented: $isShowingStarterPackResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(starterPackResult ?? "")
        }
        .confirmationDialog("Choose Merge Strategy", isPresented: $isShowingMergeStrategyPicker, titleVisibility: .visible) {
            Button("Merge — keep mine on conflicts") {
                performImport(strategy: .existingWins)
            }
            .keyboardShortcut(.defaultAction)
            Button("Merge — use imported on conflicts") {
                performImport(strategy: .incomingWins)
            }
            Button("Replace All (delete current, then import)", role: .destructive) {
                requestReplaceAll()
            }
            Button("Cancel", role: .cancel) { pendingImportData = nil; pendingImportPreview = nil }
        } message: {
            Text(mergeDialogMessage)
        }
        .alert("Replace All Entries?", isPresented: $isShowingReplaceAllConfirmation) {
            Button("Delete \(pendingImportPreview?.deletedByReplaceAll ?? 0) and Replace", role: .destructive) {
                performImport(strategy: .replaceAll)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete \(pendingImportPreview?.deletedByReplaceAll ?? 0) \((pendingImportPreview?.deletedByReplaceAll ?? 0) == 1 ? "entry" : "entries") not present in this file. This cannot be undone.")
        }
    }

    // MARK: - Entries tab (mockup `dictionary-window-r2`, variant B)

    private var visibleGroups: [DictionaryService.DictionaryGroup] {
        DictionaryService.filter(groups, query: query)
    }

    private var countLine: String {
        let forms = dictionaryService.dictionary.count
        let formsText = "\(forms) heard \(forms == 1 ? "form" : "forms")"
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(groups.count) \(groups.count == 1 ? "word" : "words") · \(formsText)"
        }
        let shown = visibleGroups
        let shownForms = shown.reduce(0) { $0 + $1.forms.count }
        return "\(shown.count) of \(groups.count) words · \(shownForms) heard \(shownForms == 1 ? "form" : "forms")"
    }

    private var entriesPage: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                searchField
                    .frame(maxWidth: 260)
                Spacer()
                Text(countLine)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Picker("", selection: $sortMode) {
                    ForEach(DictionarySortMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 120)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            Text("Dicticus replaces a heard form with its correct spelling in every dictation.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)

            Divider()

            // One row per correct spelling, heard forms as chips (slice 52, mockup
            // `dictionary-rows` variant A). A List, not a Table: chip rows wrap onto
            // further lines, which Table rows do not size for.
            HStack(spacing: 16) {
                Text("Correct spelling")
                    .frame(width: DictionaryGroupRow.spellingColumnWidth, alignment: .leading)
                Text("Heard as")
                Spacer()
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 24)
            .padding(.vertical, 4)

            List(visibleGroups, selection: $selection) { group in
                DictionaryGroupRow(group: group, renamingSpelling: $renamingSpelling, onMessage: { message in
                    withAnimation(.easeInOut(duration: 0.2)) { duplicateWarning = message }
                }, onRemoved: offerUndo)
                .tag(group.spelling)
            }
            .listStyle(.inset)
            .alternatingRowBackgrounds()
            // Delete Selected acts only on rows the search leaves visible.
            .onChange(of: query) { _, _ in
                selection.formIntersection(Set(visibleGroups.map(\.spelling)))
            }
            .overlay {
                if visibleGroups.isEmpty && !groups.isEmpty {
                    Text("No word or heard form contains “\(query.trimmingCharacters(in: .whitespacesAndNewlines))”.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .contextMenu(forSelectionType: String.self) { items in
                Button("Rename…") {
                    renamingSpelling = items.first
                }
                .disabled(items.count != 1)
                Button("Delete") {
                    deleteGroups(items)
                }
                .disabled(items.isEmpty)
            } primaryAction: { items in
                if items.count == 1 { renamingSpelling = items.first }
            }

            if let undo = pendingUndo {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.secondary)
                    Text(undo.message)
                    Button("Undo") {
                        dictionaryService.restoreEntries(undo.entries)
                        pendingUndo = nil
                    }
                    .buttonStyle(.link)
                }
                .font(.system(size: 12))
                .padding(.vertical, 4)
                .transition(.opacity)
            }

            if let warning = duplicateWarning {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(warning)
                }
                .font(.system(size: 12))
                .foregroundStyle(.orange)
                .padding(.vertical, 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Divider()

            footer
                .font(.system(size: 13))
                .controlSize(.regular)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search entries", text: $query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onExitCommand { query = "" }
            if query.isEmpty {
                Text("⌘F")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            } else {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear the search")
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(searchFocused ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: searchFocused ? 2 : 1))
        .background(
            Button("") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .hidden()
        )
    }

    @ViewBuilder private var footer: some View {
        HStack(spacing: 12) {
            if isShowingAddRow {
                TextField("Heard as", text: $newOriginal)
                    .textFieldStyle(.roundedBorder)
                    .help("Matching ignores case — except a single all-uppercase heard form (e.g. HEY), which only matches when dictated in capitals.")
                    .onChange(of: newOriginal) { _, newValue in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            checkForDuplicate(newValue)
                        }
                    }

                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("Correct spelling", text: $newReplacement)
                    .textFieldStyle(.roundedBorder)

                Button("Add") {
                    addEntry()
                }
                .buttonStyle(.borderedProminent)
                .disabled(trimmedNewOriginal.isEmpty || trimmedNewReplacement.isEmpty || trimmedNewReplacement == trimmedNewOriginal || duplicateWarning != nil)

                Button("Cancel") {
                    cancelAdd()
                }
                .buttonStyle(.bordered)
            } else {
                Menu {
                    Button("Add Entry…") {
                        duplicateWarning = nil
                        withAnimation(.spring(response: 0.3)) {
                            isShowingAddRow = true
                        }
                    }
                    Button("Import CSV…") { showImportPanel() }
                    Menu("Starter Packs") {
                        ForEach(DictionaryService.StarterPack.allCases, id: \.self) { pack in
                            Button {
                                importStarterPack(pack)
                            } label: {
                                if importedPacks.contains(pack) {
                                    Label(pack.displayTitle, systemImage: "checkmark")
                                } else {
                                    Text(pack.displayTitle)
                                }
                            }
                        }
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .fixedSize()

                Button("Edit") {
                    renamingSpelling = selection.first
                }
                .buttonStyle(.bordered)
                .disabled(selection.count != 1)

                Spacer()

                Button("Delete Selected") {
                    deleteSelected()
                }
                .buttonStyle(.bordered)
                .disabled(selection.isEmpty)

                Button("Remove All") {
                    isShowingRemoveAllConfirmation = true
                }
                .buttonStyle(.bordered)
                .foregroundStyle(.red)

                Menu {
                    Button("Export as CSV") { exportDictionary(format: "csv") }
                    Button("Export as JSON") { exportDictionary(format: "json") }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .fixedSize()
            }
        }
    }

    // MARK: - Reference tabs

    private func referencePage<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
    }

    private var spokenPunctuationContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Always")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: spokenPunctuationColumns, alignment: .leading, spacing: 4) {
                LabeledContent("hyphen / Bindestrich", value: "-")
                LabeledContent("slash / Schrägstrich", value: "/")
                LabeledContent("backslash", value: "\\")
                LabeledContent("underscore / Unterstrich", value: "_")
                LabeledContent("asterisk / Sternchen", value: "*")
                LabeledContent("at sign / Klammeraffe", value: "@")
                LabeledContent("hash / Raute", value: "#")
                LabeledContent("caret", value: "^")
                LabeledContent("tilde", value: "~")
            }
            .font(.system(size: 12))

            Text("Hyphen, slash, backslash and underscore become a symbol only between two content words, e.g. \"file hyphen name\". They stay words at the start or end of a dictation, next to a comma or other punctuation, after \"a\", \"the\", \"this\", \"that\" or \"use\" or a German article, and next to a small grammar word such as \"and\", \"in\", \"it\", \"also\" or \"auch\", so a pair like \"and slash or\" stays as spoken, e.g. \"the hyphen key\" or \"der Bindestrich\".")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Between identifier words")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            LazyVGrid(columns: spokenPunctuationColumns, alignment: .leading, spacing: 4) {
                LabeledContent("minus", value: "-")
                LabeledContent("dot", value: ".")
                LabeledContent("colon", value: ":")
                LabeledContent("dollar", value: "$")
            }
            .font(.system(size: 12))

            Text("Conditional symbols collapse only when flanked by identifier-shaped words (e.g. \"Claude minus ops\" → \"Claude-ops\"). \"dot\" also collapses between number-words (\"ten dot five\" → \"10.5\").")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Punctuation commands")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            LazyVGrid(columns: spokenPunctuationColumns, alignment: .leading, spacing: 4) {
                LabeledContent("open / close parenthesis · Klammer auf / zu", value: "( )")
                LabeledContent("open / close square bracket · eckige Klammer auf / zu", value: "[ ]")
                LabeledContent("dot dot dot · Punkt Punkt Punkt", value: "...")
                LabeledContent("question mark · Fragezeichen", value: "?")
                LabeledContent("exclamation mark · Ausrufezeichen", value: "!")
                LabeledContent("new line · neue Zeile / Zeilenumbruch", value: "line break")
                LabeledContent("semicolon", value: ";")
            }
            .font(.system(size: 12))

            Text("Also works word-first, e.g. \"parentheses open\" and \"parentheses closed\". A command, \"semicolon\" included, stays as words after a word such as \"a\", \"the\", \"like\", \"or\" or \"and\" (\"a new line of chairs\"); question and exclamation marks only count when they close a sentence. Works with and without AI Cleanup.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 6)
        }
    }

    private var voiceCommandsContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("English")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: spokenPunctuationColumns, alignment: .leading, spacing: 4) {
                LabeledContent("scratch that", value: "deletes the last sentence")
                LabeledContent("scratch the last sentence", value: "deletes the last sentence")
                LabeledContent("ignore the last sentence", value: "deletes the last sentence")
                LabeledContent("forget the last sentence", value: "deletes the last sentence")
                LabeledContent("scratch the last word", value: "deletes the last word")
                LabeledContent("ignore the last word", value: "deletes the last word")
            }
            .font(.system(size: 12))

            Text("German")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            LazyVGrid(columns: spokenPunctuationColumns, alignment: .leading, spacing: 4) {
                LabeledContent("ignoriere den letzten Satz", value: "deletes the last sentence")
                LabeledContent("ignorier den letzten Satz", value: "deletes the last sentence")
                LabeledContent("vergiss den letzten Satz", value: "deletes the last sentence")
                LabeledContent("streich das", value: "deletes the last sentence")
                LabeledContent("streiche das", value: "deletes the last sentence")
                LabeledContent("ignoriere das letzte Wort", value: "deletes the last word")
                LabeledContent("vergiss das letzte Wort", value: "deletes the last word")
                LabeledContent("streich das letzte Wort", value: "deletes the last word")
                LabeledContent("streiche das letzte Wort", value: "deletes the last word")
            }
            .font(.system(size: 12))

            Text("A command only counts when it stands alone at a clause boundary — at the start of what you're saying, or right after a period or comma. If you keep talking in the same breath (e.g. \"I told him to scratch that idea\"), it's treated as ordinary dictated words, not a command. Voice Commands work in AI Cleanup mode only, and can be turned off in Settings → AI Cleanup.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 6)
        }
    }

    private var mergeDialogMessage: String {
        var lines = ["You have \(dictionaryService.dictionary.count) entries."]
        if let p = pendingImportPreview {
            lines.append("The file has \(p.fileCount) \(p.fileCount == 1 ? "entry" : "entries") — \(p.newCount) new, \(p.conflictCount) conflicting.")
            if p.skippedCount > 0 {
                lines.append("\(p.skippedCount) \(p.skippedCount == 1 ? "row" : "rows") in the file will be skipped (empty or identical original/replacement).")
            }
        }
        lines.append("\"Conflicts\" are entries whose Original appears in both.")
        return lines.joined(separator: " ")
    }

    private var trimmedNewOriginal: String { newOriginal.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedNewReplacement: String { newReplacement.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func refreshEntries() {
        let mapped = DictionaryService.groups(of: dictionaryService.dictionary)

        switch sortMode {
        case .alphabetical:
            groups = mapped.sorted { $0.spelling.localizedCaseInsensitiveCompare($1.spelling) == .orderedAscending }
        case .mostRecent:
            // Sort by source priority first (user > imported > default), then most
            // recent createdAt within each group. This ensures the user's own entries
            // always surface at the top regardless of when default entries were stamped.
            groups = mapped.sorted {
                let pa = $0.source.sortPriority, pb = $1.source.sortPriority
                if pa != pb { return pa < pb }
                if $0.newestCreatedAt != $1.newestCreatedAt { return $0.newestCreatedAt > $1.newestCreatedAt }
                return $0.spelling < $1.spelling
            }
        }
        selection.formIntersection(Set(groups.map(\.spelling)))

        importedPacks = Set(DictionaryService.StarterPack.allCases.filter { dictionaryService.isStarterPackImported($0) })
    }

    private func checkForDuplicate(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let key = dictionaryService.existingKey(for: trimmed) {
            duplicateWarning = "'\(key)' already becomes '\(dictionaryService.dictionary[key]?.replacement ?? "")'."
        } else {
            duplicateWarning = nil
        }
    }

    private func addEntry() {
        dictionaryService.setReplacement(for: newOriginal, with: newReplacement)
        newOriginal = ""
        newReplacement = ""
        isShowingAddRow = false
        duplicateWarning = nil
        refreshEntries()
    }

    private func cancelAdd() {
        isShowingAddRow = false
        newOriginal = ""
        newReplacement = ""
        duplicateWarning = nil
    }

    private func deleteSelected() {
        deleteGroups(selection)
    }

    private func deleteGroups(_ spellings: Set<String>) {
        let removed = dictionaryService.removeGroups(spellings: spellings)
        selection.subtract(spellings)
        refreshEntries()
        let what = spellings.count == 1 ? "“\(spellings.first!)”" : "\(spellings.count) words"
        offerUndo(removed, "Deleted \(what) and \(removed.count) heard \(removed.count == 1 ? "form" : "forms").")
    }

    private func offerUndo(_ entries: [String: DictionaryMetadata], _ message: String) {
        guard !entries.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.2)) { pendingUndo = (message, entries) }
    }

    // MARK: - Starter Packs (Phase 31-03)

    private func importStarterPack(_ pack: DictionaryService.StarterPack) {
        let result = dictionaryService.importStarterPack(pack)
        starterPackResult = result.summaryMessage(source: pack.displayTitle)
        isShowingStarterPackResult = true
    }

    // MARK: - Import / Export (Phase 31-02)

    private func exportDictionary(format: String) {
        let data = dictionaryService.exportData(format: format)
        let ext = format.lowercased()
        let panel = NSSavePanel()
        panel.allowedContentTypes = ext == "json" ? [.json] : [.commaSeparatedText]
        let dateStamp = ISO8601DateFormatter().string(from: Date()).prefix(10)
        panel.nameFieldStringValue = "Dicticus-dictionary-\(dateStamp).\(ext)"
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
    }

    private func showImportPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            importResult = "Could not read file."
            isShowingImportResult = true
            return
        }
        let format = url.pathExtension.lowercased()

        switch dictionaryService.previewImport(data, format: format) {
        case .failure(let message):
            importResult = "Import failed: \(message)"
            isShowingImportResult = true
        case .preview(let preview):
            pendingImportData = data
            pendingImportFormat = format
            pendingImportPreview = preview
            // Nothing to conflict with on an empty dictionary — skip the merge prompt.
            if dictionaryService.dictionary.isEmpty {
                performImport(strategy: .incomingWins)
            } else {
                isShowingMergeStrategyPicker = true
            }
        }
    }

    /// Replace All is gated behind a second confirmation whenever it would
    /// delete entries not present in the file (T-ftf-03). When nothing would
    /// be lost, import proceeds directly.
    private func requestReplaceAll() {
        if (pendingImportPreview?.deletedByReplaceAll ?? 0) > 0 {
            isShowingReplaceAllConfirmation = true
        } else {
            performImport(strategy: .replaceAll)
        }
    }

    private func performImport(strategy: MergeStrategy) {
        guard let data = pendingImportData else { return }
        let result = dictionaryService.importData(data, format: pendingImportFormat, strategy: strategy)
        importResult = result.summaryMessage()
        isShowingImportResult = true
        pendingImportData = nil
        pendingImportPreview = nil
    }
}
