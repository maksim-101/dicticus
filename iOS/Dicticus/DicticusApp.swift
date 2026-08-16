import SwiftUI
import WhisperKit
import ActivityKit

@main
struct DicticusApp: App {
    @StateObject private var warmupService = IOSModelWarmupService()
    @ObservedObject private var dictionaryService = DictionaryService.shared
    @ObservedObject private var historyService = HistoryService.shared
    @StateObject private var viewModel = DictationViewModel()

    @State private var transcriptionService: IOSTranscriptionService?
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("hasSeenWhatsNewV2") private var hasSeenWhatsNewV2 = false
    @AppStorage("hasSeenOnboardingTour") private var hasSeenOnboardingTour = false
    @State private var showingWhatsNew = false
    @State private var showingOnboardingTour = false

    @Environment(\.scenePhase) private var scenePhase

    init() {
        // ADDENDUM A (extended 46-03): On launch, reconcile everything a prior process
        // may have left behind mid-recording (crash, SIGKILL, jetsam, force-quit).
        // Deliberately ONE ordered Task, not two independent ones — a killed recording
        // leaves BOTH an orphaned Live Activity and (as of 46-02/46-03) an orphaned WAV
        // on disk, and ending the stale activity BEFORE the WAV recovery scan runs means
        // there is no window where the UI could show a stale "Recording…" banner while
        // pending-recording rows are still being reconciled underneath it.
        //
        // The Live Activity end-loop itself only closes the gap once the app relaunches —
        // ActivityKit gives app code no way to end or update an Activity while its owning
        // process is dead (see 46-DEVICE-TEST-PROCEDURE.md Section D's 2026-08-10 finding:
        // a force-quit mid-recording leaves the activity visibly counting until the next
        // launch, which is this loop; there is no faster in-process fix available without
        // a server-pushed ActivityKit update, which this strictly-local project does not
        // run).
        Task { @MainActor in
            let activities = Activity<DictationAttributes>.activities
            for activity in activities {
                await activity.end(
                    ActivityContent(
                        state: DictationAttributes.ContentState(isRecording: false, startedAt: Date.now),
                        staleDate: nil
                    ),
                    dismissalPolicy: .immediate
                )
            }
            // D-01/46-03: find any WAV left on disk by a process that died before
            // enqueue() ran, and reconcile rows against disk in the other direction
            // (missing file -> failed, stranded .transcribing -> reset to .queued).
            PendingRecordingStore.shared.recoverOrphanedRecordings()
        }
        DicticusIPCBridge.defaults?.set(false, forKey: DicticusIPCBridge.Key.isRecording)
    }

    var body: some Scene {
        WindowGroup {
            if !DeviceCapabilityGate.isCurrentDeviceSupported {
                // WHISP-05: runtime iPhone 15+ (A16) floor. Short-circuits before
                // OnboardingView/ContentView ever mount, so warmup() (and its
                // ~626 MB WhisperKit large-v3-turbo download) never fires on a
                // device that can't run the model.
                UnsupportedDeviceView()
            } else if hasCompletedOnboarding {
                ContentView()
                    .environmentObject(warmupService)
                    .environmentObject(dictionaryService)
                    .environmentObject(historyService)
                    .environmentObject(viewModel)
                    .environmentObject(PendingRecordingStore.shared)
                    .onOpenURL { url in
                        if url.scheme == "dicticus" && url.host == "dictate" {
                            // WR-03: only set the App Group flag — do NOT also post .startDictation.
                            // Posting both causes a double-start race: the notification fires
                            // startDictation() at T=0, then scenePhase .active fires at T=~0
                            // which calls handleForeground(pendingDictation:true) →
                            // checkPendingIntent() → a second startDictation() at T=500ms.
                            // Relying solely on the flag means the single scenePhase path owns
                            // the start, with the 500ms sleep giving the audio session time to settle.
                            DicticusIPCBridge.defaults?.set(true, forKey: "pendingDictation")
                            // 46-03: staleness stamp so a process death before
                            // checkPendingIntent() consumes this flag cannot
                            // spontaneously start a recording on a later,
                            // unrelated relaunch — see
                            // DictationViewModel.pendingDictationStalenessSeconds.
                            DicticusIPCBridge.defaults?.set(Date().timeIntervalSince1970, forKey: "pendingDictationSetAt")
                        } else {
                            // Live Activity body tap (dicticus://liveactivity). Navigation
                            // only — must NOT set pendingDictation or start a recording.
                            // See DeepLinkRouter's doc comment. handleLiveActivityTap
                            // no-ops for any other/unknown URL.
                            DeepLinkRouter.shared.handleLiveActivityTap(url)
                        }
                    }
                    .sheet(isPresented: $showingOnboardingTour, onDismiss: {
                        hasSeenOnboardingTour = true
                        if !hasSeenWhatsNewV2 {
                            showingWhatsNew = true
                        }
                    }) {
                        OnboardingTourView()
                    }
                    .sheet(isPresented: $showingWhatsNew, onDismiss: { hasSeenWhatsNewV2 = true }) {
                        WhatsNewView()
                    }
                    .onAppear {
                        SwissDefaultMigration.runIfNeeded()  // D-A3 — first-launch belt-and-suspenders before scenePhase fires
                        let pendingDictation = DicticusIPCBridge.defaults?.bool(forKey: "pendingDictation") ?? false
                        // Guard on viewModel.state as well: checkPendingIntent() may have already
                        // consumed pendingDictation and started dictation before onAppear fires.
                        let noDictation = pendingDictation == false && viewModel.state == .idle
                        if !hasSeenOnboardingTour && noDictation {
                            showingOnboardingTour = true
                        } else if !hasSeenWhatsNewV2 && noDictation {
                            showingWhatsNew = true
                        }
                    }
            } else {
                OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                    .environmentObject(warmupService)
            }
        }
        // D-D1 (Phase 19.5): On scenePhase .active we re-read FS so a download
        // that completed in the background flips hasModels to true here, and a
        // stale-false from a prior session gets corrected.
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                SwissDefaultMigration.runIfNeeded()  // D-A3 — must run before any useSwissGerman reader
                // D-D1 (Phase 19.5): Re-read FS on foreground so a download that completed
                // in the background flips hasModels to true here, and a stale-false from a
                // prior session gets corrected.
                if hasCompletedOnboarding && DeviceCapabilityGate.isCurrentDeviceSupported {
                    warmupService.checkHasModels()
                    if warmupService.hasModels {
                        warmupService.warmup()
                    }
                    // On foreground, decide between delivering a pending transcript and starting
                    // a new recording session. These two actions MUST NOT run in the same cycle
                    // (delivery sets state=.transcribing; startDictation() guards on state==.idle).
                    // handleForeground() owns the branch: when pendingDictation is set the new
                    // session wins and delivery is deferred; otherwise delivery runs first (D-02/D-05).
                    let pendingDictation = DicticusIPCBridge.defaults?.bool(forKey: "pendingDictation") ?? false
                    Task { @MainActor in
                        await viewModel.handleForeground(pendingDictation: pendingDictation)
                    }
                }
            } else if newPhase == .background {
                // Background recording continues — do not finalize.
                // UIBackgroundModes:audio keeps the AVAudioSession alive.
            }
        }
        .onChange(of: warmupService.isReady) { _, isReady in
            if isReady,
               let asrManager = warmupService.asrManagerInstance {
                let service = IOSTranscriptionService(asrManager: asrManager)
                transcriptionService = service
                viewModel.transcriptionService = service
                // Phase 46-02 (D-05): a recording captured before the model was ready
                // may already be queued — drain it now that a transcriber exists.
                Task { @MainActor in
                    await viewModel.drainPendingRecordingsIfNeeded()
                }
            }
        }
        // Phase 19 Wave 5 — CLEAN-01 / CLEAN-02.
        // Inject the warmed-up CleanupService into DictationViewModel as soon
        // as warmup Step 4 publishes isLlmReady. Mirrors the isReady wiring
        // above. When Step 4 tears down (.failed or cancel), clear the seam
        // so the next dictation falls back to mode=.plain (D-26).
        .onChange(of: warmupService.isLlmReady) { _, isLlmReady in
            if isLlmReady, let cleanup = warmupService.cleanupServiceInstance {
                viewModel.cleanupService = cleanup
                // Retry deferred delivery: if .active fired before LLM was ready, the pending
                // transcript was delivered as plain text (correct but un-cleaned). Now that the
                // LLM is ready AND a pending UUID still exists, re-deliver with AI cleanup.
                // deliverPendingTranscriptsIfNeeded() checks for the UUID; it's a no-op if already cleared.
                // Retry deferred delivery when the LLM becomes ready:
                // - Check the list key (batch from Phase 36+ background stops).
                // - Also check the legacy single key (older builds / one-element case).
                // deliverPendingTranscriptsIfNeeded() is a no-op if the list is empty.
                let hasPendingList = !(DicticusIPCBridge.defaults?.stringArray(forKey: DicticusIPCBridge.Key.pendingTranscriptUUIDs)?.isEmpty ?? true)
                let hasPendingLegacy: Bool = {
                    guard let s = DicticusIPCBridge.defaults?.string(forKey: DicticusIPCBridge.Key.pendingTranscriptUUID) else { return false }
                    return !s.isEmpty
                }()
                if hasCompletedOnboarding, hasPendingList || hasPendingLegacy {
                    // WR-01: skip delivery if the user is already starting a new recording.
                    // The isLlmReady onChange can fire while an Action Button press is in
                    // flight (pendingDictation=true in App Group). Delivery sets state=.transcribing
                    // which then blocks startDictation()'s guard state==.idle — same stuck-state
                    // bug that handleForeground(pendingDictation:) fixes for the scenePhase path.
                    let pendingDictation = DicticusIPCBridge.defaults?.bool(forKey: "pendingDictation") ?? false
                    guard !pendingDictation else { return }
                    Task { @MainActor in
                        await viewModel.deliverPendingTranscriptsIfNeeded()
                    }
                }
            } else if !isLlmReady {
                viewModel.cleanupService = nil
            }
        }
        // WR-03: Re-present the tour when Settings resets hasSeenOnboardingTour.
        // oldValue guard ensures the initial false default does NOT auto-trigger;
        // only an explicit true→false transition (Settings button) shows the tour.
        .onChange(of: hasSeenOnboardingTour) { oldValue, newValue in
            if oldValue == true && newValue == false {
                showingOnboardingTour = true
            }
        }
    }
}
