import SwiftUI

/// Phase 20.05 ACT-3-VISIBILITY — iOS detail view for a single history entry.
///
/// Pushed onto the existing `NavigationStack` in `HistoryView` via
/// `NavigationLink(value: entry)` + `.navigationDestination(for: TranscriptionEntry.self)`.
/// Exposes both the raw ASR output and the polished (rules + optional LLM)
/// output for the same entry, with a segmented Picker to swap between them.
///
/// **Default segment:** Raw — per CONTEXT.md decision (default Raw until LLM
/// trust is rebuilt). The `cleanupCopyMode` UserDefault is intentionally NOT
/// consulted here: the in-view Picker is the user's local choice, and the
/// toolbar Copy button copies whatever the user is looking at (precedence
/// documented in `CleanupCopyMode`).
///
/// **Legacy entries:** entries written before Phase 19 D-38 may have an empty
/// `rawText`. The Raw segment falls back to polished text in that case rather
/// than rendering a blank screen.
///
/// **Selectable text:** the body uses `.textSelection(.enabled)` so users can
/// copy substrings — important for UAT, where the team needs to compare exact
/// fragments between raw and polished.
struct HistoryDetailView: View {
    let entry: TranscriptionEntry

    /// Local picker state. Defaults to Raw per CONTEXT.md.
    @State private var selectedVariant: CleanupCopyMode = .raw

    /// Toast state for the toolbar Copy button.
    @State private var showCopiedToast: Bool = false

    @EnvironmentObject var historyService: HistoryService
    @Environment(\.dismiss) private var dismiss

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            Picker("Variant", selection: $selectedVariant) {
                Text("Raw").tag(CleanupCopyMode.raw)
                Text("Polished").tag(CleanupCopyMode.polished)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Show raw or polished transcription")

            ScrollView {
                if displayedText.isEmpty {
                    Text("Raw text not recorded")
                        .italic()
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(displayedText)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .navigationTitle("Entry")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(item: displayedText) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share transcription")

                Button {
                    copyDisplayed()
                } label: {
                    Image(systemName: showCopiedToast ? "checkmark.circle.fill" : "doc.on.doc")
                        .foregroundStyle(showCopiedToast ? .green : .accentColor)
                }
                .accessibilityLabel("Copy transcription")
                .accessibilityIdentifier("HistoryDetail.Copy")

                Button(role: .destructive) {
                    deleteAndDismiss()
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Delete transcription")
            }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(Self.dateFormatter.string(from: entry.createdAt))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            languageTag
            modeTag
        }
    }

    private var languageTag: some View {
        Text(entry.language.uppercased())
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.15))
            .foregroundStyle(Color.accentColor)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .accessibilityLabel("Language: \(entry.language == "de" ? "German" : "English")")
    }

    private var modeTag: some View {
        Text(entry.mode == "plain" ? "Plain" : "Cleanup")
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.purple.opacity(0.15))
            .foregroundStyle(.purple)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .accessibilityLabel("Mode: \(entry.mode)")
    }

    // MARK: - Variant logic

    /// Computes the text to display for the current Picker selection.
    /// Hoisted to a static helper so unit tests can exercise the swap +
    /// fallback behaviour without instantiating the view.
    static func displayedText(for variant: CleanupCopyMode, in entry: TranscriptionEntry) -> String {
        switch variant {
        case .raw:
            // Legacy entries (pre-D-38) have empty rawText. Fall back to
            // polished rather than show a blank screen.
            return entry.rawText.isEmpty ? entry.text : entry.rawText
        case .polished:
            return entry.text
        }
    }

    private var displayedText: String {
        Self.displayedText(for: selectedVariant, in: entry)
    }

    // MARK: - Actions

    private func copyDisplayed() {
        UIPasteboard.general.string = displayedText
        withAnimation { showCopiedToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { showCopiedToast = false }
        }
    }

    private func deleteAndDismiss() {
        if let id = entry.id {
            historyService.delete(id: id)
        }
        dismiss()
    }
}

#Preview {
    NavigationStack {
        HistoryDetailView(entry: TranscriptionEntry(
            uuid: UUID(),
            text: "Polished output with capitalisation and punctuation.",
            rawText: "raw output without much polish",
            language: "de",
            mode: "cleanup",
            createdAt: Date(),
            confidence: 0.95
        ))
    }
    .environmentObject(HistoryService.shared)
}
