import SwiftUI
import AppKit

/// Settings → AI Cleanup pane.
///
/// Group "Model": model name row + LLM status + Configure Prompt button.
/// Group "Language": Swiss German toggle (app-local UserDefaults on macOS).
///
/// Relocates content from AiCleanupInfoView + SwissGermanToggleRow per UIORG-04.
struct AiCleanupPane: View {
    @EnvironmentObject var warmupService: ModelWarmupService
    @State private var showPromptEditor = false

    var body: some View {
        Form {
            Section("Model") {
                LabeledContent(ModelDownloadService.modelDisplayName) {
                    statusView
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(warmupService.llmStatus == .ready ? "Model ready" : warmupService.llmStatus.label)

                LabeledContent("Cleanup prompt") {
                    Button("Configure…") {
                        showPromptEditor.toggle()
                    }
                    .popover(isPresented: $showPromptEditor, arrowEdge: .trailing) {
                        PromptEditorView(isPresented: $showPromptEditor)
                    }
                }
            }

            Section("Language") {
                SwissGermanFormRow()
            }

            Section("Voice Commands") {
                VoiceCommandsFormRow()
            }

            Section("Context-Aware Formatting") {
                ContextAwareFormattingFormRow()
                Text("Overrides below apply only while context-aware formatting is enabled above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ContextOverridesEditor()
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var statusView: some View {
        HStack(spacing: 4) {
            if warmupService.llmStatus.isActive {
                ProgressView()
                    .controlSize(.small)
            }
            Text(warmupService.llmStatus.label)
                .foregroundStyle(statusColor)
        }
    }

    private var statusColor: Color {
        switch warmupService.llmStatus {
        case .ready:   return Color(red: 0.17, green: 0.64, blue: 0.44)   // DESIGN.md `ready` light
        case .failed:  return .red
        case .downloading, .loading: return .orange
        case .idle:    return .secondary
        }
    }
}

/// Swiss German toggle row styled for a Settings Form (LabeledContent layout).
///
/// Backs the `useSwissGerman` key in app-local UserDefaults on macOS.
private struct SwissGermanFormRow: View {
    private static let appGroupDefaults = UserDefaults.standard

    @State private var isOn: Bool = SwissGermanFormRow.currentValue()

    private static func currentValue() -> Bool {
        SwissDefaultMigration.runIfNeeded()
        let defaults = appGroupDefaults
        return defaults.object(forKey: "useSwissGerman") == nil
            ? true
            : defaults.bool(forKey: "useSwissGerman")
    }

    var body: some View {
        Toggle("Swiss German spelling (ß→ss)", isOn: $isOn)
            .onChange(of: isOn) { _, newValue in
                Self.appGroupDefaults.set(newValue, forKey: "useSwissGerman")
            }
    }
}

/// Voice edit commands toggle row (Phase 39/D-07) — a UX escape hatch for
/// users who dictate ABOUT editing, not the safety mechanism. Always
/// visible, unconditionally, like `SwissGermanFormRow`, so a user whose
/// text is being unexpectedly edited can find the escape hatch even in a
/// degraded state.
///
/// Backs the `enableVoiceCommands` key in app-local UserDefaults on macOS
/// — the same key `TextProcessingService` reads via `DicticusDefaults.suite`.
private struct VoiceCommandsFormRow: View {
    private static let appGroupDefaults = UserDefaults.standard

    @State private var isOn: Bool = VoiceCommandsFormRow.currentValue()

    private static func currentValue() -> Bool {
        let defaults = appGroupDefaults
        return defaults.object(forKey: "enableVoiceCommands") == nil
            ? true
            : defaults.bool(forKey: "enableVoiceCommands")
    }

    var body: some View {
        Toggle("Voice edit commands (e.g. \u{201C}scratch that\u{201D})", isOn: $isOn)
            .onChange(of: isOn) { _, newValue in
                Self.appGroupDefaults.set(newValue, forKey: "enableVoiceCommands")
            }
    }
}

/// Context-aware formatting disable toggle (Phase 38 Plan 03, D-09, CTXFMT-03).
///
/// Backs `ContextResolver.enabledKey` on `DicticusDefaults.suite` — the same
/// suite `ContextResolver.isEnabled` reads at `HotkeyManager`'s press-time
/// resolve call, so this row is the single source of truth for whether
/// context-aware formatting runs at all. Disabled ⇒ `ContextResolver.resolve`
/// always returns `.default`, i.e. exactly today's (pre-Phase-38) behavior.
private struct ContextAwareFormattingFormRow: View {
    @State private var isOn: Bool = ContextResolver.isEnabled(DicticusDefaults.suite)

    var body: some View {
        Toggle("Context-aware formatting", isOn: $isOn)
            .onChange(of: isOn) { _, newValue in
                DicticusDefaults.suite.set(newValue, forKey: ContextResolver.enabledKey)
            }
    }
}

/// One installed/running app, as offered by the override editor's app picker
/// (2026-07-26 UAT finding — see `ContextOverridesEditor.loadInstalledApps`).
/// Display-only; `ContextResolver`'s storage format stays keyed by raw
/// `bundleID` string, unaffected by this view-layer convenience.
private struct InstalledAppEntry: Hashable {
    let displayName: String
    let bundleID: String
}

/// The override editor's "add" form app-selection state: either a concrete
/// picked app (by bundle ID) or the manual "Other…" fallback that reveals
/// the raw bundle-ID `TextField` for apps not enumerated by
/// `ContextOverridesEditor.loadInstalledApps`.
private enum AppPickerSelection: Hashable {
    case app(String)
    case other
}

/// Inline "app → context" override editor (Phase 38 Plan 03, D-05, CTXFMT-03).
///
/// Follows `DictionaryPane`'s inline-list-with-add-form pattern rather than
/// standing up a separate manager window for a handful of reassignments.
/// Reads/writes go exclusively through `ContextResolver.loadGuarded`/`save` —
/// this view never writes the override map to `UserDefaults` directly, so the
/// present-but-unreadable → suppress-seed + rolling-backup data-loss guard
/// (RESEARCH Pitfall 4) is always honored.
private struct ContextOverridesEditor: View {
    @State private var overrides: [String: DictationContext] = [:]
    @State private var showingAddForm = false
    @State private var newBundleID = ""
    @State private var newContext: DictationContext = .default
    @State private var installedApps: [InstalledAppEntry] = []
    @State private var appSelection: AppPickerSelection = .other
    /// CR-01 fix: `ContextResolver.loadGuarded`'s `suppressSeed` signal was
    /// computed but never consulted, so a present-but-unreadable override
    /// blob was shown identically to "no overrides configured" — and the
    /// next edit would silently overwrite it. This flag makes the signal
    /// actionable: `reload()` sets it, and the banner below warns the user
    /// instead of presenting an empty list as if it were the real state.
    @State private var overridesUnreadable = false

    private var sortedOverrideIDs: [String] {
        overrides.keys.sorted()
    }

    var body: some View {
        Group {
            if overridesUnreadable {
                Label(
                    "Your saved app overrides could not be read and are not shown below. Adding or editing an override here will overwrite them — restore first if you want to recover them.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)

                // WR-01 fix: `save()` already stashes the previous blob into
                // `overridesBackupKey` before every overwrite, but nothing
                // read it back — a corrupted-then-overwritten map was only
                // recoverable via a manual `defaults read`. This button
                // gives the same rolling backup a real, user-facing recovery
                // path.
                Button("Restore previous overrides") {
                    restoreFromBackup()
                }
                .buttonStyle(.bordered)
            }

            ForEach(sortedOverrideIDs, id: \.self) { bundleID in
                HStack {
                    Text(bundleID)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Picker("Context for \(bundleID)", selection: bindingForOverride(bundleID)) {
                        ForEach(DictationContext.allCases, id: \.self) { context in
                            Text(context.rawValue.capitalized).tag(context)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 180)

                    Button {
                        removeOverride(bundleID)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove override for \(bundleID)")
                }
            }

            if showingAddForm {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        // UAT finding (2026-07-26, user-requested): raw bundle-ID entry
                        // was too technical ("I don't know what the bundle ID of iTerm
                        // is"). Primary path is now an app picker; manual bundle-ID
                        // entry survives as the "Other…" fallback below for apps not
                        // enumerated (e.g. not currently running and not in /Applications).
                        Picker("App", selection: $appSelection) {
                            ForEach(installedApps, id: \.bundleID) { app in
                                Text("\(app.displayName) (\(app.bundleID))")
                                    .tag(AppPickerSelection.app(app.bundleID))
                            }
                            Divider()
                            Text("Other… (enter bundle ID manually)")
                                .tag(AppPickerSelection.other)
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: 260)
                        .onChange(of: appSelection) { _, newValue in
                            switch newValue {
                            case .app(let bundleID): newBundleID = bundleID
                            case .other: newBundleID = ""
                            }
                        }

                        Picker("New override context", selection: $newContext) {
                            ForEach(DictationContext.allCases, id: \.self) { context in
                                Text(context.rawValue.capitalized).tag(context)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 100)

                        Button("Add") {
                            addOverride()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(newBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("Save app override")

                        Button("Cancel") {
                            cancelAdd()
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Cancel adding override")
                    }

                    if appSelection == .other {
                        TextField("Bundle ID (e.g. com.example.app)", text: $newBundleID)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            } else {
                Button("+ Add App Override") {
                    appSelection = .other
                    showingAddForm = true
                    // WR-03 fix: loadInstalledApps() enumerates every .app bundle
                    // in /Applications (FileManager + Bundle/Info.plist parsing)
                    // — blocking I/O that stalled the popover when run
                    // synchronously on the MainActor inside this button action.
                    Task.detached(priority: .userInitiated) {
                        let apps = Self.loadInstalledApps()
                        await MainActor.run { installedApps = apps }
                    }
                }
                .accessibilityLabel("Add app formatting override")
            }

            DisclosureGroup("Built-in defaults (read-only)") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(ContextResolver.curatedMap.keys.sorted(), id: \.self) { bundleID in
                        LabeledContent(bundleID, value: ContextResolver.curatedMap[bundleID]!.rawValue.capitalized)
                            .font(.system(.caption, design: .monospaced))
                    }
                }
                .padding(.top, 4)
            }
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        let result = ContextResolver.loadGuarded(from: DicticusDefaults.suite, key: ContextResolver.overridesKey)
        overrides = result.overrides
        overridesUnreadable = result.suppressSeed
    }

    private func persist() {
        ContextResolver.save(overrides, to: DicticusDefaults.suite, key: ContextResolver.overridesKey, backupKey: ContextResolver.overridesBackupKey)
    }

    /// WR-01 fix: reads the rolling backup blob `save()` stashed before its
    /// last overwrite and restores it as the live override map, so a
    /// present-but-unreadable trip of the CR-01 guard has a real recovery
    /// path instead of requiring a manual `defaults read`/`write`.
    private func restoreFromBackup() {
        let backup = ContextResolver.loadGuarded(from: DicticusDefaults.suite, key: ContextResolver.overridesBackupKey)
        overrides = backup.overrides
        overridesUnreadable = false
        persist()
    }

    private func bindingForOverride(_ bundleID: String) -> Binding<DictationContext> {
        Binding(
            get: { overrides[bundleID] ?? .default },
            set: { newValue in
                overrides[bundleID] = newValue
                persist()
            }
        )
    }

    private func addOverride() {
        let trimmed = newBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        overrides[trimmed] = newContext
        persist()
        cancelAdd()
    }

    private func removeOverride(_ bundleID: String) {
        overrides.removeValue(forKey: bundleID)
        persist()
    }

    private func cancelAdd() {
        showingAddForm = false
        newBundleID = ""
        newContext = .default
        appSelection = .other
    }

    /// UAT finding (2026-07-26): enumerate installed/running apps for the
    /// override editor's app picker, so the user doesn't need to know a raw
    /// bundle ID (e.g. "what's iTerm2's bundle ID?"). Sources are UNIONed and
    /// deduped by bundle ID, preferring the richer `localizedName` from a
    /// running app over the on-disk display name when both exist.
    nonisolated private static func loadInstalledApps() -> [InstalledAppEntry] {
        var byBundleID: [String: InstalledAppEntry] = [:]

        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let bundleID = app.bundleIdentifier else { continue }
            byBundleID[bundleID] = InstalledAppEntry(displayName: app.localizedName ?? bundleID, bundleID: bundleID)
        }

        if let entries = try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: "/Applications"),
            includingPropertiesForKeys: nil
        ) {
            for url in entries where url.pathExtension == "app" {
                guard let bundleID = Bundle(url: url)?.bundleIdentifier, byBundleID[bundleID] == nil else { continue }
                byBundleID[bundleID] = InstalledAppEntry(
                    displayName: FileManager.default.displayName(atPath: url.path),
                    bundleID: bundleID
                )
            }
        }

        return byBundleID.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }
}
