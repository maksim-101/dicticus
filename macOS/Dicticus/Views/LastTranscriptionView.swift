import SwiftUI

/// Last transcription preview with copy button.
///
/// Per D-21: Shows truncated text of last successful transcription.
///   Copy button as fallback if paste-at-cursor failed or user wants the text again.
/// Per UI-SPEC:
///   - Section heading "Last Transcription" (.headline, semibold)
///   - Text: .lineLimit(2), .truncationMode(.tail), .body style
///   - Copy button: .controlSize(.small), .buttonStyle(.bordered), right-aligned
///   - Section hidden entirely when text is nil
struct LastTranscriptionView: View {
    let text: String?

    /// Tracks whether "Copied!" feedback is currently showing.
    @State private var showCopied = false

    var body: some View {
        if let text, !text.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Last Transcription")
                    .font(.headline)
                    .padding(.horizontal)
                    .padding(.top, 4)

                HStack(alignment: .top) {
                    Text(text)
                        .font(.body)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .accessibilityLabel("Last transcription")

                    Spacer()

                    Button(showCopied ? "Copied!" : "Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        showCopied = true
                        // Reset after 1.5 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            showCopied = false
                        }
                    }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                    .accessibilityLabel(showCopied ? "Copied to clipboard" : "Copy last transcription")
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
            }
        }
    }
}
