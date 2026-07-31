import SwiftUI

/// Phase 19 Wave 4: AI Cleanup + Swiss German Settings UI.
///
/// Two orthogonal toggles plus an inline GGUF download panel. Hidden behind an
/// explainer on RAM-ineligible devices (D-03). Inline — not modal — per D-10.
///
/// **Persistence (D-08):** Toggles read/write the `group.com.dicticus` App Group
/// UserDefaults suite so the keyboard extension (if revived) and warmup service
/// see the same values. Keys: `aiCleanupEnabled`, `useSwissGerman`. Both default
/// `false`.
///
/// **Downloader (D-10):** `@StateObject private var downloader` is ephemeral —
/// it only exists while the Settings screen is on-screen. The warmup service's
/// Step 4 (Wave 3) reads the *cached file* on the next app launch. When the user
/// dismisses Settings mid-download, the in-flight task is cancelled and the user
/// must retry via the inline panel; this is acceptable scope per the phase-19
/// threat register (T-19-05-03).
///
/// **RAM gating (D-03 / D-20):** When `IOSModelWarmupService.isAiCleanupSupported`
/// is `false` the AI Cleanup toggle is *replaced* by a disabled explainer row; the
/// Swiss German toggle remains visible because it operates on plain dictation
/// independently of LLM availability (D-15).
struct AiCleanupSection: View {
    @EnvironmentObject var warmupService: IOSModelWarmupService

    /// Ephemeral downloader — only alive while this view is in the hierarchy.
    @StateObject private var downloader = IOSModelDownloadService()

    /// Local mirror of on-disk cache state so UI refreshes when the downloader
    /// transitions to `.completed`.
    @State private var isModelCached: Bool = IOSModelDownloadService.isModelCached()

    /// D-05 (Phase 37 Plan 02): presented only when warmupService.isOnCellular is
    /// true — reuses the shared warmupService flag; no separate network-path
    /// monitor is created in this file.
    @State private var showCellularDownloadWarning = false

    // MARK: - AppGroup suite (D-08)
    //
    // Phase 20.06 UAT fix: use `@AppStorage` (not a manual UserDefaults Binding)
    // for `aiCleanupEnabled`. SwiftUI does not observe synchronous reads of
    // `UserDefaults.bool(forKey:)`, so the prior implementation showed a stale
    // download panel until an unrelated re-render (e.g. record-button tap) ran.
    // `@AppStorage` registers a KVO observer that invalidates the view body
    // immediately when the toggle flips.

    private static let appGroupDefaults = UserDefaults(suiteName: "group.com.dicticus")!

    @AppStorage("aiCleanupEnabled", store: appGroupDefaults) private var aiCleanupEnabled: Bool = false
    @AppStorage("useSwissGerman", store: appGroupDefaults) private var useSwissGerman: Bool = true
    // Phase 39/D-07: user-facing escape hatch for the scratch-command
    // voice-edit feature — same `enableVoiceCommands` key TextProcessingService
    // reads via DicticusDefaults.suite. NOT the safety mechanism; the
    // compile-time gate flags in SelfCorrectionResolver govern shipping.
    @AppStorage("enableVoiceCommands", store: appGroupDefaults) private var enableVoiceCommands: Bool = true

    // MARK: - Body

    var body: some View {
        Section {
            // Phase 20.04 ACT-4-RESILIENCE: surface graceful fallback state.
            // Read at view-build time; the flag is set during HistoryService.init()
            // before any view appears and is immutable for the process lifetime,
            // so static read is sufficient (no @Published / observation needed).
            if !HistoryService.appGroupAvailable {
                appGroupFallbackWarningRow
            }

            if IOSModelWarmupService.isAiCleanupSupported {
                aiCleanupToggle
                if aiCleanupEnabled {
                    statusRow
                    if !isModelCached {
                        downloadPanel
                    }
                }
            } else {
                unsupportedRow
            }

            // Swiss toggle is ALWAYS visible (D-15) — orthogonal to AI Cleanup
            // and operates on plain dictation (\u{00DF} \u{2192} ss).
            swissGermanToggle

            // Phase 39/D-07: voice-commands toggle is ALWAYS visible, like the
            // Swiss toggle above — a user whose text is being unexpectedly
            // edited must be able to find the escape hatch even in a
            // degraded state (e.g. AI Cleanup unsupported/unavailable).
            voiceCommandsToggle
        } header: {
            Text("AI Cleanup")
        } footer: {
            Text("\(IOSModelDownloadService.modelDisplayName) runs entirely on-device \u{2014} no audio is sent to any server. Swiss German spelling applies to plain dictation independently of AI Cleanup.")
        }
        .onChange(of: downloader.state) { _, newState in
            // Refresh cached-state when download completes so the panel swaps to
            // the "relaunch to enable" hint.
            if newState == .completed {
                isModelCached = IOSModelDownloadService.isModelCached()
            }
        }
        .confirmationDialog(
            "Download over Cellular?",
            isPresented: $showCellularDownloadWarning,
            titleVisibility: .visible
        ) {
            Button("Download over Cellular") {
                downloader.start()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(IOSModelDownloadService.modelDisplayName) is \u{2248} 2.74 GB and will use your cellular data. Wi-Fi is recommended.")
        }
    }

    // MARK: - Subviews

    private var aiCleanupToggle: some View {
        Toggle(isOn: $aiCleanupEnabled) {
            Label("AI Cleanup", systemImage: "sparkles")
        }
    }

    private var swissGermanToggle: some View {
        Toggle(isOn: $useSwissGerman) {
            Label("Swiss German Spelling", systemImage: "character.bubble")
        }
    }

    private var voiceCommandsToggle: some View {
        Toggle(isOn: $enableVoiceCommands) {
            Label("Voice Edit Commands", systemImage: "scissors")
        }
    }

    private var unsupportedRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("AI Cleanup", systemImage: "sparkles")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Unavailable")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
            Text("Requires iPhone 14 or newer (at least 5 GB of RAM).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Phase 20.04 ACT-4-RESILIENCE: non-blocking diagnostic row shown only when
    /// HistoryService fell back to per-app applicationSupport storage (i.e. the
    /// `group.com.dicticus` App Group container did not resolve at launch).
    /// Surfaces the degraded state so users notice misconfigured signing /
    /// missing entitlements before they assume keyboard-extension parity.
    private var appGroupFallbackWarningRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 4) {
                Text("History storage degraded")
                    .font(.subheadline.weight(.semibold))
                Text("Dicticus is using local app storage for transcription history. History will not be visible to the Dicticus keyboard extension. Reinstall the app if this is unexpected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    /// Status row — reflects Wave 3's `llmStatus` / `isLlmReady` when the toggle is ON.
    @ViewBuilder
    private var statusRow: some View {
        switch warmupService.llmStatus {
        case .idle:
            if isModelCached {
                // Cached but not yet loaded — next launch will warm up Step 4.
                HStack {
                    Image(systemName: "arrow.clockwise.circle")
                        .foregroundStyle(.orange)
                    Text("Relaunch Dicticus to enable AI Cleanup")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            // else: .idle with no cache → download panel shows below; no extra row.
        case .loading:
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text(warmupService.llmStatus.label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        case .ready:
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("AI Cleanup Ready")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        case .failed(let reason):
            HStack(alignment: .top) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(reason)
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Download panel (D-10: inline, not modal)

    @ViewBuilder
    private var downloadPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch downloader.state {
            case .idle:
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "arrow.down.circle")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Download Required")
                            .font(.subheadline.weight(.medium))
                        Text("\(IOSModelDownloadService.modelDisplayName) \u{2248} 2.74 GB. Wi-Fi recommended.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Button {
                    if warmupService.isOnCellular {
                        showCellularDownloadWarning = true
                    } else {
                        downloader.start()
                    }
                } label: {
                    Label("Download Model", systemImage: "arrow.down.to.line")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)

            case .downloading:
                ProgressView(value: downloader.progress)
                HStack {
                    Text("\(Int(downloader.progress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(Self.formatBytesPerSec(downloader.bytesPerSec))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Button {
                    downloader.pause()
                } label: {
                    Label("Pause", systemImage: "pause.circle")
                }
                .buttonStyle(.bordered)

            case .paused:
                ProgressView(value: downloader.progress)
                Text("Paused \u{00B7} \(Int(downloader.progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    downloader.resume()
                } label: {
                    Label("Resume", systemImage: "play.circle")
                }
                .buttonStyle(.borderedProminent)

            case .completed:
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Download Complete \u{2014} relaunch Dicticus to enable")
                        .font(.subheadline)
                }

            case .failed(let reason):
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Button {
                    downloader.start()
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private static func formatBytesPerSec(_ bps: Double) -> String {
        guard bps > 0 else { return "" }
        let mbps = bps / (1024.0 * 1024.0)
        return String(format: "%.1f MB/s", mbps)
    }
}

#Preview {
    NavigationStack {
        List {
            AiCleanupSection()
        }
        .navigationTitle("Settings")
    }
    .environmentObject(IOSModelWarmupService())
}
