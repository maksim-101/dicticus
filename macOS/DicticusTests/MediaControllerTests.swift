import XCTest
@testable import Dicticus

/// Unit tests for `MediaController`'s tier-1/tier-2b/tier-2 decision logic (260725-b4f,
/// RMS gate swapped in 260725-og7).
///
/// Every test uses `MediaController.makeForTesting(...)` with mock seams — no real
/// AppleScript, no real CoreAudio device I/O (the production `OutputLevelSampler`
/// process tap is NEVER exercised here), no real MediaRemote send. This is a hard
/// constraint (project CLAUDE.md, `feedback_coordinate_live_experiments`): unit tests
/// must never run an observable media experiment.
@MainActor
final class MediaControllerTests: XCTestCase {

    /// Above `MediaController`'s silenceThreshold (1e-4) — "genuinely playing".
    private static let playingRMS = 0.5

    /// At/below the silence threshold — "digital silence, nothing playing".
    private static let silentRMS = 0.0

    /// Verify-side resample above the 1e-4 absolute floor but below 25% of
    /// `playingRMS` (0.5 * 0.25 = 0.125) — a fade-out tail, not a still-playing verdict.
    private static let fadeOutBelowRatioRMS = 0.05

    /// Verify-side resample at 40% of `playingRMS` — just above the 25% still-playing
    /// bar. Paired with `fadeOutBelowRatioRMS` so the two tests read as a boundary.
    private static let justAboveRatioRMS = 0.2

    // MARK: - S-running: RMS above threshold, toggle succeeds

    func testRunningGuardTrueToggleSucceeds_SendsExactlyOneToggleAndLatches() {
        var toggleCallCount = 0
        var muteWriteCallCount = 0

        let controller = MediaController.makeForTesting(
            tier1RunningPlayers: { [] },
            outputRMS: { Self.playingRMS },
            mediaRemoteToggle: {
                toggleCallCount += 1
                return true
            },
            isOutputMuted: { false },
            setOutputMuted: { _ in
                muteWriteCallCount += 1
                return true
            }
        )

        controller.pauseMediaIfPlaying()

        XCTAssertEqual(toggleCallCount, 1, "exactly one toggle must be sent on press")
        XCTAssertEqual(muteWriteCallCount, 0, "mute must NOT be written when tier-2b succeeds")
    }

    // MARK: - S3 idle guard: RMS at/below threshold ⇒ no toggle sent (idle session never resumed)

    func testIdleGuardFalse_NeverSendsToggle() {
        var toggleCallCount = 0

        let controller = MediaController.makeForTesting(
            tier1RunningPlayers: { [] },
            outputRMS: { Self.silentRMS },
            mediaRemoteToggle: {
                toggleCallCount += 1
                return true
            },
            isOutputMuted: { false },
            setOutputMuted: { _ in true }
        )

        controller.pauseMediaIfPlaying()

        XCTAssertEqual(toggleCallCount, 0, "toggle must never fire when measured RMS is at/below the silence threshold — an idle/last session must never be resumed")

        // Latch stays false: resume must not send a resume-toggle either.
        controller.resumeMediaIfPaused()
        XCTAssertEqual(toggleCallCount, 0, "resume must not send a toggle when nothing was latched on press")
    }

    // MARK: - dlsym degrade: RMS above threshold, toggle returns false ⇒ falls through to mute

    func testDlsymDegrade_FallsThroughToMuteLastResort() {
        var toggleCallCount = 0
        var muteWriteCallCount = 0
        var muteWriteValue: Bool?

        let controller = MediaController.makeForTesting(
            tier1RunningPlayers: { [] },
            outputRMS: { Self.playingRMS },
            mediaRemoteToggle: {
                toggleCallCount += 1
                return false
            },
            isOutputMuted: { false },
            setOutputMuted: { value in
                muteWriteCallCount += 1
                muteWriteValue = value
                return true
            }
        )

        controller.pauseMediaIfPlaying()

        XCTAssertEqual(toggleCallCount, 1, "the degraded toggle must still be attempted exactly once")
        XCTAssertEqual(muteWriteCallCount, 1, "a degraded toggle must fall through and exercise the mute last-resort write")
        XCTAssertEqual(muteWriteValue, true)

        // Latch must NOT be set on a degraded toggle — resume must unmute, not re-toggle.
        var resumeToggleCallCount = 0
        var unmuteCallCount = 0
        let resumeController = MediaController.makeForTesting(
            tier1RunningPlayers: { [] },
            outputRMS: { Self.playingRMS },
            mediaRemoteToggle: {
                resumeToggleCallCount += 1
                return false
            },
            isOutputMuted: { false },
            setOutputMuted: { value in
                if value == false { unmuteCallCount += 1 }
                return true
            }
        )
        resumeController.pauseMediaIfPlaying()
        resumeController.resumeMediaIfPaused()
        XCTAssertEqual(resumeToggleCallCount, 1, "no second (resume) toggle call — press already exhausted the one call, latch was never set")
        XCTAssertEqual(unmuteCallCount, 1, "release must unmute since the mute path (not tier-2b) actually latched")
    }

    // MARK: - Resume toggle: latched press sends a second toggle and clears the latch

    func testLatchedPress_ResumeSendsSecondToggleAndClearsLatch() {
        var toggleCalls: [String] = []
        var unmuteCallCount = 0

        let controller = MediaController.makeForTesting(
            tier1RunningPlayers: { [] },
            outputRMS: { Self.playingRMS },
            mediaRemoteToggle: {
                toggleCalls.append("toggle")
                return true
            },
            isOutputMuted: { false },
            setOutputMuted: { value in
                if value == false { unmuteCallCount += 1 }
                return true
            }
        )

        controller.pauseMediaIfPlaying()
        XCTAssertEqual(toggleCalls.count, 1, "press sends exactly one toggle")

        controller.resumeMediaIfPaused()
        XCTAssertEqual(toggleCalls.count, 2, "release sends a second toggle to resume")
        XCTAssertEqual(unmuteCallCount, 0, "release must not also unmute — tier-2b and mute are mutually exclusive")

        // A second release call must be a no-op: latch was cleared before the resume send.
        controller.resumeMediaIfPaused()
        XCTAssertEqual(toggleCalls.count, 2, "a second resume call after the latch cleared must be a no-op")
    }

    // MARK: - Tier-1 precedence: a running player pausing means tier-2b is never reached

    func testTier1Precedence_SkipsTier2bEntirely() {
        var toggleCallCount = 0
        var outputRMSCallCount = 0
        var muteWriteCallCount = 0

        let controller = MediaController.makeForTesting(
            tier1RunningPlayers: { ["Music"] },
            outputRMS: {
                outputRMSCallCount += 1
                return Self.playingRMS
            },
            mediaRemoteToggle: {
                toggleCallCount += 1
                return true
            },
            isOutputMuted: { false },
            setOutputMuted: { _ in
                muteWriteCallCount += 1
                return true
            }
        )

        controller.pauseMediaIfPlaying()

        XCTAssertEqual(outputRMSCallCount, 0, "the RMS sampler seam must never be consulted once tier-1 has paused a player")
        XCTAssertEqual(toggleCallCount, 0, "no MediaRemote toggle when tier-1 already handled the hold")
        XCTAssertEqual(muteWriteCallCount, 0, "no mute write when tier-1 already handled the hold")
    }

    // MARK: - Silent below threshold: the paused-YouTube-resumes bug-fix case

    func testSilentBelowThreshold_NoToggleAndNoMute() {
        var toggleCallCount = 0
        var muteWriteCallCount = 0

        let controller = MediaController.makeForTesting(
            tier1RunningPlayers: { [] },
            outputRMS: { 0.000001 },
            mediaRemoteToggle: {
                toggleCallCount += 1
                return true
            },
            isOutputMuted: { false },
            setOutputMuted: { _ in
                muteWriteCallCount += 1
                return true
            }
        )

        controller.pauseMediaIfPlaying()

        XCTAssertEqual(toggleCallCount, 0, "silent (below-threshold) RMS must never send a toggle")
        XCTAssertEqual(muteWriteCallCount, 0, "silent (below-threshold) RMS must never write a mute — the paused-YouTube-resumes bug fix")

        // A following resume must be a no-op: nothing was latched on press.
        controller.resumeMediaIfPaused()
        XCTAssertEqual(toggleCallCount, 0, "resume must not send a toggle when press measured silence")
    }

    // MARK: - Tap unavailable (nil): conservative degrade

    func testTapUnavailable_NoToggleAndNoMute() {
        var toggleCallCount = 0
        var muteWriteCallCount = 0

        let controller = MediaController.makeForTesting(
            tier1RunningPlayers: { [] },
            outputRMS: { nil },
            mediaRemoteToggle: {
                toggleCallCount += 1
                return true
            },
            isOutputMuted: { false },
            setOutputMuted: { _ in
                muteWriteCallCount += 1
                return true
            }
        )

        controller.pauseMediaIfPlaying()

        XCTAssertEqual(toggleCallCount, 0, "a nil (tap-unavailable) sample must never send a toggle")
        XCTAssertEqual(muteWriteCallCount, 0, "a nil (tap-unavailable) sample must never write a mute — conservative degrade")
    }

    // MARK: - Tier-2b verify-and-fallback (260805-suy)

    /// Pure decision table for `MediaController.tier2bVerdict(pressRMS:postRMS:)` —
    /// no controller instance, no seams, just the boundary cases from the plan.
    func testTier2bVerdict_PureDecisionTable() {
        XCTAssertEqual(MediaController.tier2bVerdict(pressRMS: 0.5, postRMS: 0.5), .stillPlaying,
                        "post-toggle RMS equal to press RMS must verdict still-playing")
        XCTAssertEqual(MediaController.tier2bVerdict(pressRMS: 0.5, postRMS: 0.0), .stopped,
                        "digital silence after the toggle must verdict stopped")
        XCTAssertEqual(MediaController.tier2bVerdict(pressRMS: 0.5, postRMS: nil), .unmeasurable,
                        "a nil (tap-unavailable) resample must verdict unmeasurable")
    }

    /// End-to-end still-playing path: press toggles, verification resamples the same
    /// RMS, sends the undo toggle, mutes; release then unmutes and sends NO third
    /// toggle (the undo toggle already restored the third-party app's state).
    func testVerifyStillPlaying_SendsUndoToggleAndMutes_ResumeUnmutesWithoutToggle() async {
        var toggleCallCount = 0
        var muteWriteCalls: [Bool] = []

        let controller = MediaController.makeForTesting(
            tier1RunningPlayers: { [] },
            outputRMS: { Self.playingRMS },
            mediaRemoteToggle: {
                toggleCallCount += 1
                return true
            },
            isOutputMuted: { false },
            setOutputMuted: { value in
                muteWriteCalls.append(value)
                return true
            }
        )

        controller.pauseMediaIfPlaying()
        await controller.pendingVerifyTask?.value

        XCTAssertEqual(toggleCallCount, 2, "still-playing verdict must send exactly two toggles: press + undo")
        XCTAssertEqual(muteWriteCalls, [true], "still-playing verdict must mute exactly once")

        controller.resumeMediaIfPaused()

        XCTAssertEqual(toggleCallCount, 2, "resume after a fallback must send NO resume toggle — the undo toggle already restored state")
        XCTAssertEqual(muteWriteCalls, [true, false], "resume after a fallback must unmute exactly once")
    }

    /// Stopped verdict: press toggles, verification resamples digital silence — no
    /// undo toggle, no mute; release must still send its OWN resume toggle (the
    /// press-side latch was never cleared by a stopped verdict).
    func testVerifyStopped_NoUndoToggleNoMute_ResumeSendsSecondToggle() async {
        var toggleCallCount = 0
        var muteWriteCallCount = 0
        var rmsCallCount = 0

        let controller = MediaController.makeForTesting(
            tier1RunningPlayers: { [] },
            outputRMS: {
                rmsCallCount += 1
                return rmsCallCount == 1 ? Self.playingRMS : Self.silentRMS
            },
            mediaRemoteToggle: {
                toggleCallCount += 1
                return true
            },
            isOutputMuted: { false },
            setOutputMuted: { _ in
                muteWriteCallCount += 1
                return true
            }
        )

        controller.pauseMediaIfPlaying()
        await controller.pendingVerifyTask?.value

        XCTAssertEqual(toggleCallCount, 1, "a stopped verdict must never send an undo toggle")
        XCTAssertEqual(muteWriteCallCount, 0, "a stopped verdict must never write a mute")

        controller.resumeMediaIfPaused()
        XCTAssertEqual(toggleCallCount, 2, "release must still send its own resume toggle — the press-side latch was untouched by a stopped verdict")
        XCTAssertEqual(muteWriteCallCount, 0, "resume after a stopped verdict must never unmute — nothing was muted")
    }

    /// Fade-out below the still-playing ratio: verify RMS clears the absolute
    /// `silenceThreshold` floor but stays under 25% of press RMS — treated as
    /// stopped, not still-playing.
    func testVerifyFadeOutBelowRatio_TreatedAsStopped() async {
        var toggleCallCount = 0
        var muteWriteCallCount = 0
        var rmsCallCount = 0

        let controller = MediaController.makeForTesting(
            tier1RunningPlayers: { [] },
            outputRMS: {
                rmsCallCount += 1
                return rmsCallCount == 1 ? Self.playingRMS : Self.fadeOutBelowRatioRMS
            },
            mediaRemoteToggle: {
                toggleCallCount += 1
                return true
            },
            isOutputMuted: { false },
            setOutputMuted: { _ in
                muteWriteCallCount += 1
                return true
            }
        )

        controller.pauseMediaIfPlaying()
        await controller.pendingVerifyTask?.value

        XCTAssertEqual(toggleCallCount, 1, "a fade-out tail below the 25%-of-press ratio must never send an undo toggle")
        XCTAssertEqual(muteWriteCallCount, 0, "a fade-out tail below the 25%-of-press ratio must never write a mute")
    }

    /// Just above the still-playing ratio: verify RMS at 40% of press RMS clears the
    /// bar — treated as still-playing, undo toggle + mute fire.
    func testVerifyJustAboveRatio_TreatedAsStillPlaying() async {
        var toggleCallCount = 0
        var muteWriteCallCount = 0
        var rmsCallCount = 0

        let controller = MediaController.makeForTesting(
            tier1RunningPlayers: { [] },
            outputRMS: {
                rmsCallCount += 1
                return rmsCallCount == 1 ? Self.playingRMS : Self.justAboveRatioRMS
            },
            mediaRemoteToggle: {
                toggleCallCount += 1
                return true
            },
            isOutputMuted: { false },
            setOutputMuted: { _ in
                muteWriteCallCount += 1
                return true
            }
        )

        controller.pauseMediaIfPlaying()
        await controller.pendingVerifyTask?.value

        XCTAssertEqual(toggleCallCount, 2, "40% of press RMS clears the still-playing bar and must send the undo toggle")
        XCTAssertEqual(muteWriteCallCount, 1, "40% of press RMS clears the still-playing bar and must write the mute")
    }

    /// Unmeasurable verify sample (tap unavailable/denied/failed/timeout) is treated
    /// identically to a stopped verdict — never act on a sample we couldn't take.
    func testVerifyUnmeasurable_TreatedAsStopped() async {
        var toggleCallCount = 0
        var muteWriteCallCount = 0
        var rmsCallCount = 0

        let controller = MediaController.makeForTesting(
            tier1RunningPlayers: { [] },
            outputRMS: {
                rmsCallCount += 1
                return rmsCallCount == 1 ? Self.playingRMS : nil
            },
            mediaRemoteToggle: {
                toggleCallCount += 1
                return true
            },
            isOutputMuted: { false },
            setOutputMuted: { _ in
                muteWriteCallCount += 1
                return true
            }
        )

        controller.pauseMediaIfPlaying()
        await controller.pendingVerifyTask?.value

        XCTAssertEqual(toggleCallCount, 1, "an unmeasurable verify sample must never send an undo toggle")
        XCTAssertEqual(muteWriteCallCount, 0, "an unmeasurable verify sample must never write a mute")
    }

    /// A release that arrives before verification completes cancels it: no undo
    /// toggle, no mute — the release's own resume toggle is the only second send.
    func testEarlyRelease_CancelsVerificationBeforeSideEffects() {
        var toggleCallCount = 0
        var muteWriteCallCount = 0
        var rmsCallCount = 0

        let controller = MediaController.makeForTesting(
            tier1RunningPlayers: { [] },
            outputRMS: {
                rmsCallCount += 1
                return Self.playingRMS
            },
            mediaRemoteToggle: {
                toggleCallCount += 1
                return true
            },
            isOutputMuted: { false },
            setOutputMuted: { _ in
                muteWriteCallCount += 1
                return true
            }
        )

        controller.pauseMediaIfPlaying()
        controller.resumeMediaIfPaused()

        XCTAssertNil(controller.pendingVerifyTask, "resume must clear the pending verify task synchronously")
        XCTAssertEqual(toggleCallCount, 2, "press + resume toggle only — an early release must cancel verification before it can send its own undo toggle")
        XCTAssertEqual(muteWriteCallCount, 0, "an early release must cancel verification before it can write a mute")
    }

    /// The undo send itself fails: no mute write (never mute on an unconfirmed undo),
    /// the press-side latch is retained, and release still unwinds the ORIGINAL press
    /// toggle — a third send, not a no-op.
    func testUndoSendFails_NoMuteWrite_LatchRetained_ReleaseStillSendsToggle() async {
        var toggleCallCount = 0
        var muteWriteCallCount = 0
        var rmsCallCount = 0

        let controller = MediaController.makeForTesting(
            tier1RunningPlayers: { [] },
            outputRMS: {
                rmsCallCount += 1
                return Self.playingRMS
            },
            mediaRemoteToggle: {
                toggleCallCount += 1
                // Press (call 1) succeeds; the undo attempt (call 2) fails.
                return toggleCallCount == 1
            },
            isOutputMuted: { false },
            setOutputMuted: { _ in
                muteWriteCallCount += 1
                return true
            }
        )

        controller.pauseMediaIfPlaying()
        await controller.pendingVerifyTask?.value

        XCTAssertEqual(toggleCallCount, 2, "press toggle plus the one failed undo attempt")
        XCTAssertEqual(muteWriteCallCount, 0, "an undo-send failure must never fall through to a mute — that would strand a mute release can't unwind")

        controller.resumeMediaIfPaused()
        XCTAssertEqual(toggleCallCount, 3, "release must still unwind the ORIGINAL press toggle since the undo failed and the latch was retained")
    }

    /// Still-playing verdict when the user has already muted output: the undo toggle
    /// still fires, but `setOutputMuted` is never called (the existing "only latch
    /// output WE muted" contract), and release does not unmute the user's own mute.
    func testStillPlayingWithUserAlreadyMuted_UndoToggleSent_MuteNeverWritten_ReleaseDoesNotUnmute() async {
        var toggleCallCount = 0
        var muteWriteCallCount = 0
        var rmsCallCount = 0

        let controller = MediaController.makeForTesting(
            tier1RunningPlayers: { [] },
            outputRMS: {
                rmsCallCount += 1
                return Self.playingRMS
            },
            mediaRemoteToggle: {
                toggleCallCount += 1
                return true
            },
            isOutputMuted: { true },
            setOutputMuted: { _ in
                muteWriteCallCount += 1
                return true
            }
        )

        controller.pauseMediaIfPlaying()
        await controller.pendingVerifyTask?.value

        XCTAssertEqual(toggleCallCount, 2, "still-playing verdict must send the undo toggle even when the user already muted output")
        XCTAssertEqual(muteWriteCallCount, 0, "must never write a mute the user already applied — the existing 'only latch output WE muted' contract")

        controller.resumeMediaIfPaused()
        XCTAssertEqual(muteWriteCallCount, 0, "release must not unmute since verification never latched didMuteOutput — the user's own mute stays untouched")
        XCTAssertEqual(toggleCallCount, 2, "release must not send a resume toggle either — the undo toggle already cleared the press-side latch")
    }

    /// No verification is ever scheduled when tier-1 already paused a player, when
    /// the RMS gate said silent, or when the press toggle degraded straight to the
    /// mute last-resort — `pendingVerifyTask` stays nil in all three cases.
    func testNoVerificationScheduled_WhenTier1Paused_WhenSilent_WhenToggleDegraded() {
        let tier1Controller = MediaController.makeForTesting(
            tier1RunningPlayers: { ["Music"] },
            outputRMS: { Self.playingRMS },
            mediaRemoteToggle: { true },
            isOutputMuted: { false },
            setOutputMuted: { _ in true }
        )
        tier1Controller.pauseMediaIfPlaying()
        XCTAssertNil(tier1Controller.pendingVerifyTask, "tier-1 pausing a player must never schedule tier-2b verification")

        let silentController = MediaController.makeForTesting(
            tier1RunningPlayers: { [] },
            outputRMS: { Self.silentRMS },
            mediaRemoteToggle: { true },
            isOutputMuted: { false },
            setOutputMuted: { _ in true }
        )
        silentController.pauseMediaIfPlaying()
        XCTAssertNil(silentController.pendingVerifyTask, "a silent RMS gate must never schedule tier-2b verification")

        let degradedController = MediaController.makeForTesting(
            tier1RunningPlayers: { [] },
            outputRMS: { Self.playingRMS },
            mediaRemoteToggle: { false },
            isOutputMuted: { false },
            setOutputMuted: { _ in true }
        )
        degradedController.pauseMediaIfPlaying()
        XCTAssertNil(degradedController.pendingVerifyTask, "a degraded press toggle falling through to the mute last-resort must never schedule tier-2b verification")
    }

    // MARK: - Canary: every seam in this file is a mock, never a real-media closure

    func testCanary_AllSeamsAreMocksNeverRealMedia() {
        // This test exists purely to document and enforce, at the file level, that
        // every controller instance above is built via the mock-injecting factory —
        // never the bare production initializer, which would wire real
        // NSWorkspace/AppleScript/CoreAudio/MediaRemote calls. A self-grep guard: if
        // this file ever gains a call to the no-argument initializer, that call
        // bypasses every seam here and would touch real media under test. The needle
        // below is built at runtime (not written literally elsewhere in this file) so
        // this guard doesn't trip on its own source text.
        let productionInitCall = "MediaController" + "()"
        let source = try? String(
            contentsOfFile: #filePath,
            encoding: .utf8
        )
        XCTAssertNotNil(source, "could not self-read this test file to verify the canary")
        let occurrences = (source?.components(separatedBy: productionInitCall).count ?? 2) - 1
        XCTAssertEqual(occurrences, 0, "this test file must never construct the bare production controller directly — all instances must go through the mock-injecting factory")
    }
}
