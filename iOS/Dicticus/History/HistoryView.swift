import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var historyService: HistoryService
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            List {
                if historyService.entries.isEmpty {
                    ContentUnavailableView(
                        "No History",
                        systemImage: "clock.badge.exclamationmark",
                        description: Text("Your transcriptions will appear here.")
                    )
                } else {
                    ForEach(historyService.entries) { entry in
                        NavigationLink(value: entry) {
                            HistoryRow(entry: entry)
                        }
                    }
                    .onDelete(perform: deleteEntries)
                }
            }
            .navigationTitle("History")
            .navigationDestination(for: TranscriptionEntry.self) { entry in
                HistoryDetailView(entry: entry)
            }
            .searchable(text: $searchText, prompt: "Search transcriptions")
            .onChange(of: searchText) { _, newValue in
                historyService.load(query: newValue)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
        }
    }

    private func deleteEntries(at offsets: IndexSet) {
        for index in offsets {
            if let id = historyService.entries[index].id {
                historyService.delete(id: id)
            }
        }
    }
}

struct HistoryRow: View {
    let entry: TranscriptionEntry
    @State private var showingCopiedMessage = false

    var body: some View {
        // Phase 20.06 UAT fix: NavigationLink already supplies the trailing
        // disclosure chevron, so the manual `chevron.right` we added produced
        // a duplicated `> >`. Removing the manual chevron also lets the language
        // tag and Copy button extend to the row's right edge instead of being
        // pushed inward by the extra chevron column.
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 4) {
                    Text(entry.createdAt, style: .date)
                    Text(entry.createdAt, style: .time)
                }
                .font(.caption)
                .foregroundColor(.secondary)
                Spacer()
                Text(entry.language.uppercased())
                    .font(.caption2).bold()
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(4)
                    .accessibilityLabel("Language: \(entry.language == "de" ? "German" : "English")")
            }

            Text(entry.text)
                .font(.body)
                .lineLimit(3)

            HStack {
                Label("\(Int(entry.confidence * 100))%", systemImage: "waveform")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .accessibilityLabel("Confidence: \(Int(entry.confidence * 100)) percent")

                Spacer()

                Button(action: copyToClipboard) {
                    Label(showingCopiedMessage ? "Copied" : "Copy", systemImage: "doc.on.doc")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(showingCopiedMessage ? "Copied to clipboard" : "Copy transcription")
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button {
                copyToClipboard()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func copyToClipboard() {
        let toCopy: String
        switch CleanupCopyMode.current {
        case .raw:
            toCopy = entry.rawText.isEmpty ? entry.text : entry.rawText
        case .polished:
            toCopy = entry.text
        }
        UIPasteboard.general.string = toCopy
        withAnimation {
            showingCopiedMessage = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showingCopiedMessage = false
            }
        }
    }
}

#Preview {
    HistoryView()
        .environmentObject(HistoryService.shared)
}
