import SwiftUI

/// Warm-up progress row shown in the menu bar dropdown during model initialization.
///
/// States (per UI-SPEC Model Warm-up Row):
/// - Compiling: indeterminate ProgressView + "Preparing models…" caption in secondary color
/// - Ready: row is hidden entirely (showWarmupRow == false)
/// - Failed: exclamation triangle + error text in red
///
/// The row disappears automatically after warm-up completes — no user action required.
struct WarmupRow: View {
    @EnvironmentObject var warmupService: ModelWarmupService

    var body: some View {
        if warmupService.showWarmupRow {
            HStack {
                if warmupService.isWarming {
                    ProgressView()
                        .controlSize(.small)
                    Text("Preparing models\u{2026}")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if let errorMessage = warmupService.error {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
    }
}
