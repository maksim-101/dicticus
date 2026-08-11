import SwiftUI

/// A single row in History's "Pending" section — the surface D-10's clear action and
/// D-11's retry action live on. Mirrors `HistoryRow`'s outer padding/List-row shape so
/// the two sections read as one continuous list.
///
/// `durationLabel(_:)` and `statusLabel(for:)` are static pure functions on purpose:
/// they are the display contract this row must never silently drift from, and being
/// pure means the contract is machine-checked by `PendingSurfaceTests` rather than
/// eyeballed.
struct PendingRecordingRow: View {
    let recording: PendingRecording

    @EnvironmentObject var viewModel: DictationViewModel
    @EnvironmentObject var pendingStore: PendingRecordingStore
    @State private var showingClearConfirmation = false

    private var status: PendingRecordingStatus {
        PendingRecordingStatus(rawValue: recording.status) ?? .queued
    }

    /// `warning` is a declared `DESIGN.md` token but iOS ships no color-asset catalog
    /// yet (confirmed absent — see `46-04-SUMMARY.md`), so this falls back to the
    /// system `.orange`, matching `WarmupStatusBanner`'s established convention.
    private var warningTint: Color { .orange }

    /// Waiting and failed both use `warning` per the UI-SPEC's status-pill color
    /// matrix — deliberately NOT `recording` red, which `DESIGN.md` reserves for an
    /// active microphone only. Reusing it here would make a stale failure look like a
    /// live recording.
    private var pillColor: Color {
        switch status {
        case .queued, .failed: return warningTint
        case .transcribing: return .accentColor
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 4) {
                    Text(recording.createdAt, style: .date)
                    Text(recording.createdAt, style: .time)
                }
                .font(.caption)
                .foregroundColor(.secondary)

                Spacer()

                Text(Self.durationLabel(recording.durationSeconds))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                statusPill

                // The transcribing pill's motion lives on its icon, not the pill's
                // color, per the UI-SPEC's Component Inventory note.
                if status == .transcribing {
                    Image(systemName: "waveform")
                        .symbolEffect(.pulse, isActive: true)
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                }

                Spacer()

                // Queued/transcribing rows offer only Clear — their resolution is
                // automatic, so a Retry button there would imply the user has to do
                // something. A failed row offers Retry only when the row is actually
                // retryable (2026-08-11 device UAT fix) — a row recovered from a WAV
                // whose header could not be trusted can never succeed, empirically
                // confirmed, and a Retry button on it is a trap, not a recovery path.
                if status == .failed && recording.isRetryable {
                    Button("Retry") {
                        Task { await viewModel.retryPendingRecording(recording) }
                    }
                    .buttonStyle(.bordered)
                    .tint(.accentColor)
                }

                // 2026-08-11 device UAT fix: `.buttonStyle(.borderless)` is load-
                // bearing, not decoration — without an explicit style, SwiftUI can
                // promote this List row's one unstyled Button to be the row's whole
                // hit-test target (the exact bug reported: tapping ANYWHERE on the
                // row opened the delete confirmation, not just this icon). Mirrors
                // the working precedent already in this file family
                // (`HistoryRow`'s Copy button, `History/HistoryView.swift`).
                Button {
                    showingClearConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .tint(.secondary)
                .accessibilityLabel("Clear recording")
            }

            // The longest text a row can carry (per the UI-SPEC's `long-text`
            // consideration) — the two-line cap is a hard layout constraint so the
            // trailing Retry/Clear actions are never pushed off-screen.
            if status == .failed {
                Text(recording.isRetryable
                     ? "Couldn't transcribe — tap Retry, or we'll try again automatically once the model reloads."
                     : PendingRecordingStore.unrecoverableFailureReason)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
        }
        .padding(.vertical, 4)
        // D-10: clearing captured audio is the only user-initiated path that destroys
        // speech the user recorded — irreversible, and gated behind a destructive
        // confirmation whose message states plainly that the recording has not been
        // transcribed and that deletion cannot be undone (T-46-10).
        .confirmationDialog(
            "Delete Recording?",
            isPresented: $showingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                pendingStore.clear(recording)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This recording hasn't been transcribed yet. Deleting it can't be undone.")
        }
    }

    private var statusPill: some View {
        Text(Self.statusLabel(for: status))
            .font(.system(size: 11, weight: .bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(pillColor.opacity(0.15))
            .foregroundStyle(pillColor)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    /// `m:ss` for a finite non-negative value (`0:42`, `1:07`, `62:05` past an hour).
    /// Returns the `--:--` placeholder for nil, non-finite, or negative — the display
    /// contract for a recording recovered from a WAV whose header couldn't be read by
    /// 46-03's relaunch-recovery scan. A blank field or a crash there is the failure
    /// the UI-SPEC's E3 partial backstop exists to prevent; a fabricated `0:00` would
    /// be a lie about a recording that may contain real speech.
    static func durationLabel(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "--:--" }
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    /// Maps a status to its pill label. The failed row additionally carries the
    /// longer explanatory line below the pill.
    static func statusLabel(for status: PendingRecordingStatus) -> String {
        switch status {
        case .queued: return "Waiting for model"
        case .transcribing: return "Transcribing…"
        case .failed: return "Failed"
        }
    }
}

#Preview("Queued") {
    List {
        PendingRecordingRow(recording: PendingRecording(
            id: 1, uuid: UUID(), fileName: "a.wav", createdAt: Date(),
            status: PendingRecordingStatus.queued.rawValue, durationSeconds: 42,
            retryCount: 0, failureReason: nil
        ))
    }
    .environmentObject(DictationViewModel())
    .environmentObject(PendingRecordingStore.shared)
}

#Preview("Transcribing") {
    List {
        PendingRecordingRow(recording: PendingRecording(
            id: 2, uuid: UUID(), fileName: "b.wav", createdAt: Date(),
            status: PendingRecordingStatus.transcribing.rawValue, durationSeconds: 67,
            retryCount: 0, failureReason: nil
        ))
    }
    .environmentObject(DictationViewModel())
    .environmentObject(PendingRecordingStore.shared)
}

#Preview("Failed — retryable") {
    List {
        PendingRecordingRow(recording: PendingRecording(
            id: 3, uuid: UUID(), fileName: "c.wav", createdAt: Date(),
            status: PendingRecordingStatus.failed.rawValue, durationSeconds: 12,
            retryCount: 1, failureReason: "Could not understand audio."
        ))
    }
    .environmentObject(DictationViewModel())
    .environmentObject(PendingRecordingStore.shared)
}

/// A row recovered from a WAV whose header could not be trusted — empirically
/// confirmed (2026-08-11) to always fail transcription, so Retry is hidden and the
/// explanatory text is the honest permanent-failure copy, not the generic one.
#Preview("Failed — unrecoverable") {
    List {
        PendingRecordingRow(recording: PendingRecording(
            id: 4, uuid: UUID(), fileName: "d.wav", createdAt: Date(),
            status: PendingRecordingStatus.failed.rawValue, durationSeconds: nil,
            retryCount: 0, failureReason: PendingRecordingStore.unrecoverableFailureReason
        ))
    }
    .environmentObject(DictationViewModel())
    .environmentObject(PendingRecordingStore.shared)
}
