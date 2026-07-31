import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var warmupService: IOSModelWarmupService
    @Environment(\.dismiss) var dismiss
    @State private var showingModelInfo = false
    @AppStorage("hasSeenOnboardingTour") private var hasSeenOnboardingTour = false

    var body: some View {
        NavigationStack {
            List {
                Section("Transcriptions") {
                    NavigationLink(destination: SpokenPunctuationReferenceView()) {
                        Label("Spoken Punctuation", systemImage: "character.textbox")
                    }

                    Toggle(isOn: appGroupBinding("useCustomDictionary", default: true)) {
                        Label("Apply Replacements", systemImage: "character.cursor.ibeam")
                    }

                    Toggle(isOn: appGroupBinding("useITN", default: true)) {
                        Label("Numbers to Digits", systemImage: "number")
                    }

                    Toggle(isOn: appGroupBinding("useAutoStop", default: true)) {
                        Label("Auto-Stop Recording", systemImage: "stop.circle")
                    }
                }

                AiCleanupSection()   // Phase 19 Wave 4 — CLEAN-01

                Section {
                    Picker("Copy from history rows", selection: copyModeBinding) {
                        Text("Raw").tag(CleanupCopyMode.raw)
                        Text("Polished").tag(CleanupCopyMode.polished)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("settings.copyMode")
                } header: {
                    Text("History")
                } footer: {
                    Text("Choose what the Copy button on each history row puts on your clipboard. Raw = unedited ASR output; Polished = post-cleanup text.")
                }

                Section("Integration") {
                    NavigationLink(destination: SetupGuidesView()) {
                        Label("Setup Guides", systemImage: "questionmark.circle")
                    }

                    Button(action: { hasSeenOnboardingTour = false }) {
                        Label("Show Onboarding Tour", systemImage: "arrow.counterclockwise")
                    }

                    Button(action: openSystemSettings) {
                        Label("System Permissions", systemImage: "gear")
                    }
                }

                Section("Model Management") {
                    HStack {
                        Label("ASR Model", systemImage: "cpu")
                        Spacer()
                        Button {
                            showingModelInfo = true
                        } label: {
                            Image(systemName: "info.circle")
                        }
                        .buttonStyle(.borderless)
                        if warmupService.hasModels {
                            Text("Ready").foregroundColor(.green)
                        } else {
                            Text("Missing").foregroundColor(.red)
                        }
                    }

                    Button(role: .destructive, action: { warmupService.warmup() }) {
                        Label("Force Model Update", systemImage: "arrow.clockwise")
                    }
                    .disabled(warmupService.isWarming)
                }

                Section("What's New") {
                    ForEach(AppBuildInfo.recentChanges, id: \.self) { note in
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Link(destination: URL(string: "https://github.com/maksim-101/dicticus")!) {
                        Label("Source Code", systemImage: "link")
                    }
                } header: {
                    Text("About")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(AppBuildInfo.displayVersion)
                        if let date = AppBuildInfo.buildDate {
                            Text("Built \(date)")
                        }
                        Text("\u{00A9} 2026 Maksim-101")
                    }
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingModelInfo) {
                NavigationStack {
                    List {
                        Section("Model") {
                            LabeledContent("Name", value: "Whisper large-v3-turbo")
                            LabeledContent("Provider", value: "OpenAI / Argmax (WhisperKit)")
                            LabeledContent("Parameters", value: "~809M")
                            LabeledContent("Size on Disk", value: "~626 MB (CoreML)")
                        }
                        Section("Capabilities") {
                            LabeledContent("Languages", value: "99 (incl. DE, EN)")
                            LabeledContent("German WER", value: "TBD (pending D-07)")
                            LabeledContent("English WER", value: "TBD (pending D-07)")
                            LabeledContent("Compute", value: "Apple Neural Engine")
                        }
                        Section {
                            Text("Whisper large-v3-turbo is a multilingual speech recognition model optimized for Apple Neural Engine via CoreML. It runs entirely on-device — no audio is sent to any server.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .navigationTitle("ASR Model Info")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingModelInfo = false }
                        }
                    }
                }
                .presentationDetents([.medium])
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var copyModeBinding: Binding<CleanupCopyMode> {
        Binding(
            get: { CleanupCopyMode.current },
            set: { CleanupCopyMode.current = $0 }
        )
    }

    private static let appGroupDefaults = UserDefaults(suiteName: "group.com.dicticus")!

    private func appGroupBinding(_ key: String, default defaultValue: Bool) -> Binding<Bool> {
        Binding(
            get: {
                let defaults = Self.appGroupDefaults
                return defaults.object(forKey: key) == nil ? defaultValue : defaults.bool(forKey: key)
            },
            set: { Self.appGroupDefaults.set($0, forKey: key) }
        )
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(IOSModelWarmupService())
}
