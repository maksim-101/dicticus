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
