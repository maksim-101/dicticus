import SwiftUI
import WhisperKit
import KeyboardShortcuts
import Sparkle

@main
struct DicticusApp: App {
    @StateObject private var permissionManager = PermissionManager()
    @StateObject private var warmupService = ModelWarmupService()
    @StateObject private var hotkeyManager = HotkeyManager()
    @StateObject private var modifierListener = ModifierHotkeyListener()
    @StateObject private var updater = SparkleUpdater()

    // TranscriptionService is created once from the warm WhisperKit instance.
    // Held here so Phase 3 hotkey wiring can access it without re-initialization.
    // Optional because it cannot be created until warmup completes.
    @State private var transcriptionService: TranscriptionService?

    // CleanupService is created during warmup (ModelWarmupService Step 4).
    // Exposed here for icon state machine (D-14/D-15) and passed to HotkeyManager.
    // Optional because it cannot be created until LLM warmup completes.
    @State private var cleanupService: CleanupService?

    // TextProcessingService orchestrates Dictionary, ITN, and CleanupService.
    @State private var textProcessingService: TextProcessingService?

    // Phase 20.08 D-02: openWindow accessor for the DEBUG-only Cleanup Spike
    // command. Declared at the App level so the .commands menu entry below can
    // imperatively open the spike window. Always available; only the menu
    // entry that uses it is gated by #if DEBUG.
    @Environment(\.openWindow) private var openWindow

    // Stage Manager fix (Finding 5): track how many auxiliary windows (Dictionary,
    // History, Settings) are currently open. When the count goes 0→1 we promote to
    // .regular so Stage Manager groups these windows under a real app identity (with a
    // transient Dock icon). When the count returns to 0 we restore .accessory so the
    // app vanishes from the Dock and Cmd-Tab again — matching the pure menu-bar default.
    @State private var auxiliaryWindowCount = 0

    private func auxiliaryWindowOpened() {
        auxiliaryWindowCount += 1
        if auxiliaryWindowCount == 1 {
            NSApp.setActivationPolicy(.regular)
            // Bring the newly-opened window to the front. Without this the window can
            // open behind the currently-active Stage Manager group.
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func auxiliaryWindowClosed() {
        auxiliaryWindowCount = max(0, auxiliaryWindowCount - 1)
        if auxiliaryWindowCount == 0 {
            // Brief delay so Stage Manager can process the window closure before the
            // app's entry disappears from its strip, avoiding a jarring instant removal.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverRoot()
                .environmentObject(permissionManager)
                .environmentObject(warmupService)
                .environmentObject(hotkeyManager)
                .environmentObject(modifierListener)
                .environmentObject(updater)
        } label: {
            // Icon state logic per UI-SPEC three-state machine:
            //   recording -> mic.circle.fill (red) per D-09
            //   transcribing -> waveform.circle (pulsing) per D-11
            //   idle/warming -> mic (pulsing during warm-up per D-04)
            // symbolEffect(.pulse) requires macOS 14+ — verified in Research Pattern 1.
            //
            // macOS renders menu bar icons as template images, stripping color.
            // To show red during recording, we use NSImage with isTemplate=false.
            menuBarIcon
                .symbolEffect(.pulse, isActive: warmupService.isWarming
                    || (hotkeyManager.pipelineState == .transcribing)
                    || (hotkeyManager.pipelineState == .cleaning))
                .task {
                    AppLocalMigrationService.runIfNeeded()  // 36.3 — migrate group container → app-local (runs before any service init)
                    SwissDefaultMigration.runIfNeeded()  // D-A3 — must precede any useSwissGerman reader
                    // Check permissions at launch so iconName reads correct state immediately
                    // (prevents mic.slash showing when permissions are already granted but
                    // status is still .pending from init)
                    permissionManager.checkAll()
                    warmupService.warmup()

                    // R-06: optional single-fire revert-to-raw hotkey (default: nil —
                    // never claims a combo unprompted). Independent of ASR/LLM warmup;
                    // only needs history + the existing TextInjector.
                    KeyboardShortcuts.onKeyUp(for: .revertToRaw) {
                        Task { await revertToRaw() }
                    }
                }
                .onChange(of: warmupService.isReady) { _, isReady in
                    if isReady,
                       let whisperKit = warmupService.whisperKitInstance {
                        let service = TranscriptionService(whisperKit: whisperKit)
                        transcriptionService = service

                        // CleanupService may be nil here — LLM loads after ASR.
                        // Plain dictation works immediately; AI cleanup wires later.
                        let cleanup = warmupService.cleanupServiceInstance
                        cleanupService = cleanup
                        
                        let processingService = TextProcessingService(cleanupService: cleanup)
                        textProcessingService = processingService

                        hotkeyManager.setup(
                            transcriptionService: service,
                            warmupService: warmupService,
                            textProcessingService: processingService
                        )

                        // D-08: Wire modifier hotkey listener after ASR is ready so
                        // Fn+Shift / Fn+Control only activate when the app can record.
                        hotkeyManager.setupModifierListener(modifierListener)
                    }
                }
                .onChange(of: warmupService.isLlmReady) { _, ready in
                    // LLM finished loading after ASR was already ready.
                    // Wire CleanupService into HotkeyManager and icon state.
                    if ready, let cleanup = warmupService.cleanupServiceInstance {
                        cleanupService = cleanup

                        let processingService = TextProcessingService(cleanupService: cleanup)
                        textProcessingService = processingService
                        hotkeyManager.textProcessingService = processingService
                        hotkeyManager.cleanupService = cleanup
                    }
                }
                // Stage Manager fix: listen for auxiliary-window open/close notifications
                // posted by DictionaryView, HistoryView, and SettingsRoot (Finding 5).
                .onReceive(NotificationCenter.default.publisher(for: .dicticusAuxWindowOpened)) { _ in
                    auxiliaryWindowOpened()
                }
                .onReceive(NotificationCenter.default.publisher(for: .dicticusAuxWindowClosed)) { _ in
                    auxiliaryWindowClosed()
                }
        }
        .menuBarExtraStyle(.window)

        // Window for managing the custom dictionary (TEXT-02)
        WindowGroup("Manage Dictionary", id: "dictionary") {
            DictionaryView()
                .environmentObject(DictionaryService.shared)
        }

        // Window for browsing transcription history (UX-02)
        WindowGroup("History", id: "history") {
            HistoryView()
                .environmentObject(HistoryService.shared)
        }

        // ⌘, Settings window — 4-pane (Hotkeys / AI Cleanup / General / About).
        // The Settings scene auto-registers ⌘, as the keyboard shortcut (no manual .keyboardShortcut needed).
        // Coexists cleanly with the dictionary/history WindowGroups (spike-verified, Q-03).
        Settings {
            SettingsRoot()
                .environmentObject(permissionManager)
                .environmentObject(warmupService)
                .environmentObject(hotkeyManager)
                .environmentObject(modifierListener)
                .environmentObject(updater)
        }

#if DEBUG
        // Phase 20.08 D-02: prompt-spike harness for AI-cleanup A/B comparison.
        // DEBUG-only — kept behind #if DEBUG for future LLM-prompt iterations
        // rather than removed after Phase 20.08 ships (D-Discretion).
        WindowGroup("Cleanup Spike", id: "cleanup-spike") {
            if let cleanup = cleanupService {
                CleanupSpikeView()
                    .environmentObject(cleanup)
            } else {
                Text("CleanupService not loaded yet — wait for warmup.")
                    .padding()
            }
        }
        .commands {
            CommandGroup(after: .windowList) {
                Button("Cleanup Spike (Debug)…") {
                    openWindow(id: "cleanup-spike")
                }
                .keyboardShortcut("k", modifiers: [.command, .shift, .option])
            }
        }
#endif
    }

    /// Menu bar icon view — uses a colored NSImage for recording (isTemplate=false bypasses
    /// macOS template rendering), standard SF Symbol for all other states.
    @ViewBuilder
    private var menuBarIcon: some View {
        if hotkeyManager.pipelineState == .recording {
            let config = NSImage.SymbolConfiguration(paletteColors: [.systemRed])
            let image = NSImage(systemSymbolName: "mic.circle.fill", accessibilityDescription: "Recording")!
                .withSymbolConfiguration(config)!
            // isTemplate=false prevents macOS from stripping color in menu bar
            let _ = (image.isTemplate = false)
            Image(nsImage: image)
        } else {
            Image(systemName: iconName)
        }
    }

    /// Computed icon name combining permission, warm-up, recording, transcription, and cleanup state.
    ///
    /// State priority (highest first):
    ///   1. Permission missing -> mic.slash (degraded)
    ///   2. Recording -> mic.fill (D-09: red filled mic)
    ///   3. Transcribing -> waveform.circle (D-11/UI-SPEC: audio processing indicator)
    ///   4. AI cleanup -> sparkles (D-14/D-15: LLM processing indicator, pulsing)
    ///   5. Default -> mic (ready or warming, pulse animation handles warming)
    private var iconName: String {
        if !permissionManager.allGranted {
            return "mic.slash"  // Degraded: missing permissions
        }
        switch hotkeyManager.pipelineState {
        case .recording:
            return "mic.circle.fill"  // D-09: Recording in progress — distinct shape at menu bar size
        case .transcribing:
            return "waveform.circle"  // D-11/UI-SPEC: Transcription in progress
        case .cleaning:
            return "sparkles"  // D-14/D-15: AI cleanup in progress
        case .idle:
            return "mic"  // Ready or warming (pulse animation handles warming per Phase 1)
        }
    }
}
