import SwiftUI

/// Home's route into the pending queue (D-11) — renders only while at least one
/// recording is waiting, transcribing, or failed. `label(for:)` returning `nil` at
/// zero is what implements "not rendered at all"; the chip is never hidden with
/// opacity.
struct PendingQueueChip: View {
    let waiting: Int
    let unrecoverable: Int
    let onTap: () -> Void

    /// `warning` is a declared `DESIGN.md` token but iOS ships no color-asset catalog
    /// yet (confirmed absent — see `46-04-SUMMARY.md`), so this falls back to the
    /// system `.orange`, matching `WarmupStatusBanner`'s and `PendingRecordingRow`'s
    /// established convention.
    private var warningTint: Color { .orange }

    var body: some View {
        if let label = Self.label(waiting: waiting, unrecoverable: unrecoverable) {
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
    static func label(waiting: Int, unrecoverable: Int) -> String? {
        switch (waiting, unrecoverable) {
        case (0, 0):
            return nil
        case (_, 0):
            return waiting == 1 ? "1 recording waiting to transcribe" : "\(waiting) recordings waiting to transcribe"
        case (0, _):
            return unrecoverable == 1 ? "1 recording couldn't be saved" : "\(unrecoverable) recordings couldn't be saved"
        default:
            return "\(waiting) waiting · \(unrecoverable) couldn't be saved"
        }
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
