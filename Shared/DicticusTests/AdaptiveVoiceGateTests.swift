import XCTest
@testable import Dicticus

// Pure-logic tests for the reintroduced Layer 2 adaptive voice-activity gate
// (whisper-dictation-dropout debug session, cycle 2). Drives
// AdaptiveVoiceGate.evaluate(frameEnergies:) directly over [Float] values — no
// WhisperKit import, no live audio capture required. Shared between macOS and
// iOS test targets since the gate predicate is pure logic.
//
// Constants under test: defaultAbsoluteFloor 0.006, defaultNoiseRatio 3.5,
// defaultNoiseFloorPercentile 0.1 — grounded in on-device energy-separation
// data (true silence ceiling ~0.0052, quiet-speech floor ~0.0093).
final class AdaptiveVoiceGateTests: XCTestCase {

    func testAllSilenceDiscards() {
        // True-silence frame energies (this user's on-device data: max
        // 100ms-frame RMS ranged ~0.0011-0.0052 across true-silence presses).
        let frameEnergies: [Float] = [0.0011, 0.0015, 0.0012, 0.0017, 0.0013, 0.0016, 0.0014, 0.00175]
        let decision = AdaptiveVoiceGate.evaluate(frameEnergies: frameEnergies)
        XCTAssertFalse(
            decision.voiceDetected,
            "A clip where every frame sits near the noise floor should be discarded as silence"
        )
        XCTAssertLessThan(
            decision.maxFrameEnergy, decision.threshold,
            "The loudest frame in a true-silence clip must stay below the computed threshold"
        )
    }

    func testQuietSpeechPasses() {
        // A quiet room punctuated by a few real-speech frames peaking around
        // ~0.009-0.0095 (the observed quiet-speech floor for this user) — the
        // exact case the removed fixed-threshold EnergyVAD (0.02) misclassified
        // as silence in cycle 1.
        let frameEnergies: [Float] = [0.0012, 0.0015, 0.0093, 0.0088, 0.0011, 0.0014, 0.0095, 0.0013]
        let decision = AdaptiveVoiceGate.evaluate(frameEnergies: frameEnergies)
        XCTAssertTrue(
            decision.voiceDetected,
            "Deliberately quiet speech (max frame ~0.0095) must pass the adaptive gate"
        )
    }

    func testLoudRoomWithSpeechPasses() {
        // Elevated ambient noise floor (~0.005, a "loud room") with speech
        // frames that clearly dwarf it (~0.028-0.03). The gate must adapt its
        // threshold upward from the room's own noise floor rather than relying
        // on a single fixed absolute constant, and still detect the speech.
        let frameEnergies: [Float] = [0.005, 0.0048, 0.0052, 0.0049, 0.03, 0.028, 0.0051, 0.005]
        let decision = AdaptiveVoiceGate.evaluate(frameEnergies: frameEnergies)
        XCTAssertTrue(
            decision.voiceDetected,
            "Speech that clearly dwarfs an elevated room noise floor must pass"
        )
        XCTAssertGreaterThan(
            decision.threshold, AdaptiveVoiceGate.defaultAbsoluteFloor,
            "A loud room's threshold should adapt above the flat absolute floor"
        )
    }

    func testLoudRoomWithoutSpeechDiscards() {
        // Steady elevated ambient noise (~0.0085-0.0095) with NO frame that
        // dwarfs the room's own noise floor — a naive flat absolute threshold
        // of 0.006 would wrongly accept this as voice; the adaptive
        // noise-floor-ratio check must reject it.
        let frameEnergies: [Float] = [0.009, 0.0085, 0.0095, 0.009, 0.0088, 0.0092, 0.0087, 0.0091]
        let decision = AdaptiveVoiceGate.evaluate(frameEnergies: frameEnergies)
        XCTAssertFalse(
            decision.voiceDetected,
            "Steady loud-room noise with no frame dwarfing its own floor must be discarded, not mistaken for speech"
        )
    }

    func testEmptyFrameEnergiesDiscards() {
        // Degenerate case: no frames at all. Fail-safe direction matches
        // NoSpeechDiscard's vacuous-true default — no energy evidence means no
        // evidence of voice.
        let decision = AdaptiveVoiceGate.evaluate(frameEnergies: [])
        XCTAssertFalse(decision.voiceDetected, "Empty frame energies should discard (fail-safe default)")
    }
}
