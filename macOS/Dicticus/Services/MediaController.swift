import AppKit
import CoreAudio
import Foundation
import os

private let mediaLog = Logger(subsystem: "com.dicticus", category: "media-control")

/// MediaRemote `MRMediaRemoteSendCommand` bridge (tier-2b). Loaded once, lazily, at
/// process lifetime — private-framework handles are never `dlclose`'d. File-scope so
/// it is nonisolated (no MainActor coupling needed for a plain function pointer) and
/// shared across every `MediaController` instance. Spike 003-validated: the SEND is
/// not entitlement-gated from the signed app; the now-playing READ is (never read).
private typealias MRSendCommandFn = @convention(c) (Int, [AnyHashable: Any]?) -> Bool

private let mrSendCommandFn: MRSendCommandFn? = {
    guard let handle = dlopen(
        "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW
    ) else {
        return nil
    }
    guard let sym = dlsym(handle, "MRMediaRemoteSendCommand") else {
        return nil
    }
    return unsafeBitCast(sym, to: MRSendCommandFn.self)
}()

/// kMRTogglePlayPause — the only MediaRemote command this bridge ever sends.
private let kMRTogglePlayPause = 2

/// Pauses/resumes the currently-audible desktop media player while PTT is held.
///
/// Tier-1: ScriptingBridge / Apple events (validated signed in Spike 003d) control
/// Apple Music and Spotify. Tier-2b: for non-scriptable sources (browser/YouTube/
/// podcast), a CoreAudio running-guard gates a MediaRemote `togglePlayPause` send
/// (Spike 2026-07-25, all 4 scenarios / both output devices, LOCKED design — see
/// `260725-b4f-PLAN.md`). Tier-2: CoreAudio default-output mute is the last resort
/// (dead on hardware without a software mute, e.g. the JDS Labs Element IV DAC).
///
/// Algorithm (from 30-CONTEXT, extended by 260725-b4f):
///   pauseMediaIfPlaying()  — fire on PTT press, AFTER startRecording() succeeds.
///   resumeMediaIfPaused()  — fire on PTT release.
/// Tiers are mutually exclusive per hold: `pausedApp` (tier-1), `didToggleMediaRemote`
/// (tier-2b), `didMuteOutput` (tier-2) latch whichever tier actually acted, and resume
/// checks them in that same order so only the tier that fired on press unwinds on
/// release.
@MainActor
final class MediaController {

    private struct Player {
        let name: String
        let bundleID: String
    }

    private let players = [
        Player(name: "Music", bundleID: "com.apple.Music"),
        Player(name: "Spotify", bundleID: "com.spotify.client"),
    ]

    /// The specific player we paused this hold; nil when nothing was paused.
    private var pausedApp: Player?

    /// One-shot guard so a denied Automation grant logs once, not on every press.
    private var didWarnPermission = false

    /// True when WE muted the default output this hold (pausedApp == nil tier-2
    /// fallback). Separate from `pausedApp` so resume only un-mutes output we changed.
    private var didMuteOutput = false

    /// One-shot guard so a CoreAudio mute failure logs once, not on every press.
    private var didWarnMute = false

    /// True when WE sent a MediaRemote togglePlayPause this hold (tier-2b). A latch,
    /// not a re-read — release decides purely from this flag because MediaRemote's
    /// now-playing state cannot be read from the signed app (entitlement-gated).
    private var didToggleMediaRemote = false

    /// One-shot guard so a MediaRemote dlopen/dlsym/send failure logs once, not on
    /// every press.
    private var didWarnMediaRemote = false

    /// Settling window between the tier-2b press-side toggle and the post-toggle
    /// verification resample (260805-suy) — long enough for a genuinely-stopped
    /// player's audio to actually drain before we resample. `0.3` in production;
    /// the `makeForTesting` factory defaults it to `0` so tests are deterministic
    /// and fast (no real sleep).
    private let verifyDelaySeconds: TimeInterval

    /// Task handle for the async post-toggle verification (260805-suy).
    /// `resumeMediaIfPaused()` cancels this FIRST, before touching any other state,
    /// so a release that arrives before verification completes can never trigger a
    /// post-release undo toggle or a stranded mute. Read access is deliberately
    /// `internal` (not `private`) — the test target uses `@testable import` to await
    /// it directly; only this type can assign it (`private(set)`).
    private(set) var pendingVerifyTask: Task<Void, Never>?

    // MARK: - Test seams (tier-2b + tier-1, `makeForTesting` only)

    /// When non-nil, substitutes the entire ScriptingBridge tier-1 scan: any player
    /// whose name is in the returned set is treated as found-playing-and-paused (first
    /// match wins, mirroring the real loop) — no AppleScript ever runs under test.
    private let tier1RunningPlayersOverride: (() -> Set<String>)?

    /// When non-nil, substitutes the CoreAudio process-tap RMS sample that gates the
    /// tier-2b MediaRemote send AND the tier-2 mute fallback (260725-og7). `nil` from
    /// the closure means "tap unavailable" — the same conservative degrade as a real
    /// `OutputLevelSampler` timeout/failure.
    private let outputRMSOverride: (() -> Double?)?

    /// When non-nil, substitutes the MediaRemote togglePlayPause send (both press and
    /// resume use the same seam — mirrors the real bridge being called twice).
    private let mediaRemoteToggleOverride: (() -> Bool)?

    /// When non-nil, substitutes the default-output mute read.
    private let isOutputMutedOverride: (() -> Bool?)?

    /// When non-nil, substitutes the default-output mute write.
    private let setOutputMutedOverride: ((Bool) -> Bool)?

    /// Production initializer — no overrides, every seam resolves to the real
    /// ScriptingBridge / CoreAudio / MediaRemote implementation.
    init() {
        tier1RunningPlayersOverride = nil
        outputRMSOverride = nil
        mediaRemoteToggleOverride = nil
        isOutputMutedOverride = nil
        setOutputMutedOverride = nil
        verifyDelaySeconds = 0.3
    }

    private init(
        tier1RunningPlayers: @escaping () -> Set<String>,
        outputRMS: @escaping () -> Double?,
        mediaRemoteToggle: @escaping () -> Bool,
        isOutputMuted: @escaping () -> Bool?,
        setOutputMuted: @escaping (Bool) -> Bool,
        verifyDelaySeconds: TimeInterval
    ) {
        tier1RunningPlayersOverride = tier1RunningPlayers
        outputRMSOverride = outputRMS
        mediaRemoteToggleOverride = mediaRemoteToggle
        isOutputMutedOverride = isOutputMuted
        setOutputMutedOverride = setOutputMuted
        self.verifyDelaySeconds = verifyDelaySeconds
    }

    #if DEBUG
    /// Test-seam factory (260725-b4f, RMS seam swapped in 260725-og7). Injects mock
    /// closures so unit tests exercise the tier-1/tier-2b/tier-2 decision logic without
    /// ever touching real media — no real AppleScript, no real CoreAudio device I/O
    /// (the production `OutputLevelSampler` process tap is NEVER run under test), no
    /// real MediaRemote send.
    static func makeForTesting(
        tier1RunningPlayers: @escaping () -> Set<String> = { [] },
        outputRMS: @escaping () -> Double? = { nil },
        mediaRemoteToggle: @escaping () -> Bool = { false },
        isOutputMuted: @escaping () -> Bool? = { false },
        setOutputMuted: @escaping (Bool) -> Bool = { _ in false },
        verifyDelaySeconds: TimeInterval = 0
    ) -> MediaController {
        MediaController(
            tier1RunningPlayers: tier1RunningPlayers,
            outputRMS: outputRMS,
            mediaRemoteToggle: mediaRemoteToggle,
            isOutputMuted: isOutputMuted,
            setOutputMuted: setOutputMuted,
            verifyDelaySeconds: verifyDelaySeconds
        )
    }
    #endif

    /// Running-check via NSWorkspace (no Apple event) so we never LAUNCH a stopped
    /// player just to query it — `tell application "X"` blind would start it.
    private func isRunning(_ bundleID: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleID }
    }

    /// Runs an AppleScript source, returning its string value or an error number.
    private func runAS(_ src: String) -> (value: String?, errorNumber: Int?) {
        var err: NSDictionary?
        guard let script = NSAppleScript(source: src) else { return (nil, nil) }
        let out = script.executeAndReturnError(&err)
        if let err {
            let num = (err[NSAppleScript.errorNumber] as? Int)
            return (nil, num)
        }
        return (out.stringValue, nil)
    }

    /// Degrade to a silent no-op when Automation TCC is denied (errAEEventNotPermitted
    /// / -1743) or any AppleScript error occurs; log once at warn, never crash or retry.
    private func handleError(_ errorNumber: Int) {
        guard !didWarnPermission else { return }
        didWarnPermission = true
        mediaLog.warning("MediaController: Apple event failed (\(errorNumber)) — media pause disabled for this session")
    }

    /// Resolve the system default output device, or nil if CoreAudio fails.
    private func defaultOutputDevice() -> AudioDeviceID? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var dev = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev)
        return status == noErr ? dev : nil
    }

    private func muteAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
    }

    /// Read the master mute of the default output device; nil on failure.
    ///
    /// CoreAudio first, then AppleScript fallback: built-in MacBook speakers and many
    /// external devices expose no `kAudioDevicePropertyMute` master-mute property, so
    /// the CoreAudio path silently no-ops there. `output muted of (get volume settings)`
    /// is Standard Additions (in-process, no Automation-TCC grant) and works regardless.
    private func isOutputMuted() -> Bool? {
        if let override = isOutputMutedOverride { return override() }
        if let dev = defaultOutputDevice() {
            var addr = muteAddress()
            if AudioObjectHasProperty(dev, &addr) {
                var muted = UInt32(0)
                var size = UInt32(MemoryLayout<UInt32>.size)
                let status = AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &muted)
                if status == noErr { return muted != 0 }
            }
        }
        let result = runAS("output muted of (get volume settings)")
        if result.errorNumber != nil { return nil }
        switch result.value {
        case "true": return true
        case "false": return false
        default: return nil
        }
    }

    /// Write the master mute of the default output device; returns success.
    ///
    /// CoreAudio first, then AppleScript fallback (`set volume output muted`,
    /// Standard Additions, in-process, no Automation-TCC grant) for devices without a
    /// CoreAudio master-mute property.
    private func setOutputMuted(_ muted: Bool) -> Bool {
        if let override = setOutputMutedOverride { return override(muted) }
        if let dev = defaultOutputDevice() {
            var addr = muteAddress()
            if AudioObjectHasProperty(dev, &addr) {
                var value = UInt32(muted ? 1 : 0)
                let size = UInt32(MemoryLayout<UInt32>.size)
                let status = AudioObjectSetPropertyData(dev, &addr, 0, nil, size, &value)
                if status == noErr { return true }
            }
        }
        let result = runAS("set volume output muted \(muted ? "true" : "false")")
        return result.errorNumber == nil
    }

    /// Degrade to a silent no-op when the CoreAudio mute API fails; log once at warn.
    private func handleMuteFailure() {
        guard !didWarnMute else { return }
        didWarnMute = true
        mediaLog.warning("MediaController: default-output mute failed — mute fallback disabled for this session")
    }

    /// Conservative "nothing measurably playing" gate (260725-og7). RMS <= this
    /// threshold, or a nil sample (tap unavailable/denied/failed/timeout), means BOTH
    /// the tier-2b toggle AND the tier-2 mute stay OFF for this press — the
    /// paused-YouTube-resumes bug fix. Chosen conservative-low pending on-device
    /// threshold calibration from real `tier2b_rms` log evidence.
    nonisolated private static let silenceThreshold = 1e-4

    /// Sample the system output level via the RMS test seam (if installed) or the
    /// real `OutputLevelSampler` process tap. Replaces the dead
    /// `kAudioDevicePropertyDeviceIsRunningSomewhere` running-guard, which stays
    /// `true` through confirmed silence (spike 003 step 3) — this measures the
    /// actual output signal instead of "is the audio graph warm".
    private func sampleOutputLevel() -> (rms: Double?, status: String) {
        if let override = outputRMSOverride {
            let rms = override()
            return (rms, rms != nil ? "sampled" : "unavailable")
        }
        return OutputLevelSampler().sample()
    }

    /// Async variant used only by the tier-2b post-toggle verification
    /// (260805-suy) — the blocking ~100-250ms CoreAudio sample must never run on
    /// the MainActor mid-dictation. When a test override is installed it is
    /// resolved synchronously right here on the MainActor (tests never reach
    /// CoreAudio); otherwise the real `OutputLevelSampler` runs on a detached
    /// background task.
    private func sampleOutputLevelAsync() async -> (rms: Double?, status: String) {
        if let override = outputRMSOverride {
            let rms = override()
            return (rms, rms != nil ? "sampled" : "unavailable")
        }
        return await Task.detached(priority: .userInitiated) {
            OutputLevelSampler().sample()
        }.value
    }

    /// The three outcomes of the tier-2b post-toggle verification resample
    /// (260805-suy). Internal (not private) so `MediaControllerTests` can assert on
    /// `tier2bVerdict(...)` directly as a pure boundary table.
    enum Tier2bVerdict: Equatable {
        case stopped
        case stillPlaying
        case unmeasurable
    }

    /// Relative-to-press ratio used by the verify-side "still playing" bar
    /// (260805-suy) — deliberately NOT the bare `silenceThreshold`. See the
    /// "Why a relative ratio" note in `260805-suy-PLAN.md`: on the verify side a
    /// false "still playing" is strictly worse than today (it would un-pause media
    /// we correctly paused, then mute on top), so the bar tracks how loud THIS
    /// press was, not an absolute floor tuned for the press-side gate.
    nonisolated private static let verifyStillPlayingRatio = 0.25

    /// Pure decision: did the post-toggle resample show the audio is still playing?
    /// No I/O, reads no instance state — this is the whole tier-2b verify decision,
    /// directly unit-testable as a boundary table.
    ///
    /// `postRMS == nil` (tap unavailable/denied/failed/timeout) -> `.unmeasurable`,
    /// treated identically to `.stopped` by the caller (never act on an unmeasurable
    /// sample). Otherwise still-playing iff `postRMS` exceeds both the absolute
    /// `silenceThreshold` floor AND `verifyStillPlayingRatio` of the press-side RMS.
    nonisolated static func tier2bVerdict(pressRMS: Double, postRMS: Double?) -> Tier2bVerdict {
        guard let postRMS else { return .unmeasurable }
        if postRMS > max(silenceThreshold, pressRMS * verifyStillPlayingRatio) {
            return .stillPlaying
        }
        return .stopped
    }

    /// Post-toggle verification for the tier-2b press-side send (260805-suy). Runs
    /// asynchronously AFTER `pauseMediaIfPlaying()` has already returned — it never
    /// delays recording start or text processing. Re-checks `Task.isCancelled` and
    /// `didToggleMediaRemote` after every `await` because `resumeMediaIfPaused()` can
    /// race this task to completion; either check failing means the hold already
    /// ended and this verification must do nothing further.
    private func runTier2bVerification(pressRMS: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(verifyDelaySeconds * 1_000_000_000))
        guard !Task.isCancelled, didToggleMediaRemote else {
            #if DEBUG_RECORDER
            logTier2bVerify(pressRMS: pressRMS, verifyRMS: nil, verifyTapStatus: nil,
                             outcome: "cancelled", undoToggleSent: nil,
                             fallbackMuteAttempted: false, fallbackMuteResult: nil,
                             isOutputMutedResult: nil)
            #endif
            return
        }

        let (postRMS, tapStatus) = await sampleOutputLevelAsync()

        guard !Task.isCancelled, didToggleMediaRemote else {
            #if DEBUG_RECORDER
            logTier2bVerify(pressRMS: pressRMS, verifyRMS: postRMS, verifyTapStatus: tapStatus,
                             outcome: "cancelled", undoToggleSent: nil,
                             fallbackMuteAttempted: false, fallbackMuteResult: nil,
                             isOutputMutedResult: nil)
            #endif
            return
        }

        switch Self.tier2bVerdict(pressRMS: pressRMS, postRMS: postRMS) {
        case .stopped:
            #if DEBUG_RECORDER
            logTier2bVerify(pressRMS: pressRMS, verifyRMS: postRMS, verifyTapStatus: tapStatus,
                             outcome: "stopped", undoToggleSent: nil,
                             fallbackMuteAttempted: false, fallbackMuteResult: nil,
                             isOutputMutedResult: nil)
            #endif
            return

        case .unmeasurable:
            #if DEBUG_RECORDER
            logTier2bVerify(pressRMS: pressRMS, verifyRMS: postRMS, verifyTapStatus: tapStatus,
                             outcome: "unmeasurable", undoToggleSent: nil,
                             fallbackMuteAttempted: false, fallbackMuteResult: nil,
                             isOutputMutedResult: nil)
            #endif
            return

        case .stillPlaying:
            // Undo the collateral toggle first. If the send itself fails, leave the
            // press latch set exactly as it was — release still unwinds the press
            // toggle exactly as today, and no mute can be stranded.
            let undoSent = sendMediaRemoteToggle()
            guard undoSent else {
                #if DEBUG_RECORDER
                logTier2bVerify(pressRMS: pressRMS, verifyRMS: postRMS, verifyTapStatus: tapStatus,
                                 outcome: "still_playing", undoToggleSent: false,
                                 fallbackMuteAttempted: false, fallbackMuteResult: nil,
                                 isOutputMutedResult: nil)
                #endif
                return
            }
            didToggleMediaRemote = false

            // Mute fallback: same "only latch output WE muted" contract as the
            // press-side tier-2 last resort.
            guard let muted = isOutputMuted() else {
                handleMuteFailure()
                #if DEBUG_RECORDER
                logTier2bVerify(pressRMS: pressRMS, verifyRMS: postRMS, verifyTapStatus: tapStatus,
                                 outcome: "still_playing", undoToggleSent: true,
                                 fallbackMuteAttempted: false, fallbackMuteResult: nil,
                                 isOutputMutedResult: nil)
                #endif
                return
            }
            guard !muted else {
                #if DEBUG_RECORDER
                logTier2bVerify(pressRMS: pressRMS, verifyRMS: postRMS, verifyTapStatus: tapStatus,
                                 outcome: "still_playing", undoToggleSent: true,
                                 fallbackMuteAttempted: false, fallbackMuteResult: nil,
                                 isOutputMutedResult: muted)
                #endif
                return
            }
            let muteWriteSucceeded = setOutputMuted(true)
            if muteWriteSucceeded {
                didMuteOutput = true
            } else {
                handleMuteFailure()
            }
            #if DEBUG_RECORDER
            logTier2bVerify(pressRMS: pressRMS, verifyRMS: postRMS, verifyTapStatus: tapStatus,
                             outcome: "still_playing", undoToggleSent: true,
                             fallbackMuteAttempted: true, fallbackMuteResult: muteWriteSucceeded,
                             isOutputMutedResult: muted)
            #endif
        }
    }

    /// True when the real MediaRemote bridge resolved a send function (dlopen +
    /// dlsym both succeeded), or a test override is installed. Used only for probe
    /// logging — never gates behavior (behavior is entirely `sendMediaRemoteToggle()`'s
    /// return value).
    private var mediaRemoteBridgeAvailable: Bool {
        mediaRemoteToggleOverride != nil || mrSendCommandFn != nil
    }

    /// Send `MRMediaRemoteSendCommand(kMRTogglePlayPause, nil)` via the lazily-resolved
    /// private-framework bridge. Returns `false` — a graceful degrade, never a crash —
    /// when dlopen/dlsym failed to resolve the symbol OR the send itself returns false.
    /// Callers fall through to the tier-2 mute fallback on `false`.
    private func sendMediaRemoteToggle() -> Bool {
        if let override = mediaRemoteToggleOverride { return override() }
        guard let send = mrSendCommandFn else {
            handleMediaRemoteFailure()
            return false
        }
        let sent = send(kMRTogglePlayPause, nil)
        if !sent { handleMediaRemoteFailure() }
        return sent
    }

    /// Degrade to a silent no-op when the MediaRemote bridge is unavailable or a send
    /// fails; log once at warn, never crash or retry. Mirrors `handleMuteFailure`.
    private func handleMediaRemoteFailure() {
        guard !didWarnMediaRemote else { return }
        didWarnMediaRemote = true
        mediaLog.warning("MediaController: MediaRemote toggle unavailable/failed — degrading to mute fallback for this session")
    }

    /// Pause the one running player that is audibly playing; latch it for resume.
    ///
    /// Must be called AFTER `startRecording()` succeeds so rejected presses (model not
    /// ready, busy, mode mismatch, sub-threshold) never reach this call.
    func pauseMediaIfPlaying() {
        pendingVerifyTask?.cancel()
        pendingVerifyTask = nil
        pausedApp = nil
        #if DEBUG_RECORDER
        var playerOutcomes: [MediaPauseProbe.PlayerOutcome] = []
        #endif

        if let tier1Override = tier1RunningPlayersOverride {
            let runningNames = tier1Override()
            for player in players {
                if runningNames.contains(player.name) {
                    pausedApp = player
                    #if DEBUG_RECORDER
                    playerOutcomes.append(MediaPauseProbe.PlayerOutcome(
                        name: player.name, running: true, stateValue: "playing",
                        pauseAttempted: true, paused: true))
                    #endif
                    break
                }
                #if DEBUG_RECORDER
                playerOutcomes.append(MediaPauseProbe.PlayerOutcome(name: player.name, running: false))
                #endif
            }
        } else {
            for player in players {
                let running = isRunning(player.bundleID)
                guard running else {
                    #if DEBUG_RECORDER
                    playerOutcomes.append(MediaPauseProbe.PlayerOutcome(name: player.name, running: false))
                    #endif
                    continue
                }
                let state = runAS("tell application \"\(player.name)\" to return (player state as text)")
                if let err = state.errorNumber {
                    handleError(err)
                    #if DEBUG_RECORDER
                    playerOutcomes.append(MediaPauseProbe.PlayerOutcome(name: player.name, running: true, stateErrorNumber: err))
                    #endif
                    continue
                }
                if state.value == "playing" {
                    let result = runAS("tell application \"\(player.name)\" to pause")
                    if let err = result.errorNumber {
                        handleError(err)
                        #if DEBUG_RECORDER
                        playerOutcomes.append(MediaPauseProbe.PlayerOutcome(
                            name: player.name, running: true, stateValue: state.value,
                            pauseAttempted: true, pauseErrorNumber: err))
                        #endif
                        continue
                    }
                    pausedApp = player
                    #if DEBUG_RECORDER
                    playerOutcomes.append(MediaPauseProbe.PlayerOutcome(
                        name: player.name, running: true, stateValue: state.value,
                        pauseAttempted: true, paused: true))
                    #endif
                    break
                }
                #if DEBUG_RECORDER
                playerOutcomes.append(MediaPauseProbe.PlayerOutcome(name: player.name, running: true, stateValue: state.value))
                #endif
            }
        }

        // Tier 2b / Tier 2: only when tier-1 (ScriptingBridge) paused nothing.
        guard pausedApp == nil else {
            #if DEBUG_RECORDER
            logPause(playerOutcomes: playerOutcomes, tier2Reached: false,
                      isOutputMutedResult: nil, muteAttempted: false, setOutputMutedResult: nil)
            #endif
            return
        }

        // Tier 2b / Tier 2 gate: measured system-output RMS (260725-og7), NOT the
        // dead kAudioDevicePropertyDeviceIsRunningSomewhere running-check (spike 003
        // step 3: stays true through confirmed silence). RMS <= threshold, or a nil
        // sample (tap unavailable/denied/failed/timeout), means BOTH the tier-2b
        // toggle AND the tier-2 mute stay OFF for this press — never toggle or mute
        // on silence (fixes paused-YouTube-resumes-on-PTT).
        let (measuredRMS, tapStatus) = sampleOutputLevel()
        let isPlaying = (measuredRMS ?? 0) > Self.silenceThreshold

        guard isPlaying else {
            #if DEBUG_RECORDER
            logPause(playerOutcomes: playerOutcomes, tier2Reached: false,
                      isOutputMutedResult: nil, muteAttempted: false, setOutputMutedResult: nil,
                      tier2bGuardResult: false, tier2bToggleAttempted: false, tier2bToggleSent: false,
                      tier2bDlsymDegrade: nil, tier2bRMS: measuredRMS, tier2bTapStatus: tapStatus)
            #endif
            return
        }

        // Tier 2b: MediaRemote togglePlayPause — only attempted once we've measured
        // genuinely playing audio.
        let toggleSent = sendMediaRemoteToggle()
        if toggleSent {
            didToggleMediaRemote = true
            #if DEBUG_RECORDER
            logPause(playerOutcomes: playerOutcomes, tier2Reached: false,
                      isOutputMutedResult: nil, muteAttempted: false, setOutputMutedResult: nil,
                      tier2bGuardResult: true, tier2bToggleAttempted: true, tier2bToggleSent: true,
                      tier2bDlsymDegrade: false, tier2bRMS: measuredRMS, tier2bTapStatus: tapStatus)
            #endif
            // Post-toggle verify-and-fallback (260805-suy): measuredRMS is guaranteed
            // non-nil here — `isPlaying` above required it to exceed silenceThreshold.
            if let pressRMS = measuredRMS {
                pendingVerifyTask = Task { [weak self] in
                    await self?.runTier2bVerification(pressRMS: pressRMS)
                }
            }
            return
        }
        // Toggle degraded (dlsym/send failed) — fall through to the mute fallback,
        // now demoted to LAST resort behind tier-2b. isPlaying is still true here, so
        // the mute fallback remains gated on measured audio, never on silence.

        // Tier 2: default-output mute, the last resort (dead on hardware without a
        // software mute, e.g. the JDS Labs Element IV DAC — this is why tier-2b exists).
        // We latch only output WE muted — if the user already muted it, leave it
        // untouched so release never silently un-mutes a user-muted system.
        guard let muted = isOutputMuted() else {
            handleMuteFailure()
            #if DEBUG_RECORDER
            logPause(playerOutcomes: playerOutcomes, tier2Reached: true,
                      isOutputMutedResult: nil, muteAttempted: false, setOutputMutedResult: nil,
                      tier2bGuardResult: true, tier2bToggleAttempted: true,
                      tier2bToggleSent: false, tier2bDlsymDegrade: !mediaRemoteBridgeAvailable,
                      tier2bRMS: measuredRMS, tier2bTapStatus: tapStatus)
            #endif
            return
        }
        guard !muted else {
            #if DEBUG_RECORDER
            logPause(playerOutcomes: playerOutcomes, tier2Reached: true,
                      isOutputMutedResult: muted, muteAttempted: false, setOutputMutedResult: nil,
                      tier2bGuardResult: true, tier2bToggleAttempted: true,
                      tier2bToggleSent: false, tier2bDlsymDegrade: !mediaRemoteBridgeAvailable,
                      tier2bRMS: measuredRMS, tier2bTapStatus: tapStatus)
            #endif
            return
        }
        let muteWriteSucceeded = setOutputMuted(true)
        if muteWriteSucceeded {
            didMuteOutput = true
        } else {
            handleMuteFailure()
        }
        #if DEBUG_RECORDER
        logPause(playerOutcomes: playerOutcomes, tier2Reached: true,
                  isOutputMutedResult: muted, muteAttempted: true, setOutputMutedResult: muteWriteSucceeded,
                  tier2bGuardResult: true, tier2bToggleAttempted: true,
                  tier2bToggleSent: false, tier2bDlsymDegrade: !mediaRemoteBridgeAvailable,
                  tier2bRMS: measuredRMS, tier2bTapStatus: tapStatus)
        #endif
    }

    /// Resume the latched player/toggle/mute if we acted on press. Safe to call
    /// unconditionally on every release — a no-op when nothing was acted on.
    ///
    /// Branch order is tier-1 → tier-2b → tier-2, mirroring press: tiers are mutually
    /// exclusive per hold. Tier-2b MUST be checked before tier-2 (mute) so a latched
    /// MediaRemote toggle always resumes via a second toggle, never via an unmute.
    func resumeMediaIfPaused() {
        pendingVerifyTask?.cancel()
        pendingVerifyTask = nil

        if let player = pausedApp {
            pausedApp = nil
            let result = runAS("tell application \"\(player.name)\" to play")
            if let err = result.errorNumber {
                handleError(err)
            }
            #if DEBUG_RECORDER
            logResume(resumedPlayer: player.name, resumeErrorNumber: result.errorNumber,
                       unmuteAttempted: false, unmuteResult: nil, didMuteOutputBefore: false)
            #endif
            return
        }

        // Tier 2b resume: latch-only decision — never re-read MediaRemote's
        // now-playing state (entitlement-gated in the signed app). Clear the latch
        // BEFORE sending so a degraded resume send never re-fires on the next press.
        if didToggleMediaRemote {
            didToggleMediaRemote = false
            let toggleSent = sendMediaRemoteToggle()
            #if DEBUG_RECORDER
            logResume(resumedPlayer: nil, resumeErrorNumber: nil,
                       unmuteAttempted: false, unmuteResult: nil, didMuteOutputBefore: false,
                       tier2bResumeToggleAttempted: true, tier2bResumeToggleSent: toggleSent)
            #endif
            return
        }

        // Mute is the last-resort branch: we only reach here when no scriptable
        // player was resumed and no MediaRemote toggle was latched.
        guard didMuteOutput else {
            #if DEBUG_RECORDER
            logResume(resumedPlayer: nil, resumeErrorNumber: nil,
                       unmuteAttempted: false, unmuteResult: nil, didMuteOutputBefore: false,
                       tier2bResumeToggleAttempted: false, tier2bResumeToggleSent: nil)
            #endif
            return
        }
        didMuteOutput = false
        let unmuteSucceeded = setOutputMuted(false)
        if !unmuteSucceeded {
            handleMuteFailure()
        }
        #if DEBUG_RECORDER
        logResume(resumedPlayer: nil, resumeErrorNumber: nil,
                   unmuteAttempted: true, unmuteResult: unmuteSucceeded, didMuteOutputBefore: true,
                   tier2bResumeToggleAttempted: false, tier2bResumeToggleSent: nil)
        #endif
    }

    #if DEBUG_RECORDER

    /// Human-readable name of the current default output device (CoreAudio
    /// `kAudioObjectPropertyName`), or "unknown" when unavailable/query fails.
    private func defaultOutputDeviceName() -> String {
        guard let dev = defaultOutputDevice() else { return "unknown" }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &name)
        guard status == noErr, let resolved = name?.takeRetainedValue() else { return "unknown" }
        return resolved as String
    }

    private func logPause(
        playerOutcomes: [MediaPauseProbe.PlayerOutcome],
        tier2Reached: Bool,
        isOutputMutedResult: Bool?,
        muteAttempted: Bool,
        setOutputMutedResult: Bool?,
        tier2bGuardResult: Bool? = nil,
        tier2bToggleAttempted: Bool? = nil,
        tier2bToggleSent: Bool? = nil,
        tier2bDlsymDegrade: Bool? = nil,
        tier2bRMS: Double? = nil,
        tier2bTapStatus: String? = nil
    ) {
        let pausedAppName = pausedApp?.name
        let didMute = didMuteOutput
        let didToggle = didToggleMediaRemote
        let deviceName = defaultOutputDeviceName()
        Task {
            await MediaPauseProbe.shared.recordPause(
                players: playerOutcomes,
                pausedApp: pausedAppName,
                tier2Reached: tier2Reached,
                isOutputMutedResult: isOutputMutedResult,
                muteAttempted: muteAttempted,
                setOutputMutedResult: setOutputMutedResult,
                didMuteOutput: didMute,
                outputDeviceName: deviceName,
                tier2bGuardResult: tier2bGuardResult,
                tier2bToggleAttempted: tier2bToggleAttempted,
                tier2bToggleSent: tier2bToggleSent,
                tier2bDlsymDegrade: tier2bDlsymDegrade,
                didToggleMediaRemote: didToggle,
                tier2bRMS: tier2bRMS,
                tier2bTapStatus: tier2bTapStatus
            )
        }
    }

    /// Log one `runTier2bVerification(...)` decision point. Captures `didMuteOutput`
    /// on the MainActor before dispatching, mirroring `logPause`/`logResume`; the
    /// dispatched `Task` is intentionally unstructured (not a child task) so a
    /// `cancelled` outcome — recorded precisely when `runTier2bVerification`'s own
    /// task has been cancelled — still gets logged rather than being cancelled itself.
    private func logTier2bVerify(
        pressRMS: Double,
        verifyRMS: Double?,
        verifyTapStatus: String?,
        outcome: String,
        undoToggleSent: Bool?,
        fallbackMuteAttempted: Bool,
        fallbackMuteResult: Bool?,
        isOutputMutedResult: Bool?
    ) {
        let didMute = didMuteOutput
        Task {
            await MediaPauseProbe.shared.recordTier2bVerify(
                pressRMS: pressRMS,
                verifyRMS: verifyRMS,
                verifyTapStatus: verifyTapStatus,
                outcome: outcome,
                undoToggleSent: undoToggleSent,
                fallbackMuteAttempted: fallbackMuteAttempted,
                fallbackMuteResult: fallbackMuteResult,
                isOutputMutedResult: isOutputMutedResult,
                didMuteOutput: didMute
            )
        }
    }

    private func logResume(
        resumedPlayer: String?,
        resumeErrorNumber: Int?,
        unmuteAttempted: Bool,
        unmuteResult: Bool?,
        didMuteOutputBefore: Bool,
        tier2bResumeToggleAttempted: Bool? = nil,
        tier2bResumeToggleSent: Bool? = nil
    ) {
        Task {
            await MediaPauseProbe.shared.recordResume(
                resumedPlayer: resumedPlayer,
                resumeErrorNumber: resumeErrorNumber,
                unmuteAttempted: unmuteAttempted,
                unmuteResult: unmuteResult,
                didMuteOutputBefore: didMuteOutputBefore,
                tier2bResumeToggleAttempted: tier2bResumeToggleAttempted,
                tier2bResumeToggleSent: tier2bResumeToggleSent
            )
        }
    }

    #endif
}
