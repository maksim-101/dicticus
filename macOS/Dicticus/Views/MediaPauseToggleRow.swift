import SwiftUI

/// Settings toggle for PTT media auto-pause. Default ON when the key is absent.
///
/// Reads/writes `UserDefaults.standard` (macOS-only feature; NOT the App Group
/// suite — no cross-platform sync needed for this toggle).
struct MediaPauseToggleRow: View {

    @State private var isOn: Bool = MediaPauseToggleRow.currentValue()

    private static func currentValue() -> Bool {
        // Default ON when the key has never been written.
        UserDefaults.standard.object(forKey: "pauseMediaDuringDictation") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "pauseMediaDuringDictation")
    }

    var body: some View {
        // Form-native row so it aligns with the sibling `LaunchAtLogin.Toggle`
        // in GeneralPane's grouped Form. A manual HStack + `.padding(.horizontal)`
        // (the menu-bar pattern) would double-inset it inside the Form's own cell
        // insets and read as nested under "Launch at login".
        Toggle("Pause media while dictating", isOn: $isOn)
            .onChange(of: isOn) { _, newValue in
                UserDefaults.standard.set(newValue, forKey: "pauseMediaDuringDictation")
            }
    }
}
