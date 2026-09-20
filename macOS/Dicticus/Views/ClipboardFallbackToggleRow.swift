import SwiftUI

/// Settings toggle for D-3's clipboard fallback. Default ON when the key is absent — same key
/// `TextInjector.clipboardFallbackEnabled`'s default closure reads (quick 260920-9m8).
struct ClipboardFallbackToggleRow: View {

    @State private var isOn: Bool = ClipboardFallbackToggleRow.currentValue()

    private static func currentValue() -> Bool {
        // Default ON when the key has never been written.
        UserDefaults.standard.object(forKey: "leaveTranscriptOnClipboardWhenUndeliverable") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "leaveTranscriptOnClipboardWhenUndeliverable")
    }

    var body: some View {
        // Form-native row so it aligns with the sibling `LaunchAtLogin.Toggle`
        // in GeneralPane's grouped Form. A manual HStack + `.padding(.horizontal)`
        // (the menu-bar pattern) would double-inset it inside the Form's own cell
        // insets and read as nested under "Launch at login".
        Toggle("Copy transcript to clipboard when it can't be pasted", isOn: $isOn)
            .onChange(of: isOn) { _, newValue in
                UserDefaults.standard.set(newValue, forKey: "leaveTranscriptOnClipboardWhenUndeliverable")
            }
    }
}
