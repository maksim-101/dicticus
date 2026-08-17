import SwiftUI

/// Home's route into the pending queue (D-11) — renders only while at least one
/// recording is waiting, transcribing, or failed. `label(for:)` returning `nil` at
/// zero is what implements "not rendered at all"; the chip is never hidden with
/// opacity.
struct PendingQueueChip: View {
    let waiting: Int
    let unrecoverable: Int
    /// How many of `waiting`'s total are actively `.transcribing` right now, vs
    /// merely `.queued`. Defaults to 0 so every pre-existing call site keeps
    /// compiling and producing identical copy. See `label(waiting:unrecoverable:transcribing:)`.
    let transcribing: Int
    let onTap: () -> Void

    init(waiting: Int, unrecoverable: Int, transcribing: Int = 0, onTap: @escaping () -> Void) {
        self.waiting = waiting
        self.unrecoverable = unrecoverable
        self.transcribing = transcribing
        self.onTap = onTap
    }

    /// `warning` is a declared `DESIGN.md` token but iOS ships no color-asset catalog
    /// yet (confirmed absent — see `46-04-SUMMARY.md`), so this falls back to the
    /// system `.orange`, matching `WarmupStatusBanner`'s and `PendingRecordingRow`'s
    /// established convention.
    private var warningTint: Color { .orange }

    var body: some View {
        if let label = Self.label(waiting: waiting, unrecoverable: unrecoverable, transcribing: transcribing) {
            Button(action: onTap) {
                HStack(spacing: 8) {
                    Image(systemName: "tray.full")
                        .foregroundStyle(warningTint)

                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(warningTint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
        }
    }

    /// Nil when both are zero (renders nothing). Waiting-only and unrecoverable-only
    /// keep their own singular/plural sentences; when both are nonzero, a single
    /// mixed sentence states both counts — the approved copy (UAT finding F,
    /// 2026-08-15).
    ///
    /// `transcribing` (2026-08-17, third checkpoint round on the same "waiting for
    /// transcription" complaint — the first two rounds fixed `PendingRecordingRow`'s
    /// per-row pill and never touched this chip, which is the component the user was
    /// actually looking at on the main Dictation screen): how many of `waiting`'s
    /// total are actively `PendingRecordingStatus.transcribing` right now, vs merely
    /// `.queued`. Defaults to 0 so every existing call site/test that omits it keeps
    /// producing byte-identical copy. This parameter changes ONLY the wording — it
    /// never changes which of `waiting`/`unrecoverable` renders, their totals, or
    /// `PendingRecordingStore.waitingCount`'s locked definition (46-05-PLAN.md).
    /// Previously any nonzero `waiting` always read "waiting to transcribe" even once
    /// a recording's decode had actually started — invisible under Whisper's ~4s
    /// decode, but visible and confusing once Parakeet's much faster decode made
    /// "waiting" read as wrong for a recording already in flight.
    static func label(waiting: Int, unrecoverable: Int, transcribing: Int = 0) -> String? {
        switch (waiting, unrecoverable) {
        case (0, 0):
            return nil
        case (_, 0):
            return waitingSentence(waiting: waiting, transcribing: transcribing)
        case (0, _):
            return unrecoverable == 1 ? "1 recording couldn't be saved" : "\(unrecoverable) recordings couldn't be saved"
        default:
            return "\(waitingPhrase(waiting: waiting, transcribing: transcribing)) · \(unrecoverable) couldn't be saved"
        }
    }

    /// The waiting-only sentence (no unrecoverable rows). Three cases: nothing yet
    /// transcribing (byte-identical to the pre-2026-08-17 copy), everything
    /// transcribing (the common solo-recording case this fix targets), or a genuine
    /// mix of both.
    private static func waitingSentence(waiting: Int, transcribing: Int) -> String {
        if transcribing == 0 {
            return waiting == 1 ? "1 recording waiting to transcribe" : "\(waiting) recordings waiting to transcribe"
        }
        if transcribing == waiting {
            return waiting == 1 ? "Transcribing 1 recording\u{2026}" : "Transcribing \(waiting) recordings\u{2026}"
        }
        return "Transcribing \(transcribing) of \(waiting) recordings\u{2026}"
    }

    /// The compact clause used inside the mixed (waiting + unrecoverable) sentence —
    /// same three cases as `waitingSentence(waiting:transcribing:)` above, phrased to
    /// read naturally before " · N couldn't be saved" instead of as a standalone
    /// sentence. With `transcribing == 0` this is exactly the pre-2026-08-17 "N
    /// waiting" clause.
    private static func waitingPhrase(waiting: Int, transcribing: Int) -> String {
        if transcribing == 0 {
            return "\(waiting) waiting"
        }
        if transcribing == waiting {
            return "\(waiting) transcribing"
        }
        return "\(transcribing) of \(waiting) transcribing"
    }
}

#Preview("One waiting") {
    PendingQueueChip(waiting: 1, unrecoverable: 0, onTap: {})
        .padding()
}

#Preview("Several waiting") {
    PendingQueueChip(waiting: 4, unrecoverable: 0, onTap: {})
        .padding()
}

#Preview("Zero — renders nothing") {
    PendingQueueChip(waiting: 0, unrecoverable: 0, onTap: {})
        .padding()
}

#Preview("Couldn't be saved") {
    PendingQueueChip(waiting: 0, unrecoverable: 2, onTap: {})
        .padding()
}

#Preview("Mixed") {
    PendingQueueChip(waiting: 2, unrecoverable: 1, onTap: {})
        .padding()
}

#Preview("Solo — actively transcribing") {
    PendingQueueChip(waiting: 1, unrecoverable: 0, transcribing: 1, onTap: {})
        .padding()
}

#Preview("Mixed queued + transcribing") {
    PendingQueueChip(waiting: 3, unrecoverable: 0, transcribing: 1, onTap: {})
        .padding()
}
