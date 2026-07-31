import SwiftUI

/// History pane of the popover: up to 2 inline recent rows + "Open Full History…" link.
///
/// Per UI-SPEC §macOS — History Tab:
///   - Section header "Recent" in caption uppercase secondary
///   - Up to 2 inline rows mirroring HistoryView row style
///   - Per-row Copy button (a11y label includes excerpt)
///   - Final tappable row opens the full history window
///   - Empty state: "No transcription history yet." centered subheadline secondary
struct HistoryPane: View {

    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var historyService = HistoryService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if historyService.entries.isEmpty {
                Spacer()
                Text("No transcription history yet.")
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(16)
                Spacer()
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text("RECENT")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 6)

                    let recentEntries = Array(historyService.entries.prefix(4))
                    ForEach(Array(recentEntries.enumerated()), id: \.element.uuid) { index, entry in
                        inlineHistoryRow(entry)
                        if index < recentEntries.count - 1 {
                            Divider()
                                .padding(.horizontal, 16)
                        }
                    }

                    Divider()
                        .padding(.horizontal, 16)
                        .padding(.top, 4)

                    openHistoryButton
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            historyService.load()
        }
    }

    @ViewBuilder
    private func inlineHistoryRow(_ entry: TranscriptionEntry) -> some View {
        HStack {
            Text(entry.text)
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
                .lineLimit(1)

            Spacer()

            CopyRowButton(text: entry.text)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private var openHistoryButton: some View {
        Button {
            openWindow(id: "history")
            NSApp.activate(ignoringOtherApps: true)
        } label: {
            HStack {
                Image(systemName: "magnifyingglass")
                Text("Open Full History…")
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(Color.secondary)
            }
            .contentShape(Rectangle())
            .font(.subheadline)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .accessibilityLabel("Open full history")
    }
}

// MARK: - CopyRowButton

private struct CopyRowButton: View {
    let text: String
    @State private var showCopied = false

    var body: some View {
        Button(showCopied ? "Copied!" : "Copy") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            showCopied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                showCopied = false
            }
        }
        .controlSize(.small)
        .accessibilityLabel("Copy: \(text.prefix(40))")
    }
}
