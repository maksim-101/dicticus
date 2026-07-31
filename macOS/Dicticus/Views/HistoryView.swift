import SwiftUI

/// A window view for browsing transcription history.
///
/// Per UX-02/UX-03/UX-04: Searchable list with copy support and highlighting.
/// Per Phase 20.05: Inline disclosure exposing raw vs polished output for UAT/visibility.
struct HistoryView: View {
    @EnvironmentObject var historyService: HistoryService
    @State private var searchText = ""
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
        VStack(spacing: 0) {
            // Header with Search
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search history\u{2026}", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isSearchFieldFocused)
                    .onChange(of: searchText) { _, newValue in
                        historyService.load(query: newValue)
                    }

                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        historyService.load(query: "")
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(.ultraThinMaterial)
            .contentShape(Rectangle())
            .onTapGesture {
                isSearchFieldFocused = true
            }

            Divider()

            // History List
            List(historyService.entries, selection: $selection) { entry in
                HistoryRow(entry: entry, formatter: dateFormatter, searchTerm: searchText)
                    .tag(entry.uuid)
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
            }
            .listStyle(.inset)
            .overlay {
                if historyService.entries.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No History" : "No Results",
                        systemImage: searchText.isEmpty ? "clock" : "magnifyingglass",
                        description: Text(searchText.isEmpty ? "Your transcriptions will appear here." : "Try a different search term.")
                    )
                }
            }

            Divider()

            // Footer
            HStack {
                Text("\(historyService.entries.count) entries")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Spacer()

                if !selection.isEmpty {
                    Button("Delete Selected") {
                        for uuid in selection {
                            if let entry = historyService.entries.first(where: { $0.uuid == uuid }),
                               let id = entry.id {
                                historyService.delete(id: id)
                            }
                        }
                        selection.removeAll()
                    }
                    .controlSize(.small)
                }

                Button("Clear All") {
                    isShowingClearConfirmation = true
                }
                .controlSize(.small)
                .foregroundStyle(.red)
            }
            .padding(.horizontal, 16)
            .frame(height: 32)
            .background(.ultraThinMaterial)
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
            historyService.load(query: searchText)
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

    @State private var showCopied = false
    @State private var isExpanded: Bool = false
    @State private var selectedVariant: CleanupCopyMode = .raw

    private var displayedText: String {
        switch selectedVariant {
        case .raw:
            return entry.rawText.isEmpty ? entry.text : entry.rawText
        case .polished:
            return entry.text
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                // Disclosure chevron
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "Collapse" : "Show raw / polished")

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
                    copyToClipboard(rowCopyText())
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
                .help("Copy to clipboard (uses Settings > Copy mode)")
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Variant", selection: $selectedVariant) {
                        Text("Raw").tag(CleanupCopyMode.raw)
                        Text("Polished").tag(CleanupCopyMode.polished)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    ScrollView {
                        Text(displayedText)
                            .font(.system(size: 12))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 200)

                    HStack {
                        Spacer()
                        Button {
                            copyToClipboard(displayedText)
                            withAnimation { showCopied = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                withAnimation { showCopied = false }
                            }
                        } label: {
                            Label("Copy \(selectedVariant == .raw ? "Raw" : "Polished")",
                                  systemImage: "doc.on.doc")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(.leading, 26)
                .padding(.top, 4)
                .padding(.bottom, 4)
            }
        }
        .padding(.vertical, 8)
    }

    /// Per-row Copy honors the global default; in-disclosure Copy honors the in-view Picker.
    private func rowCopyText() -> String {
        switch CleanupCopyMode.current {
        case .raw:
            return entry.rawText.isEmpty ? entry.text : entry.rawText
        case .polished:
            return entry.text
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
}
