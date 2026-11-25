import SwiftUI

/// Settings toggle for the live transcript overlay (Phase 51 D-14). Default ON
/// when the key is absent; HotkeyManager reads the same key and suite at press time.
///
/// Storage goes through `DicticusDefaults.suite` (not `.standard`) so the test
/// bootstrap's ephemeral override keeps tests off the real defaults domain.
struct LiveOverlayToggleRow: View {

    @State private var isOn: Bool = LivePreviewSession.isEnabled(DicticusDefaults.suite)

    var body: some View {
        Toggle("Show live transcript while dictating", isOn: $isOn)
            .onChange(of: isOn) { _, newValue in
                DicticusDefaults.suite.set(newValue, forKey: LivePreviewSession.enabledKey)
            }
    }
}
