import SwiftUI

/// Per Phase 19.5 D-A2: macOS exposure of the Swiss German toggle in the
/// menu-bar dropdown, clustered with `AiCleanupInfoView`.
///
/// Reads/writes `useSwissGerman` via DicticusDefaults.suite (app-local on macOS,
/// group container on iOS — platform-conditional via the resolver).
struct SwissGermanToggleRow: View {
    private static let appGroupDefaults = UserDefaults.standard

    @State private var isOn: Bool = SwissGermanToggleRow.currentValue()

    /// B4 fix (Phase 19.5 revision): SwiftUI does not guarantee that
    /// `MenuBarExtra.task` fires before `MenuBarView`'s body first renders.
    /// If view-construction wins the race, this `currentValue()` call would
    /// read pre-migration state. Self-heal by running the migration FIRST
    /// — `runIfNeeded()` is idempotent (gated by `swissDefaultMigratedV2_1`)
    /// so duplicate execution from `MenuBarExtra.task` is a no-op.
    private static func currentValue() -> Bool {
        SwissDefaultMigration.runIfNeeded()
        // D-A1: default ON when the key has never been written.
        let defaults = appGroupDefaults
        return defaults.object(forKey: "useSwissGerman") == nil
            ? true
            : defaults.bool(forKey: "useSwissGerman")
    }

    var body: some View {
        HStack {
            Label("Swiss German Spelling", systemImage: "character.bubble")
                .font(.body)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .accessibilityLabel("Swiss German spelling")
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .onChange(of: isOn) { _, newValue in
            Self.appGroupDefaults.set(newValue, forKey: "useSwissGerman")
        }
    }
}
