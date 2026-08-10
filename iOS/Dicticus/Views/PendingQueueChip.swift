import SwiftUI

/// Home's route into the pending queue (D-11) — renders only while at least one
/// recording is waiting, transcribing, or failed. `label(for:)` returning `nil` at
/// zero is what implements "not rendered at all"; the chip is never hidden with
/// opacity.
struct PendingQueueChip: View {
    let count: Int
    let onTap: () -> Void

    /// `warning` is a declared `DESIGN.md` token but iOS ships no color-asset catalog
    /// yet (confirmed absent — see `46-04-SUMMARY.md`), so this falls back to the
    /// system `.orange`, matching `WarmupStatusBanner`'s and `PendingRecordingRow`'s
    /// established convention.
    private var warningTint: Color { .orange }

    var body: some View {
        if let label = Self.label(for: count) {
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

    /// Nil at zero (renders nothing), the singular sentence at one, the plural
    /// sentence with the number above one — the two locked sentences from the
    /// UI-SPEC's Copywriting Contract, verbatim.
    static func label(for count: Int) -> String? {
        switch count {
        case 0: return nil
        case 1: return "1 recording waiting to transcribe"
        default: return "\(count) recordings waiting to transcribe"
        }
    }
}

#Preview("One waiting") {
    PendingQueueChip(count: 1, onTap: {})
        .padding()
}

#Preview("Several waiting") {
    PendingQueueChip(count: 4, onTap: {})
        .padding()
}

#Preview("Zero — renders nothing") {
    PendingQueueChip(count: 0, onTap: {})
        .padding()
}
