import SwiftUI

struct DictationView: View {
    @EnvironmentObject var viewModel: DictationViewModel
    @EnvironmentObject var warmupService: IOSModelWarmupService
    @State private var showingSettings = false
    @State private var selectedBatchEntry: TranscriptionEntry?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: iconName)
                    .font(.system(size: 64))
                    .foregroundStyle(viewModel.state == .recording ? .red : .primary)
                    .symbolEffect(.pulse, isActive: warmupService.isWarming || viewModel.state == .transcribing)
                    .accessibilityLabel(iconName == "mic" ? "Microphone" : "Recording status")
                    .accessibilityAddTraits(.isImage)

                Text(statusLabel)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .accessibilityLabel("Status")
                    .accessibilityValue(statusLabel)

                Button(action: handleButton) {
                    Text(buttonLabel)
                        .frame(minWidth: 160)
                }
                .buttonStyle(.borderedProminent)
                .tint(viewModel.state == .recording ? .red : .accentColor)
                .disabled(warmupService.isWarming || viewModel.state == .transcribing || viewModel.state == .preparingLiveActivity)
                .accessibilityLabel(buttonLabel)
                .accessibilityHint(modelMissing ? "Downloads the ASR model" : viewModel.state == .recording ? "Stops recording and transcribes" : "Starts a new dictation")

                // Show what warmup is actually doing, on EVERY launch — not just during a
                // download. The status text (`downloadStatus`) is now stage-accurate ("Loading
                // speech model…" when the model is already on disk, "Downloading…" on first run),
                // so it no longer flashes a fake "Downloading" screen on cold launch (IOS-ONB-01).
                // WhisperKit's download-progress callback is a documented no-op today, so show a
                // determinate bar only when real progress arrives, otherwise an indeterminate
                // spinner — honest about not having a percentage rather than a bar stuck at 0.
                if warmupService.isWarming {
                    VStack(spacing: 8) {
                        if warmupService.downloadProgress > 0 {
                            ProgressView(value: warmupService.downloadProgress, total: 1.0)
                                .progressViewStyle(.linear)
                        } else {
                            ProgressView()
                                .progressViewStyle(.circular)
                        }
                        Text(warmupService.downloadStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(.horizontal)
                }

                if let result = viewModel.lastResult {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Copied to clipboard:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(result)
                            .font(.body)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(8)
                        if viewModel.isShortcutLaunch {
                            Label("Swipe up to return to your app", systemImage: "arrow.up")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                        }
                    }
                    .padding(.horizontal)
                }

                // Batch list: shown when multiple background sessions completed since last open.
                // The most-recent is already in `lastResult`; here we surface the full batch.
                if viewModel.recentlyDelivered.count > 1 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(viewModel.recentlyDelivered.count) new transcripts")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        VStack(spacing: 0) {
                            ForEach(viewModel.recentlyDelivered) { entry in
                                Button {
                                    selectedBatchEntry = entry
                                } label: {
                                    HStack(alignment: .top, spacing: 8) {
                                        Text(entry.createdAt, style: .time)
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                            .frame(minWidth: 52, alignment: .leading)
                                        Text(entry.text)
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                            .lineLimit(2)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 12)
                                }
                                .buttonStyle(.plain)
                                if entry != viewModel.recentlyDelivered.last {
                                    Divider().padding(.leading, 72)
                                }
                            }
                        }
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(8)
                    }
                    .padding(.horizontal)
                    .sheet(item: $selectedBatchEntry) { entry in
                        NavigationStack {
                            HistoryDetailView(entry: entry)
                        }
                        .environmentObject(HistoryService.shared)
                    }
                }

                if let error = viewModel.error {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .padding(.horizontal)
                }

                if warmupService.error != nil && !warmupService.isWarming {
                    Button("Retry Download") {
                        warmupService.retry()
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Dicticus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !viewModel.isShortcutLaunch {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: { showingSettings = true }) {
                            Image(systemName: "gear")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .environmentObject(warmupService)
            }
            .onChange(of: viewModel.state) { _, newState in
                if newState == .recording {
                    showingSettings = false
                }
            }
        }
    }

    /// Whether the model needs to be downloaded before dictation can start.
    private var modelMissing: Bool {
        !warmupService.hasModels && !warmupService.isWarming && !warmupService.isReady
    }

    private var iconName: String {
        // Present-model warmup keeps the normal mic so the home screen doesn't look
        // like a download is in progress (IOS-ONB-01).
        if warmupService.isWarming { return warmupService.hasModels ? "mic" : "arrow.down.circle" }
        if modelMissing { return "arrow.down.to.line" }
        switch viewModel.state {
        case .idle:                  return "mic"
        case .preparingLiveActivity: return "mic"
        case .recording:             return "mic.circle.fill"
        case .transcribing:          return "waveform.circle"
        }
    }

    private var statusLabel: String {
        if warmupService.isWarming {
            // Stable headline; the stage-accurate detail (download vs load, size) is the caption
            // line below (warmupService.downloadStatus), so this no longer carries a wrong size.
            return "Getting Dicticus ready\u{2026}"
        }
        if let error = warmupService.error { return error }
        if modelMissing { return "ASR model not downloaded" }
        switch viewModel.state {
        case .idle:
            if viewModel.isShortcutLaunch && viewModel.lastResult != nil {
                return "Copied to clipboard"
            }
            return "Ready"
        case .preparingLiveActivity: return "Starting\u{2026}"
        case .recording:             return "Recording\u{2026}"
        case .transcribing:          return "Transcribing\u{2026}"
        }
    }

    private var buttonLabel: String {
        if modelMissing { return "Download Model" }
        return viewModel.state == .recording ? "Stop" : "Start Dictation"
    }

    private func handleButton() {
        if modelMissing {
            warmupService.retry()
            return
        }
        Task {
            if viewModel.state == .idle {
                await viewModel.startDictation()
            } else if viewModel.state == .recording {
                await viewModel.stopDictation()
            }
        }
    }
}

#Preview {
    DictationView()
        .environmentObject(DictationViewModel())
        .environmentObject(IOSModelWarmupService())
}

#Preview("Batch delivery — 3 new") {
    let vm = DictationViewModel()
    vm.lastResult = "The most recent dictation transcript goes here."
    vm.recentlyDelivered = [
        TranscriptionEntry(uuid: UUID(), text: "The most recent dictation transcript goes here.",
                           rawText: "the most recent dictation transcript goes here",
                           language: "en", mode: "plain",
                           createdAt: Date(timeIntervalSinceNow: -30), confidence: 0.93),
        TranscriptionEntry(uuid: UUID(), text: "Zweite Aufnahme mit etwas längerem Text der umbricht.",
                           rawText: "zweite aufnahme mit etwas längerem text der umbricht",
                           language: "de", mode: "plain",
                           createdAt: Date(timeIntervalSinceNow: -120), confidence: 0.88),
        TranscriptionEntry(uuid: UUID(), text: "First background session from earlier.",
                           rawText: "first background session from earlier",
                           language: "en", mode: "plain",
                           createdAt: Date(timeIntervalSinceNow: -300), confidence: 0.91),
    ]
    return DictationView()
        .environmentObject(vm)
        .environmentObject(IOSModelWarmupService())
}
