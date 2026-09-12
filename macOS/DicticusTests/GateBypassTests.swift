import XCTest
@testable import Dicticus

// Phase 50 D-01: pure-function tests for the duration-aware energy-gate bypass
// (TranscriptionService.shouldProceedPastEnergyGate). All frame-energy fixtures
// are literals in this file — never `.shared` singletons, never the real
// DebugRecordings directory (D-18/D-19).
final class GateBypassTests: XCTestCase {

    // 25 frames (2.5s at 100ms/frame), all strictly below AdaptiveVoiceGate's
    // absoluteFloor (0.006) — guarantees voiceDetected == false regardless of
    // this clip's own noise floor, so the fixture is not vacuous (R7).
    private static let lowEnergyFrames: [Float] = [
        0.0032, 0.0045, 0.0038, 0.0051, 0.0033,
        0.0047, 0.0036, 0.0053, 0.0031, 0.0049,
        0.0040, 0.0055, 0.0034, 0.0046, 0.0037,
        0.0052, 0.0030, 0.0048, 0.0035, 0.0050,
        0.0039, 0.0054, 0.0033, 0.0044, 0.0041
    ]

    func testLowEnergy2_5sClip_proceedsByDuration() {
        let decision = AdaptiveVoiceGate.evaluate(frameEnergies: Self.lowEnergyFrames)
        XCTAssertFalse(decision.voiceDetected, "Precondition: this fixture must be a real gate-negative, or the test proves nothing")

        XCTAssertTrue(
            TranscriptionService.shouldProceedPastEnergyGate(voiceDetected: false, durationSeconds: 2.5),
            "A 2.5s low-energy clip is at/above the bypass duration and must proceed to WhisperKit"
        )
    }

    func testLowEnergy1_0sClip_isDiscarded() {
        let tenFrames = Array(Self.lowEnergyFrames.prefix(10))
        let decision = AdaptiveVoiceGate.evaluate(frameEnergies: tenFrames)
        XCTAssertFalse(decision.voiceDetected, "Precondition: this fixture must be a real gate-negative, or the test proves nothing")

        XCTAssertFalse(
            TranscriptionService.shouldProceedPastEnergyGate(voiceDetected: false, durationSeconds: 1.0),
            "A 1.0s low-energy clip is below the bypass duration and must still be discarded"
        )
    }

    func testBypassBoundary_exactlyAtConstantProceeds_oneUlpBelowDiscards() {
        XCTAssertEqual(TranscriptionService.gateBypassDurationSeconds, 2.0)

        XCTAssertTrue(
            TranscriptionService.shouldProceedPastEnergyGate(
                voiceDetected: false,
                durationSeconds: TranscriptionService.gateBypassDurationSeconds
            ),
            "A clip exactly at the bypass constant must proceed (>=, not >)"
        )
        XCTAssertFalse(
            TranscriptionService.shouldProceedPastEnergyGate(
                voiceDetected: false,
                durationSeconds: TranscriptionService.gateBypassDurationSeconds.nextDown
            ),
            "One ULP below the bypass constant must still be gated"
        )
    }

    func testVoiceDetectedShortClip_proceedsRegardless() {
        XCTAssertTrue(
            TranscriptionService.shouldProceedPastEnergyGate(voiceDetected: true, durationSeconds: 0.5),
            "The bypass only widens eligibility — a detected-voice clip must never become a discard"
        )
    }

    func testLayer1MinimumUnchanged() {
        // Pins the ordering the `empty` edge probe relies on: the bypass sits
        // strictly above Layer 1's minimumDurationSeconds (0.3), so a tap can
        // never reach the bypass predicate.
        XCTAssertGreaterThan(TranscriptionService.gateBypassDurationSeconds, 0.3)
    }
}
