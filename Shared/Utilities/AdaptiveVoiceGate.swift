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
