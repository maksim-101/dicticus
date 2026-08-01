import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// A model representing a single replacement entry for the SwiftUI Table.
struct DictionaryEntry: Identifiable, Hashable {
    let id: String // Use the 'original' string as the unique ID
    var original: String
    var replacement: String
    var createdAt: Date
    var source: LexiconSource
}

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

/// A window view for managing the custom dictionary find-replace pairs.
struct DictionaryView: View {
    @EnvironmentObject var dictionaryService: DictionaryService
    @State private var entries: [DictionaryEntry] = []
    @State private var selection: Set<DictionaryEntry.ID> = []
    
    @State private var sortMode: DictionarySortMode = .mostRecent
    @State private var isShowingRemoveAllConfirmation = false
    @State private var duplicateWarning: String? = nil
    
    @State private var newOriginal: String = ""
    @State private var newReplacement: String = ""
    @State private var isShowingAddRow = false

    // In-place edit state (quick task 260801-ftf). `editingOriginal` is the
    // dictionary key currently being edited (the pre-edit "Original" string);
    // nil means the inline form is in Add mode.
    @State private var editingOriginal: String? = nil

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
        VStack(spacing: 0) {
            // Header / Toolbar
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    Text("Case Sensitive")
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                    Toggle("", isOn: $dictionaryService.isCaseSensitive)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .scaleEffect(0.6) // Smaller scale to match button heights and reduce border thickness
                        .frame(width: 32, height: 20)
                }
                .padding(.leading, 16)

                Spacer()

                Text("\(dictionaryService.dictionary.count) \(dictionaryService.dictionary.count == 1 ? "entry" : "entries")")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Spacer()

                Picker("", selection: $sortMode) {
                    ForEach(DictionarySortMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
                .controlSize(.regular)
                .padding(.trailing, 16)
            }
            .frame(height: 50)
            .background(.ultraThinMaterial)

            Divider()

            // Main Table
            Table(entries, selection: $selection) {
                TableColumn("Original (ASR Error)") { entry in
                    Text(entry.original)
                        .font(.system(size: 13))
                }
                TableColumn("Replacement") { entry in
                    Text(entry.replacement)
                        .font(.system(size: 13))
                }
            }
            .tableStyle(.inset)
            .contextMenu {
                Button("Edit…") {
                    beginEdit()
                }
                .disabled(selection.count != 1)
                Button("Delete") {
                    deleteSelected()
                }
                .disabled(selection.isEmpty)
            }

            // Duplicate Warning
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

            // Footer / Actions
            HStack(spacing: 12) {
                if isShowingAddRow {
                    HStack(spacing: 8) {
                        TextField("Original error", text: $newOriginal)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.regular)
                            .font(.system(size: 13))
                            .onChange(of: newOriginal) { _, newValue in
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    checkForDuplicate(newValue)
                                }
                            }
                        
                        Image(systemName: "arrow.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        TextField("Replacement", text: $newReplacement)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.regular)
                            .font(.system(size: 13))

                        Button(editingOriginal != nil ? "Save" : "Add") {
                            if editingOriginal != nil {
                                saveEdit()
                            } else {
                                addEntry()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .disabled(newOriginal.isEmpty || duplicateWarning != nil)

                        Button("Cancel") {
                            cancelAdd()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                    }
                } else {
                    Button(action: {
                        withAnimation(.spring(response: 0.3)) {
                            isShowingAddRow = true
                        }
                    }) {
                        Label("Add Entry", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)

                    Button("Edit") {
                        beginEdit()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(selection.count != 1)

                    Spacer()

                    Button("Delete Selected") {
                        deleteSelected()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(selection.isEmpty)

                    Button("Remove All") {
                        isShowingRemoveAllConfirmation = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .foregroundStyle(.red)

                    Divider()
                        .frame(height: 20)

                    Menu {
                        Button("Export as CSV") { exportDictionary(format: "csv") }
                        Button("Export as JSON") { exportDictionary(format: "json") }
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)

                    Button(action: { showImportPanel() }) {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
            }
            .font(.system(size: 13))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)

            Divider()

            // Starter Packs (Phase 31-03)
            VStack(alignment: .leading, spacing: 8) {
                Text("Starter Packs")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(DictionaryService.StarterPack.allCases, id: \.self) { pack in
                        let imported = importedPacks.contains(pack)
                        Button(action: { importStarterPack(pack) }) {
                            Label(pack.displayTitle, systemImage: imported ? "checkmark.circle.fill" : "tray.and.arrow.down")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .tint(imported ? .green : nil)
                        .help(imported ? "All entries from this pack are already in your dictionary" : "Import this pack")
                    }
                }

                Text("The dictionary starts empty by design so no personal data ships in the public app. Grow it three ways: add entries manually above, tap a starter pack to import curated corrections in one click, or import a CSV file. You can also ask an AI (ChatGPT, Claude, etc.) to generate a CSV for your field — e.g. \"Give me 50 common medical dictation mishearings as original,replacement CSV\" — then import it here.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)

            Divider()

            // Spoken Punctuation Reference (Phase 32 D-07)
            // DisclosureGroup keeps this within the fixed-height window (the VStack
            // does not scroll); expanded content scrolls internally so it can never
            // clip off-window. Mirrors the iOS tap-to-reveal NavigationLink.
            DisclosureGroup {
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
                        LabeledContent("semicolon", value: ";")
                        LabeledContent("at sign / Klammeraffe", value: "@")
                        LabeledContent("hash / Raute", value: "#")
                        LabeledContent("caret", value: "^")
                        LabeledContent("tilde", value: "~")
                    }
                    .font(.system(size: 12))

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
                        .padding(.bottom, 6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
            } label: {
                Text("Spoken Punctuation")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 14)
            .background(.ultraThinMaterial)

            Divider()

            // Voice Commands Reference (Phase 39 / D-09)
            // Sibling section to "Spoken Punctuation" above — same
            // fixed-height/internal-scroll discipline, same label styling.
            DisclosureGroup {
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
            } label: {
                Text("Voice Commands")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 14)
            .background(.ultraThinMaterial)
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

    private func refreshEntries() {
        let mapped = dictionaryService.dictionary.map {
            DictionaryEntry(id: $0.key, original: $0.key, replacement: $0.value.replacement, createdAt: $0.value.createdAt, source: $0.value.source)
        }

        switch sortMode {
        case .alphabetical:
            entries = mapped.sorted { $0.original.lowercased() < $1.original.lowercased() }
        case .mostRecent:
            // Sort by source priority first (user > imported > default), then most
            // recent createdAt within each group. This ensures the user's own entries
            // always surface at the top regardless of when default entries were stamped.
            entries = mapped.sorted {
                let pa = $0.source.sortPriority, pb = $1.source.sortPriority
                if pa != pb { return pa < pb }
                return $0.createdAt > $1.createdAt
            }
        }

        importedPacks = Set(DictionaryService.StarterPack.allCases.filter { dictionaryService.isStarterPackImported($0) })
    }

    private func checkForDuplicate(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != editingOriginal, dictionaryService.dictionary.keys.contains(trimmed) {
            duplicateWarning = "Entry '\(trimmed)' already exists."
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
        editingOriginal = nil
    }

    // MARK: - In-place editing (quick task 260801-ftf)

    private func beginEdit() {
        guard selection.count == 1, let id = selection.first,
              let entry = dictionaryService.dictionary[id] else { return }
        editingOriginal = id
        newOriginal = id
        newReplacement = entry.replacement
        duplicateWarning = nil
        withAnimation(.spring(response: 0.3)) {
            isShowingAddRow = true
        }
    }

    private func saveEdit() {
        guard let oldOriginal = editingOriginal else { return }
        let result = dictionaryService.renameEntry(from: oldOriginal, to: newOriginal, replacement: newReplacement)
        switch result {
        case .saved:
            selection.removeAll()
            isShowingAddRow = false
            newOriginal = ""
            newReplacement = ""
            duplicateWarning = nil
            editingOriginal = nil
            refreshEntries()
        case .collision(let key):
            duplicateWarning = "'\(key)' already exists — choose a different Original."
        case .invalid(let reason):
            duplicateWarning = reason
        case .notFound:
            duplicateWarning = "This entry no longer exists."
        }
    }

    private func deleteSelected() {
        for id in selection {
            dictionaryService.removeReplacement(for: id)
        }
        selection.removeAll()
        refreshEntries()
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
