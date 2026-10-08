import Foundation

/// Pure adaptive input-energy voice-activity gate — Layer 2 of the app's silence
/// defense, reintroduced 2026-07-05 (whisper-dictation-dropout debug session,
/// cycle 2) after the fixed-threshold `EnergyVAD` pre-filter was removed entirely
/// in cycle 1 (Option c).
///
/// Cycle 1 recap: WhisperKit's `EnergyVAD` uses one fixed absolute RMS threshold
/// (0.02 per 100ms frame). That threshold was miscalibrated for a quiet
/// microphone — real speech never exceeded it — so Layer 2 discarded every
/// recording as silence. Removing Layer 2 fixed the dropout, but reopened D-09:
/// Whisper can emit a CONFIDENT hallucinated segment ("Thank you") on true
/// silence, and Layer 3 (`NoSpeechDiscard`, which reads `noSpeechProb`) cannot
/// catch it — a confident hallucination has a LOW `noSpeechProb` by definition.
/// Only an input-energy gate, evaluated before WhisperKit ever runs, can catch
/// that case. This type is that gate, redesigned to be adaptive instead of a
/// fixed constant so it doesn't reintroduce cycle 1's mic-calibration bug.
///
/// Energy-separation data behind the chosen constants (this user, on-device
/// verification 2026-07-05): true-silence clips topped out around a
/// max-100ms-frame RMS of ~0.0052; real speech (including deliberately quiet
/// speech) had a floor around ~0.0093. `defaultAbsoluteFloor` sits in the clean
/// gap between those two numbers.
///
/// Kept pure over `[Float]` per-frame RMS energies (no WhisperKit/AVFoundation
/// import) so it is directly unit-testable with plain arrays — no live
/// WhisperKit instance or audio capture required — mirroring `NoSpeechDiscard`.
/// Callers are responsible for computing per-100ms-frame RMS energies (e.g. via
/// WhisperKit's own `AudioProcessor.calculateAverageEnergy(of:)` per chunk) and
/// passing them in temporal order.
enum AdaptiveVoiceGate {

    /// One clip's gate evaluation, including the intermediate values, so
    /// callers can log the full decision (not just the boolean) for
    /// verification.
    struct Decision: Sendable, Equatable {
        /// True if voice activity was detected — the clip should proceed to WhisperKit.
        let voiceDetected: Bool
        /// The clip's own estimated ambient noise floor.
        let noiseFloor: Float
        /// The computed threshold `maxFrameEnergy` was measured against.
        let threshold: Float
        /// The loudest single frame's energy in the clip.
        let maxFrameEnergy: Float
    }

    /// Absolute floor below which a clip is never considered voice-active,
    /// regardless of how the noise-floor ratio computes. Sits strictly above
    /// the observed silence ceiling (~0.0052) and strictly below the observed
    /// quiet-speech floor (~0.0093) for the reproduction user — see type doc.
    static let defaultAbsoluteFloor: Float = 0.006

    /// Multiplier applied to the clip's own noise floor. A frame's energy must
    /// exceed `noiseFloor * defaultNoiseRatio` to count as voice, so the gate
    /// adapts to louder rooms without re-admitting steady ambient noise as
    /// speech. Midpoint of the ~3-4x range grounded in the energy-separation data.
    static let defaultNoiseRatio: Float = 3.5

    /// Percentile (0...1) used to estimate a clip's ambient noise floor from its
    /// own frame energies. A low percentile (rather than the bare minimum)
    /// avoids a single near-zero sample (e.g. a momentary dropout) from
    /// artificially depressing the floor.
    static let defaultNoiseFloorPercentile: Float = 0.1

    /// Evaluate voice activity for one clip's frame energies.
    ///
    /// - Parameter frameEnergies: Per-frame (typically 100ms) RMS energy values
    ///   for the whole clip, in any order (order does not affect the result —
    ///   only the value distribution matters). Pass an empty array for a clip
    ///   with no frames; this returns `voiceDetected: false` (fail-safe: no
    ///   energy evidence means no evidence of voice).
    /// - Parameter absoluteFloor: Minimum energy below which a clip can never be voice-active.
    /// - Parameter noiseRatio: How many times the noise floor a frame must exceed to count as voice.
    /// - Parameter noiseFloorPercentile: Percentile (0...1) used to estimate the noise floor.
    static func evaluate(
        frameEnergies: [Float],
        absoluteFloor: Float = defaultAbsoluteFloor,
        noiseRatio: Float = defaultNoiseRatio,
        noiseFloorPercentile: Float = defaultNoiseFloorPercentile
    ) -> Decision {
        guard !frameEnergies.isEmpty else {
            return Decision(voiceDetected: false, noiseFloor: 0, threshold: absoluteFloor, maxFrameEnergy: 0)
        }

        let noiseFloor = percentile(frameEnergies, noiseFloorPercentile)
        let threshold = max(absoluteFloor, noiseFloor * noiseRatio)
        let maxFrameEnergy = frameEnergies.max() ?? 0

        return Decision(
            voiceDetected: maxFrameEnergy > threshold,
            noiseFloor: noiseFloor,
            threshold: threshold,
            maxFrameEnergy: maxFrameEnergy
        )
    }

    /// Linear-interpolation percentile over `values` (sorted internally; the
    /// input array is not mutated).
    private static func percentile(_ values: [Float], _ p: Float) -> Float {
        let sorted = values.sorted()
        guard sorted.count > 1 else { return sorted.first ?? 0 }
        let clampedP = max(0, min(1, p))
        let rank = clampedP * Float(sorted.count - 1)
        let lowerIndex = Int(rank)
        let upperIndex = min(lowerIndex + 1, sorted.count - 1)
        let fraction = rank - Float(lowerIndex)
        return sorted[lowerIndex] * (1 - fraction) + sorted[upperIndex] * fraction
    }
}

extension AdaptiveVoiceGate.Decision {
    /// Frames-above-threshold count for a clip's frame energies against this
    /// decision's own `threshold`, single-sourcing what was previously an inline
    /// `frameEnergies.filter { $0 > gateDecision.threshold }.count` expression at
    /// the `TranscriptionService.transcribe()` call site (quick task 260826-8ec).
    /// Also the input of `AdaptiveVoiceGate.isNearSilentShortClip`, a gating decision,
    /// since quick task 261008-gb2.
    func framesAboveThreshold(in frameEnergies: [Float]) -> Int {
        frameEnergies.filter { $0 > threshold }.count
    }
}

extension AdaptiveVoiceGate {
    /// Near-silent short-clip rule (quick task 261008-gb2, F3): a clip shorter than this
    /// (exclusive) with at most `nearSilentMaxVoicedFrames` voiced frames is discarded after
    /// decode. The constants are the user's rule.
    ///
    /// Measured margin over the macOS discard logs (2026-08-13 to 2026-10-08), 54 pass
    /// records under 2.5 s that carry a frame count: the phantoms sit at 1 voiced frame (4
    /// records) and 4 frames (2 short-stock phantoms, "And" and "you"), the lowest real short
    /// utterance has 5. The cutoff of 2 leaves 3 unoccupied frame counts below real speech.
    ///
    /// The Phase 50 D-01 duration bypass sends 2.0-2.5 s clips with no voiced frame to
    /// Whisper; this rule narrows that to clips of 2.5 s and longer. Evidence that no real
    /// speech lives in the narrowed band: D-01's own shortest low-gain real speech lasts 2.7 s,
    /// and the 0-voiced real passes since 2026-09-16 start at 3.5 s.
    ///
    /// Called from macOS only (iOS runs Parakeet: no duration bypass, no silence
    /// hallucination, Phase 47.1 D-02).
    static let nearSilentMaxDurationSeconds: Float = 2.5
    static let nearSilentMaxVoicedFrames = 2

    /// True when `durationSeconds < nearSilentMaxDurationSeconds` and
    /// `voicedFrames <= nearSilentMaxVoicedFrames`. `voicedFrames` is
    /// `Decision.framesAboveThreshold(in:)` of the clip.
    static func isNearSilentShortClip(durationSeconds: Float, voicedFrames: Int) -> Bool {
        durationSeconds < nearSilentMaxDurationSeconds && voicedFrames <= nearSilentMaxVoicedFrames
    }
}
