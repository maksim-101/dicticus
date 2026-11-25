import SwiftUI

/// A window view for browsing transcription history.
///
/// Per UX-02/UX-03/UX-04: Searchable list with copy support and highlighting.
/// Per Phase 20.05: Inline disclosure exposing raw vs polished output for UAT/visibility.
struct HistoryView: View {
    @EnvironmentObject var historyService: HistoryService
    @State private var searchText = ""
    /// What the list shows: the search hits, else all of `historyService.entries`. Kept here so
    /// a search never replaces the service's list that the Home card and Fix a word read.
    @State private var shown: [TranscriptionEntry] = []
    /// Rows marked with ⌘-click for "Delete Marked".
    @State private var selection: Set<UUID> = []
    @State private var isShowingClearConfirmation = false
    @FocusState private var isSearchFieldFocused: Bool

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }()

    var body: some View {
        // History List
            // No List selection: a click opens a row, ⌘-click marks it for the bin, and the
            // accent-blue selection fill made the row hard to read.
            // A stack, not a List: the List's table cells re-laid out and redrew the whole row,
            // summary included, whenever a row opened.
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(shown, id: \.uuid) { entry in
                        HistoryRow(entry: entry, formatter: dateFormatter, searchTerm: searchText,
                                   marked: selection.contains(entry.uuid)) {
                            if !selection.insert(entry.uuid).inserted { selection.remove(entry.uuid) }
                        }
                        .contextMenu {
                            Button("Copy Text") {
                                copyToClipboard(entry.text)
                            }
                            Button("Delete", role: .destructive) {
                                if let id = entry.id {
                                    historyService.delete(id: id)
                                }
                            }
                        }
                        Divider().padding(.leading, 30)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .overlay {
                if shown.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No History" : "No Results",
                        systemImage: searchText.isEmpty ? "clock" : "magnifyingglass",
                        description: Text(searchText.isEmpty ? "Your transcriptions will appear here." : "Try a different search term.")
                    )
                }
            }
        // Search, count and actions live in the window toolbar (DESIGN.md).
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search history")
        .searchFocused($isSearchFieldFocused)
        .onChange(of: searchText) { _, _ in refreshShown() }
        .onChange(of: historyService.entries) { _, _ in refreshShown() }
        .navigationSubtitle("\(shown.count) \(shown.count == 1 ? "dictation" : "dictations")")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if !selection.isEmpty {
                    Button("Delete Marked", systemImage: "trash") {
                        for uuid in selection {
                            if let entry = shown.first(where: { $0.uuid == uuid }),
                               let id = entry.id {
                                historyService.delete(id: id)
                            }
                        }
                        selection.removeAll()
                    }
                }
                Menu {
                    Button("Clear All…", role: .destructive) { isShowingClearConfirmation = true }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .frame(minWidth: 600, minHeight: 450)
        .navigationTitle("Transcription History")
        .alert("Clear History?", isPresented: $isShowingClearConfirmation) {
            Button("Clear All", role: .destructive) {
                historyService.clearAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete all transcription history? This cannot be undone.")
        }
        .onAppear {
            historyService.load()
            refreshShown()
            // Auto-focus search on appear for better UX
            isSearchFieldFocused = true
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
    }

    private func refreshShown() {
        shown = searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? historyService.entries
            : historyService.searchHits(query: searchText)
        // Marks follow what is shown, so "Delete Marked" deletes exactly the marked rows on screen.
        selection.formIntersection(shown.map(\.uuid))
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

struct HistoryRow: View {
    let entry: TranscriptionEntry
    let formatter: DateFormatter
    let searchTerm: String
    var marked = false
    var onMark: () -> Void = {}

    @State private var showCopied = false
    @State private var isExpanded: Bool = false
    @State private var showCopiedHeard = false
    @Environment(\.openWindow) private var openWindow

    /// `expanded` sets the starting state for the off-screen render test.
    init(entry: TranscriptionEntry, formatter: DateFormatter, searchTerm: String, expanded: Bool = false,
         marked: Bool = false, onMark: @escaping () -> Void = {}) {
        self.entry = entry
        self.formatter = formatter
        self.searchTerm = searchTerm
        self.marked = marked
        self.onMark = onMark
        _isExpanded = State(initialValue: expanded)
    }

    /// What the recognizer heard, when it differs from the pasted text.
    private var heardText: String? {
        entry.rawText.isEmpty || entry.rawText == entry.text ? nil : entry.rawText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                // The whole row opens and closes (tap gesture below); the chevron only shows the state.
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(formatter.string(from: entry.createdAt))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)

                        Spacer()

                        HStack(spacing: 4) {
                            TagView(text: entry.language.uppercased(), color: .blue)
                            TagView(text: entry.mode == "plain" ? "Plain" : "Cleanup", color: entry.mode == "plain" ? .gray : .purple)
                        }
                    }

                    highlightedText(entry.text, term: searchTerm)
                        .font(.system(size: 13))
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                // Dedicated Copy Button (UX Requirement)
                Button {
                    copyToClipboard(entry.text)
                    withAnimation {
                        showCopied = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation { showCopied = false }
                    }
                } label: {
                    Group {
                        if showCopied {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Image(systemName: "doc.on.doc")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.system(size: 12))
                    .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help("Copy the pasted text")
                .accessibilityLabel("Copy the pasted text")
            }
            // The summary opens and closes the row; the opened part keeps its own clicks, so its
            // text stays selectable (review of 98e2e2a).
            .contentShape(Rectangle())
            .onTapGesture(perform: rowTapped)

            if isExpanded {
                // Board popover-dictionary-and-history, variant A: the summary shows and copies the
                // pasted text; the heard text sits in its own box with its own Copy, so each copy
                // button stays next to the text it copies.
                VStack(alignment: .leading, spacing: 8) {
                    if let heardText {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("As heard, before the dictionary and cleanup")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button {
                                    copyToClipboard(heardText)
                                    withAnimation { showCopiedHeard = true }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                        withAnimation { showCopiedHeard = false }
                                    }
                                } label: {
                                    Label(showCopiedHeard ? "Copied" : "Copy",
                                          systemImage: showCopiedHeard ? "checkmark" : "doc.on.doc")
                                        .font(.system(size: 11))
                                }
                                .buttonStyle(.borderless)
                                .help("Copy the text as heard")
                            }
                            Text(heardText)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                    }

                    // Words are marked in the "Fix a word" window, on the pasted text.
                    Button {
                        FixWordRequest.open(entry, with: openWindow)
                    } label: {
                        Label("Fix a word…", systemImage: "character.cursor.ibeam")
                    }
                    .buttonStyle(.bordered)
                    .fixedSize()
                }
                .padding(.leading, 26)
                .padding(.top, 4)
                .padding(.bottom, 4)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(marked ? Color.accentColor.opacity(0.12) : isExpanded ? Color.primary.opacity(0.06) : .clear,
                    in: RoundedRectangle(cornerRadius: 8))
        // A closed row also opens from its padding edge; an opened row keeps its own clicks.
        .contentShape(Rectangle())
        .gesture(TapGesture().onEnded(rowTapped), including: isExpanded ? .subviews : .all)
    }

    private func rowTapped() {
        if NSEvent.modifierFlags.contains(.command) {
            onMark()
        } else {
            withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
        }
    }


    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Helper to generate highlighted text based on search term
    private func highlightedText(_ text: String, term: String) -> Text {
        guard !term.isEmpty, let range = text.range(of: term, options: .caseInsensitive) else {
            return Text(text)
        }

        let beforeRange = text[..<range.lowerBound]
        let matchRange = text[range]
        let afterRange = text[range.upperBound...]

        return Text(String(beforeRange))
            + Text(String(matchRange))
                .bold()
                .foregroundStyle(.primary)
            + highlightedText(String(afterRange), term: term)
    }
}

struct TagView: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

#Preview {
    HistoryView()
        .environmentObject(HistoryService.shared)
        .environmentObject(DictionaryService.shared)
}
