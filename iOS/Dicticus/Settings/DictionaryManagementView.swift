import SwiftUI
import UniformTypeIdentifiers

/// FileDocument wrapper for .fileExporter (Phase 31-02).
struct PlainTextDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText, .json, .plainText] }
    var text: String
    init(_ text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        text = String(data: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? ""
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

private struct AddEntrySheet: View {
    @Binding var original: String
    @Binding var replacement: String
    let duplicateWarning: String?
    /// nil = Add mode; non-nil (the pre-edit original) = Edit mode. Drives
    /// the navigation title and confirm-button label (quick task 260801-ftf).
    let editingOriginal: String?
    let onConfirm: () -> Void
    let onCancel: () -> Void
    let onOriginalChange: (String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. true nest", text: $original)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .onChange(of: original) { _, v in onOriginalChange(v) }
                } header: {
                    Text("Original Phrase")
                } footer: {
                    if let warning = duplicateWarning {
                        Text(warning).foregroundColor(Color.orange)
                    }
                }
                Section("Replacement") {
                    TextField("e.g. TrueNAS", text: $replacement)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
            }
            .navigationTitle(editingOriginal != nil ? "Edit Entry" : "Add Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editingOriginal != nil ? "Save" : "Add", action: onConfirm)
                        .disabled(original.isEmpty || replacement.isEmpty || duplicateWarning != nil)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct DictionaryEntryRow: View {
    let key: String
    let replacement: String
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(key).font(.headline)
                Text(replacement).font(.subheadline).foregroundColor(.accentColor)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(key) replaced with \(replacement)")
    }
}

struct DictionaryManagementView: View {
    @EnvironmentObject var dictionaryService: DictionaryService
    @State private var showingAddSheet = false
    @State private var newOriginal = ""
    @State private var newReplacement = ""
    @State private var duplicateWarning: String? = nil
    @State private var sortOrder: EntrySortOrder = .alphabetical

    // In-place edit state (quick task 260801-ftf). nil = the sheet is in Add
    // mode; non-nil = editing the entry with this (pre-edit) original key.
    @State private var editingOriginal: String? = nil

    // Import / Export state (Phase 31-02)
    @State private var showingExporter = false
    @State private var exportFormat = "csv"
    @State private var showingImporter = false
    @State private var showingMergeStrategyPicker = false
    @State private var pendingImportData: Data? = nil
    @State private var pendingImportFormat: String = "csv"
    @State private var pendingImportPreview: DictionaryIOService.ImportPreview? = nil
    @State private var showingReplaceAllConfirmation = false
    @State private var importResultMessage: String? = nil
    @State private var showingImportResult = false

    // Starter packs state (Phase 31-03)
    @State private var starterPackResultMessage: String? = nil
    @State private var showingStarterPackResult = false
    @State private var importedPacks: Set<DictionaryService.StarterPack> = []

    enum EntrySortOrder {
        case alphabetical, mostRecent
    }
    
    private var sortedKeys: [String] {
        switch sortOrder {
        case .alphabetical:
            return dictionaryService.dictionary.keys.sorted()
        case .mostRecent:
            // Sort by source priority first (user > imported > default), then most
            // recent createdAt within each group. This ensures the user's own entries
            // always surface at the top regardless of when default entries were stamped.
            return dictionaryService.dictionary.keys.sorted {
                let ma = dictionaryService.dictionary[$0], mb = dictionaryService.dictionary[$1]
                let pa = ma?.source.sortPriority ?? 0, pb = mb?.source.sortPriority ?? 0
                if pa != pb { return pa < pb }
                let da = ma?.createdAt ?? Date.distantPast, db = mb?.createdAt ?? Date.distantPast
                return da > db
            }
        }
    }
    
    @ViewBuilder private var starterPacksSection: some View {
        Section {
            Toggle("Case Sensitive Matching", isOn: $dictionaryService.isCaseSensitive)
        } footer: {
            Text("When enabled, 'truenas' will not match 'TrueNAS'.")
        }

        Section {
            ForEach(DictionaryService.StarterPack.allCases, id: \.self) { pack in
                let imported = importedPacks.contains(pack)
                Button(action: { importStarterPack(pack) }) {
                    let icon = imported ? "checkmark.circle.fill" : "tray.and.arrow.down"
                    let tint: Color = imported ? .green : .accentColor
                    HStack {
                        Label(pack.displayTitle, systemImage: icon).foregroundColor(tint)
                        if imported { Spacer(); Text("Imported").font(.caption).foregroundColor(.secondary) }
                    }
                }
            }
        } header: {
            Text("Starter Packs")
        } footer: {
            Text("The dictionary starts empty by design — no personal data ships in the app. Grow it three ways: add entries manually, tap a starter pack to import curated corrections in one click, or import a CSV file.\n\nTip: ask an AI to generate a CSV for your field — then tap Import.")
        }
    }

    @ViewBuilder private var importExportSection: some View {
        Section("Import / Export") {
            Menu {
                Button("Export as CSV") { exportFormat = "csv"; showingExporter = true }
                Button("Export as JSON") { exportFormat = "json"; showingExporter = true }
            } label: {
                Label("Export Dictionary", systemImage: "square.and.arrow.up")
            }
            Button(action: { showingImporter = true }) {
                Label("Import Dictionary", systemImage: "square.and.arrow.down")
            }
        }
    }

    @ViewBuilder private var customReplacementsSection: some View {
        Section("Custom Replacements (\(dictionaryService.dictionary.count))") {
            if dictionaryService.dictionary.isEmpty {
                Text("No custom entries yet.").foregroundColor(.secondary)
            } else {
                ForEach(sortedKeys, id: \.self) { key in
                    Button {
                        beginEdit(key)
                    } label: {
                        DictionaryEntryRow(
                            key: key,
                            replacement: dictionaryService.dictionary[key]?.replacement ?? ""
                        )
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: deleteEntries)
            }
        }
    }

    var body: some View {
        List {
            starterPacksSection
            importExportSection
            customReplacementsSection
        }
        .navigationTitle("Dictionary")
        .fileExporter(
            isPresented: $showingExporter,
            document: PlainTextDocument(exportedText()),
            contentType: exportFormat == "json" ? .json : .commaSeparatedText,
            defaultFilename: "Dicticus-dictionary-\(dateStamp()).\(exportFormat)"
        ) { _ in }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.commaSeparatedText, .json],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { return }
            let format = url.pathExtension.lowercased()
            let resolvedFormat = format.isEmpty ? "csv" : format

            switch dictionaryService.previewImport(data, format: resolvedFormat) {
            case .failure(let message):
                importResultMessage = "Import failed: \(message)"
                showingImportResult = true
            case .preview(let preview):
                // Store data before closure exits — URL scope ends here (Pitfall 4).
                pendingImportData = data
                pendingImportFormat = resolvedFormat
                pendingImportPreview = preview
                // Nothing to conflict with on an empty dictionary — skip the merge prompt.
                if dictionaryService.dictionary.isEmpty {
                    applyImport(strategy: .incomingWins)
                } else {
                    showingMergeStrategyPicker = true
                }
            }
        }
        .confirmationDialog("Choose Merge Strategy", isPresented: $showingMergeStrategyPicker, titleVisibility: .visible) {
            Button("Merge — keep mine on conflicts") { applyImport(strategy: .existingWins) }
                .keyboardShortcut(.defaultAction)
            Button("Merge — use imported on conflicts") { applyImport(strategy: .incomingWins) }
            Button("Replace All (delete current, then import)", role: .destructive) { requestReplaceAll() }
            Button("Cancel", role: .cancel) { pendingImportData = nil; pendingImportPreview = nil }
        } message: {
            Text(mergeDialogMessage)
        }
        .alert("Replace All Entries?", isPresented: $showingReplaceAllConfirmation) {
            Button("Delete \(pendingImportPreview?.deletedByReplaceAll ?? 0) and Replace", role: .destructive) {
                applyImport(strategy: .replaceAll)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete \(pendingImportPreview?.deletedByReplaceAll ?? 0) \((pendingImportPreview?.deletedByReplaceAll ?? 0) == 1 ? "entry" : "entries") not present in this file. This cannot be undone.")
        }
        .alert("Import Result", isPresented: $showingImportResult) {
            Button("OK", role: .cancel) {}
        } message: {
            let msg: String = importResultMessage ?? ""
            Text(msg)
        }
        .alert("Starter Pack Imported", isPresented: $showingStarterPackResult) {
            Button("OK", role: .cancel) {}
        } message: {
            let msg: String = starterPackResultMessage ?? ""
            Text(msg)
        }
        .onAppear { recomputeImportedPacks() }
        .onChange(of: dictionaryService.dictionary) { recomputeImportedPacks() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort By", selection: $sortOrder) {
                        Label("Alphabetical", systemImage: "textformat.abc").tag(EntrySortOrder.alphabetical)
                        Label("Most Recent", systemImage: "clock").tag(EntrySortOrder.mostRecent)
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .accessibilityLabel("Sort order")
            }
            
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingAddSheet = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddEntrySheet(
                original: $newOriginal,
                replacement: $newReplacement,
                duplicateWarning: duplicateWarning,
                editingOriginal: editingOriginal,
                onConfirm: {
                    if let oldOriginal = editingOriginal {
                        let result = dictionaryService.renameEntry(from: oldOriginal, to: newOriginal, replacement: newReplacement)
                        switch result {
                        case .saved:
                            showingAddSheet = false
                            resetFields()
                        case .collision(let key):
                            duplicateWarning = "'\(key)' already exists — choose a different Original."
                        case .invalid(let reason):
                            duplicateWarning = reason
                        case .notFound:
                            duplicateWarning = "This entry no longer exists."
                        }
                    } else {
                        dictionaryService.setReplacement(for: newOriginal, with: newReplacement)
                        showingAddSheet = false
                        resetFields()
                    }
                },
                onCancel: {
                    showingAddSheet = false
                    resetFields()
                },
                onOriginalChange: { checkForDuplicate($0) }
            )
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
        lines.append("Conflicts are entries whose Original appears in both.")
        return lines.joined(separator: " ")
    }

    // MARK: - In-place editing (quick task 260801-ftf)

    private func beginEdit(_ key: String) {
        guard let entry = dictionaryService.dictionary[key] else { return }
        editingOriginal = key
        newOriginal = key
        newReplacement = entry.replacement
        duplicateWarning = nil
        showingAddSheet = true
    }

    private func deleteEntries(at offsets: IndexSet) {
        let currentKeys = sortedKeys
        for index in offsets {
            dictionaryService.removeReplacement(for: currentKeys[index])
        }
    }
    
    private func resetFields() {
        newOriginal = ""
        newReplacement = ""
        duplicateWarning = nil
        editingOriginal = nil
    }

    private func checkForDuplicate(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != editingOriginal, dictionaryService.dictionary.keys.contains(trimmed) {
            duplicateWarning = "Entry '\(trimmed)' already exists."
        } else {
            duplicateWarning = nil
        }
    }

    // MARK: - Starter Packs (Phase 31-03)

    private func importStarterPack(_ pack: DictionaryService.StarterPack) {
        let result = dictionaryService.importStarterPack(pack)
        starterPackResultMessage = result.summaryMessage(source: pack.displayTitle)
        showingStarterPackResult = true
    }

    private func recomputeImportedPacks() {
        importedPacks = Set(DictionaryService.StarterPack.allCases.filter { dictionaryService.isStarterPackImported($0) })
    }

    // MARK: - Import / Export helpers (Phase 31-02)

    private func exportedText() -> String {
        let data = dictionaryService.exportData(format: exportFormat)
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func dateStamp() -> String {
        String(ISO8601DateFormatter().string(from: Date()).prefix(10))
    }

    /// Replace All is gated behind a second confirmation whenever it would
    /// delete entries not present in the file (T-ftf-03). When nothing would
    /// be lost, import proceeds directly.
    private func requestReplaceAll() {
        if (pendingImportPreview?.deletedByReplaceAll ?? 0) > 0 {
            showingReplaceAllConfirmation = true
        } else {
            applyImport(strategy: .replaceAll)
        }
    }

    private func applyImport(strategy: MergeStrategy) {
        guard let data = pendingImportData else { return }
        let result = dictionaryService.importData(data, format: pendingImportFormat, strategy: strategy)
        importResultMessage = result.summaryMessage()
        showingImportResult = true
        pendingImportData = nil
        pendingImportPreview = nil
    }
}

#Preview {
    NavigationStack {
        DictionaryManagementView()
            .environmentObject(DictionaryService.shared)
    }
}
