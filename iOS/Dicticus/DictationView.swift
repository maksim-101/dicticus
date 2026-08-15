import SwiftUI

struct DictationView: View {
    @EnvironmentObject var viewModel: DictationViewModel
    @EnvironmentObject var warmupService: IOSModelWarmupService
    @EnvironmentObject var pendingStore: PendingRecordingStore
    @State private var showingSettings = false
    @State private var selectedBatchEntry: TranscriptionEntry?

    /// Chip tap target — defaults to a no-op so existing previews and any other
    /// construction site keep compiling. `ContentView` wires this to select the
    /// History tab (scroll-to-top is sufficient navigation per the UI-SPEC — no
    /// modal, no deep link).
    var onOpenPendingQueue: () -> Void = {}

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: iconName)
                    .font(.system(size: 64))
                    .foregroundStyle(viewModel.state == .recording ? .red : .primary)
                    .symbolEffect(.pulse, isActive: viewModel.state == .transcribing)
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
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(minWidth: 160)
                }
                .buttonStyle(.borderedProminent)
                .tint(viewModel.state == .recording ? .red : .accentColor)
                .disabled(viewModel.state == .transcribing || viewModel.state == .preparingLiveActivity)
                .accessibilityLabel(buttonLabel)
                .accessibilityHint(modelMissing ? "Starts recording and downloads the speech model in the background" : viewModel.state == .recording ? "Stops recording and transcribes" : "Starts a new dictation")

                // Non-blocking warm-up status: the mic button above is never gated by
                // any of this (46-UI-SPEC governing principle) — this card is purely
                // informational, rendered beside the button, and disappears entirely
                // once the model is ready (WarmupBannerStage.resolve returns nil).
                Group {
                    if let stage = warmupStage {
                        WarmupStatusBanner(
                            stage: stage,
                            downloadProgress: warmupService.downloadProgress,
                            warmupStartedAt: warmupService.warmupStartedAt,
                            error: warmupService.error,
                            isFirstWarmup: warmupService.isFirstWarmupForCurrentVersion,
                            onDownloadNow: { warmupService.warmup(force: true) },
                            onRetry: { warmupService.retry() }
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: warmupStage)

                // Sits below the warm-up banner (or alone, once the model is ready
                // and only the queue is nonempty) — renders nothing at count zero,
                // per PendingQueueChip.label(for:).
                PendingQueueChip(count: pendingStore.pendingCount, onTap: onOpenPendingQueue)
                    .padding(.horizontal, 24)

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
    /// Purely informational now (46-UI-SPEC governing principle) — never gates the
    /// mic button, only feeds `warmupStage` (the banner) and the accessibility hint.
    private var modelMissing: Bool {
        !warmupService.hasModels && !warmupService.isWarming && !warmupService.isReady
    }

    /// The `WarmupStatusBanner`'s stage, or nil to render nothing. Warm-up state is
    /// described in exactly this one place in the UI — `statusLabel`/`iconName` below
    /// no longer branch on it at all.
    private var warmupStage: WarmupBannerStage? {
        WarmupBannerStage.resolve(
            hasModels: warmupService.hasModels,
            isWarming: warmupService.isWarming,
            isReady: warmupService.isReady,
            error: warmupService.error
        )
    }

    private var iconName: String {
        switch viewModel.state {
        case .idle:                  return "mic"
        case .preparingLiveActivity: return "mic"
        case .recording:             return "mic.circle.fill"
        case .transcribing:          return "waveform.circle"
        }
    }

    private var statusLabel: String {
        switch viewModel.state {
        case .idle:
            if viewModel.isShortcutLaunch && viewModel.lastResult != nil {
                return "Copied to clipboard"
            }
            return "Ready to record"
        case .preparingLiveActivity: return "Starting\u{2026}"
        case .recording:             return "Recording\u{2026}"
        case .transcribing:          return "Transcribing\u{2026}"
        }
    }

    private var buttonLabel: String {
        viewModel.state == .recording ? "Stop" : "Start Dictation"
    }

    private func handleButton() {
        if modelMissing {
            // D-05: the tap below still records (and enqueues) regardless — this
            // just also kicks off the download so a queued recording isn't left
            // waiting on a download nobody separately triggered via the banner's
            // own "Download Now" action. warmup(force:) is a no-op if a
            // download/load is already in flight or the model is already ready.
            warmupService.warmup(force: true)
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
        .environmentObject(PendingRecordingStore.shared)
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
        .environmentObject(PendingRecordingStore.shared)
}

#Preview("Warm-up — downloading") {
    let ws = IOSModelWarmupService()
    ws.hasModels = false
    ws.isWarming = true
    ws.downloadProgress = 0.42
    return DictationView()
        .environmentObject(DictationViewModel())
        .environmentObject(ws)
        .environmentObject(PendingRecordingStore.shared)
}

#Preview("Warm-up — loading") {
    let ws = IOSModelWarmupService()
    ws.hasModels = true
    ws.isWarming = true
    return DictationView()
        .environmentObject(DictationViewModel())
        .environmentObject(ws)
        .environmentObject(PendingRecordingStore.shared)
}

#Preview("Warm-up — model missing") {
    let ws = IOSModelWarmupService()
    ws.hasModels = false
    ws.isWarming = false
    ws.isReady = false
    return DictationView()
        .environmentObject(DictationViewModel())
        .environmentObject(ws)
        .environmentObject(PendingRecordingStore.shared)
}

#Preview("Warm-up — failed") {
    let ws = IOSModelWarmupService()
    ws.isWarming = false
    ws.error = "Model load failed: The network connection was lost."
    return DictationView()
        .environmentObject(DictationViewModel())
        .environmentObject(ws)
        .environmentObject(PendingRecordingStore.shared)
}
