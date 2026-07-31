import SwiftUI

/// AI Cleanup model info section in the menu bar dropdown.
///
/// Shows model name, loading status, and a "Configure" button that opens
/// a popover with an editable prompt instruction.
struct AiCleanupInfoView: View {
    @EnvironmentObject var warmupService: ModelWarmupService
    @State private var showPromptEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AI Cleanup")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top, 4)

            VStack(spacing: 4) {
                // Model name row
                HStack {
                    Text("Model")
                        .font(.body)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(ModelDownloadService.modelDisplayName)
                        .font(.body)
                }
                .padding(.horizontal)
                .padding(.vertical, 2)

                // Status row
                HStack {
                    Text("Status")
                        .font(.body)
                        .foregroundColor(.secondary)
                    Spacer()

                    if warmupService.llmStatus.isActive {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, 4)
                    }

                    statusLabel
                }
                .padding(.horizontal)
                .padding(.vertical, 2)

                // Configure prompt button
                HStack {
                    Spacer()
                    Button {
                        showPromptEditor.toggle()
                    } label: {
                        Label("Configure Prompt", systemImage: "slider.horizontal.3")
                            .font(.caption)
                    }
                    .buttonStyle(.link)
                    .popover(isPresented: $showPromptEditor, arrowEdge: .trailing) {
                        PromptEditorView(isPresented: $showPromptEditor)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch warmupService.llmStatus {
        case .idle:
            Text(warmupService.llmStatus.label)
                .font(.body)
                .foregroundColor(.secondary)
        case .downloading, .loading:
            Text(warmupService.llmStatus.label)
                .font(.body)
                .foregroundColor(.orange)
        case .ready:
            Text(warmupService.llmStatus.label)
                .font(.body)
                .foregroundColor(.green)
        case .failed:
            Text(warmupService.llmStatus.label)
                .font(.body)
                .foregroundColor(.red)
        }
    }
}

/// Popover content for editing the AI cleanup prompt instruction.
///
/// Shows a text editor with the current instruction, a reset button,
/// and a note about language detection.
struct PromptEditorView: View {
    @Binding var isPresented: Bool
    @AppStorage(CleanupPrompt.customInstructionKey) private var customInstruction = ""
    @State private var editText = ""
    @State private var showSaved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cleanup Instruction")
                .font(.headline)

            Text("This instruction tells the AI how to polish your dictated text. The detected language (German/English) is provided automatically.")
                .font(.caption)
                .foregroundColor(.secondary)

            TextEditor(text: $editText)
                .font(.body)
                .frame(minHeight: 140)
                .border(Color.secondary.opacity(0.3))

            HStack {
                Button("Reset to Default") {
                    editText = CleanupPrompt.defaultInstruction
                    customInstruction = ""
                }
                .buttonStyle(.link)

                Spacer()

                if showSaved {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                        .transition(.opacity)
                }

                Button("Save") {
                    let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed == CleanupPrompt.defaultInstruction.trimmingCharacters(in: .whitespacesAndNewlines) {
                        customInstruction = ""
                    } else {
                        customInstruction = trimmed
                    }
                    withAnimation { showSaved = true }
                    // Brief confirmation then dismiss
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        isPresented = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding()
        .frame(width: 360)
        .onAppear {
            editText = customInstruction.isEmpty
                ? CleanupPrompt.defaultInstruction
                : customInstruction
            showSaved = false
        }
    }
}
