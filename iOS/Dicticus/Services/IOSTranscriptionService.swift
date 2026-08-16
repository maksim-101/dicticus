import Foundation
import SwiftUI
import FluidAudio
@preconcurrency import AVFoundation
import Accelerate
import NaturalLanguage
import os

/// Errors thrown by IOSTranscriptionService during transcription.
enum TranscriptionError: Error, Sendable {
    /// Recording was shorter than minimumDurationSeconds.
    case tooShort
    /// No voice activity detected — adaptive energy gate or no-speech-prob discard.
    case silenceOnly
    /// ASR engine returned no transcription results.
    case noResult
    /// ASR models not available (model not warmed up).
    case modelNotReady
    /// stopRecordingAndTranscribe() called when not recording. Retained for source
    /// compatibility with call sites that still switch over every TranscriptionError
    /// case; IOSTranscriptionService itself no longer throws this (recording state
    /// moved to AudioRecorder / RecorderError in 46-02).
    case notRecording
    /// startRecording() called while already recording or transcribing. Retained for
    /// the same reason as .notRecording above.
    case busy
    /// ASR output contains non-Latin script (Cyrillic, CJK, Arabic, etc.) — likely a
    /// Parakeet hallucination when the spoken language doesn't match model expectations.
    case unexpectedLanguage
}

/// Injection seam so `DictationViewModel` can transcribe without depending on the
/// concrete WhisperKit-backed implementation (tests use a fake conformer instead).
@MainActor
protocol TranscriptionProviding: AnyObject {
    func transcribe(wavURL: URL) async throws -> DicticusTranscriptionResult
}

/// Core ASR pipeline for iOS: transcribe a WAV file via FluidAudio/Parakeet TDT v3
/// (Phase 47.1, D-04 engine swap — replaces WhisperKit large-v3-turbo), applying an
/// input-energy pre-filter, and detect language post-hoc with NLLanguageRecognizer.
/// As of Phase 46-02 this class owns transcription only — recording moved to
/// `AudioRecorder` so capture no longer requires a loaded model.
/// (See whisper-dictation-dropout debug session for the two-cycle Layer 2 history:
/// cycle 1 removed the fixed-threshold EnergyVAD pre-filter that misclassified genuine
/// speech as silence on some microphones; cycle 2 reintroduced Layer 2 as
/// AdaptiveVoiceGate, a clip-relative energy gate, after cycle 1's removal reopened
/// D-09 silence-hallucination pastes. D-02 (Phase 47.1): `NoSpeechDiscard`, keyed on
/// WhisperKit's `noSpeechProb`, is dropped — Parakeet's TDT transducer architecture has
/// no analog and cannot silence-hallucinate the way a seq2seq decoder can.)
@MainActor
final class IOSTranscriptionService: TranscriptionProviding {

    @AppStorage("useCustomDictionary", store: DicticusIPCBridge.defaults)
    var useCustomDictionary = true
    @AppStorage("useITN", store: DicticusIPCBridge.defaults)
    var useITN = true

    // MARK: - Configuration

    static let vadProbabilityThreshold: Float = 0.75
    var silenceThreshold: Float = IOSTranscriptionService.vadProbabilityThreshold
    /// Below this, a clip is a determination that there is nothing to transcribe, not
    /// a failure to hold. Exposed as a type-level constant (not an instance property)
    /// so `DictationViewModel.stopDictation()` can consult it even when no
    /// `TranscriptionProviding` instance has been constructed yet (model not warm).
    static let minimumDurationSeconds: Float = 0.3

    // MARK: - Private

    private let asrManager: AsrManager
    private let sampleRate: Double = 16000

    /// Trailing-silence tail-pad appended before every transcribe call. Parakeet's TDT
    /// decoder drops terminal punctuation (and occasionally a final word) when the last
    /// audio chunk ends flush against speech; padding lets it flush its tail token.
    /// Do NOT exceed 0.8s — longer trailing silence makes Parakeet hallucinate tokens
    /// out of the silence (validated 2026-06-16, spike 008 Fix B; git ccbad01; restored
    /// verbatim per Phase 47.1 D-02/RESEARCH Pattern 2).
    private static let tailPadSeconds: Double = 0.8

    // MARK: - Initialization

    /// Initialize with a warm AsrManager instance from IOSModelWarmupService.
    /// - Parameter asrManager: Initialized, warm FluidAudio AsrManager from
    ///   IOSModelWarmupService.asrManagerInstance. The decoder state is NOT owned here —
    ///   it is created fresh inside every `transcribe(wavURL:)` call (D-02/Pitfall 5:
    ///   FluidAudio's own architecture is stateless per-chunk; never persist decoder
    ///   state across unrelated utterances).
    init(asrManager: AsrManager) {
        self.asrManager = asrManager
    }

    // MARK: - Transcription

    /// Reads a WAV file back into `[Float]` samples at the file's own sample rate.
    /// Used instead of FluidAudio's URL-based `transcribe(_:decoderState:language:)`
    /// entry point to keep the resample + guard-layer pipeline below fully explicit.
    static func readSamples(fromWavAt url: URL) throws -> (samples: [Float], sampleRate: Double) {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw TranscriptionError.noResult
        }
        try file.read(into: buffer)
        let frameCount = Int(buffer.frameLength)
        guard let channelData = buffer.floatChannelData?[0] else {
            return ([], format.sampleRate)
        }
        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))
        return (samples, format.sampleRate)
    }

    func transcribe(wavURL: URL) async throws -> DicticusTranscriptionResult {
        let (samples, inputSampleRate) = try Self.readSamples(fromWavAt: wavURL)

        let resampledSamples: [Float]
        if abs(inputSampleRate - sampleRate) > 1.0 {
            resampledSamples = resampleAudio(samples, from: inputSampleRate, to: sampleRate)
        } else {
            resampledSamples = samples
        }

        let durationSeconds = Float(resampledSamples.count) / Float(sampleRate)

        // Layer 1: Minimum duration guard
        guard durationSeconds >= Self.minimumDurationSeconds else {
            throw TranscriptionError.tooShort
        }

        // Layer 2: Adaptive voice-activity gate (cycle 2 — reintroduces an input-energy
        // pre-filter after cycle 1 removed the fixed-threshold EnergyVAD entirely; see
        // whisper-dictation-dropout debug session). The threshold is computed relative
        // to THIS clip's own noise floor, so it self-calibrates across microphones
        // instead of assuming one fixed RMS ceiling. D-02 (Phase 47.1): kept verbatim —
        // engine-agnostic, still the only pre-decode silence-hallucination defense now
        // that NoSpeechDiscard (WhisperKit-specific, no Parakeet analog) is dropped.
        let gateFrameEnergies = Self.frameEnergies(of: resampledSamples, sampleRate: sampleRate)
        let gateDecision = AdaptiveVoiceGate.evaluate(frameEnergies: gateFrameEnergies)
        guard gateDecision.voiceDetected else {
            throw TranscriptionError.silenceOnly
        }

        // Layer 3: Transcribe via FluidAudio/Parakeet TDT v3.
        //
        // Restore the trailing-silence tail-pad Parakeet's TDT decoder needs to flush its
        // final token (spike 008 Fix B, git ccbad01) — WhisperKit's seq2seq decoder never
        // needed this, but the returning Parakeet path does. Do NOT exceed 0.8s (Self.tailPadSeconds).
        let asrTailPad = [Float](repeating: 0, count: Int(Self.tailPadSeconds * sampleRate))

        // Fresh decoder state per call (D-02/Pitfall 5) — FluidAudio's own architecture is
        // documented as stateless per-chunk; never persist decoderState across utterances.
        var decoderState = TdtDecoderState.make(decoderLayers: await asrManager.decoderLayerCount)
        let result = try await asrManager.transcribe(
            resampledSamples + asrTailPad, decoderState: &decoderState, language: nil
        )

        // KNOWN pre-existing quirk (not introduced by this phase, RESEARCH Pitfall 3 /
        // STATE.md parked review item): the Dictionary/ITN post-processing below runs
        // again inside TextProcessingService.process() when DictationViewModel feeds this
        // result's text through it — a pre-existing double-run, D-01 boundary, out of
        // scope to fix here.
        var processedText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !processedText.isEmpty else {
            throw TranscriptionError.noResult
        }

        // Script validation
        guard !Self.containsNonLatinScript(processedText) else {
            throw TranscriptionError.unexpectedLanguage
        }

        let detectedLanguage = detectLanguage(processedText)

        // Post-processing: Custom Dictionary
        if useCustomDictionary {
            processedText = DictionaryService.shared.apply(to: processedText)
        }

        // Post-processing: ITN (Inverse Text Normalization)
        if useITN {
            processedText = ITNUtility.applyITN(to: processedText, language: detectedLanguage)
        }

        // Post-processing: conservative filler-strip (D-04, Phase 47.1). Parakeet emits
        // raw standalone disfluencies ("um"/"uh"/"äh") that WhisperKit's seq2seq LM
        // suppressed for free — this restores that on the plain path. iOS-local direct
        // call (mirrors the Dictionary/ITN calls immediately above) so
        // Shared/Services/TextProcessingService's plain path — and therefore macOS,
        // which never runs this file — stays byte-identical (RESEARCH Pitfall 2/Open
        // Question 2). Runs exactly once here, before this result is handed to
        // TextProcessingService.process(). In aiCleanup mode, TextProcessingService's
        // RulesCleanupService.clean() also calls FillerWordRemover.strip — idempotent on
        // already-filler-free text, the same pre-existing double-run class as the
        // Dictionary/ITN calls above (RESEARCH Pitfall 3), not introduced or fixed here.
        processedText = FillerWordRemover.strip(processedText, language: detectedLanguage)

        // Confidence sourced directly from FluidAudio's ASRResult.confidence (D-02) — a
        // real Float field, no derivation needed (supersedes the old WhisperKit
        // avgLogprob-derived stand-in).
        return DicticusTranscriptionResult(
            text: processedText,
            language: detectedLanguage,
            confidence: result.confidence
        )
    }

    // MARK: - Adaptive voice gate support

    /// Compute per-frame RMS energies for AdaptiveVoiceGate, chunking `samples`
    /// into `frameLengthSeconds`-long windows (default 0.1s, matching the
    /// removed EnergyVAD's frame length). Phase 47.1: WhisperKit's own
    /// `AudioProcessor.calculateAverageEnergy(of:)` is no longer available (WhisperKit
    /// removed from iOS); inlined its exact `vDSP_rmsqv` RMS calculation verbatim
    /// (`argmax-oss-swift/Sources/WhisperKit/Core/Audio/AudioProcessor.swift:698-702`)
    /// so AdaptiveVoiceGate's input is byte-for-byte identical (D-02: Layer 2 kept
    /// verbatim, engine-agnostic).
    static func frameEnergies(of samples: [Float], sampleRate: Double, frameLengthSeconds: Float = 0.1) -> [Float] {
        guard !samples.isEmpty else { return [] }
        let frameLengthSamples = max(1, Int(frameLengthSeconds * Float(sampleRate)))
        var energies: [Float] = []
        energies.reserveCapacity((samples.count + frameLengthSamples - 1) / frameLengthSamples)
        var start = 0
        while start < samples.count {
            let end = min(start + frameLengthSamples, samples.count)
            energies.append(Self.calculateAverageEnergy(of: Array(samples[start..<end])))
            start = end
        }
        return energies
    }

    /// RMS energy of a signal chunk, via `vDSP_rmsqv` — verbatim port of
    /// WhisperKit's `AudioProcessor.calculateAverageEnergy(of:)` (see doc comment above).
    private static func calculateAverageEnergy(of signal: [Float]) -> Float {
        var rmsEnergy: Float = 0.0
        vDSP_rmsqv(signal, 1, &rmsEnergy, vDSP_Length(signal.count))
        return rmsEnergy
    }

    // MARK: - Resampling

    private func resampleAudio(_ samples: [Float], from sourceSampleRate: Double, to targetSampleRate: Double) -> [Float] {
        guard let sourceFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sourceSampleRate,
            channels: 1,
            interleaved: false
        ),
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ),
        let converter = AVAudioConverter(from: sourceFormat, to: targetFormat),
        let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(samples.count))
        else {
            return resampleLinear(samples, from: sourceSampleRate, to: targetSampleRate)
        }

        sourceBuffer.frameLength = AVAudioFrameCount(samples.count)
        if let channelData = sourceBuffer.floatChannelData?[0] {
            for i in 0..<samples.count {
                channelData[i] = samples[i]
            }
        }

        let ratio = targetSampleRate / sourceSampleRate
        let outputFrameCount = AVAudioFrameCount(Double(samples.count) * ratio)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount) else {
            return resampleLinear(samples, from: sourceSampleRate, to: targetSampleRate)
        }

        var conversionError: NSError?
        final class ConversionState: @unchecked Sendable { var didProvideData = false }
        let state = ConversionState()

        converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            if state.didProvideData {
                outStatus.pointee = .endOfStream
                return nil
            }
            state.didProvideData = true
            outStatus.pointee = .haveData
            return sourceBuffer
        }

        if conversionError != nil {
            return resampleLinear(samples, from: sourceSampleRate, to: targetSampleRate)
        }

        let frameCount = Int(outputBuffer.frameLength)
        guard let outputData = outputBuffer.floatChannelData?[0] else {
            return resampleLinear(samples, from: sourceSampleRate, to: targetSampleRate)
        }
        return Array(UnsafeBufferPointer(start: outputData, count: frameCount))
    }

    private func resampleLinear(_ samples: [Float], from sourceSampleRate: Double, to targetSampleRate: Double) -> [Float] {
        let ratio = targetSampleRate / sourceSampleRate
        let outputLength = Int(Double(samples.count) * ratio)
        var output = [Float](repeating: 0, count: outputLength)

        for i in 0..<outputLength {
            let sourceIndex = Double(i) / ratio
            let lower = Int(sourceIndex)
            let upper = min(lower + 1, samples.count - 1)
            let fraction = Float(sourceIndex - Double(lower))
            output[i] = samples[lower] * (1.0 - fraction) + samples[upper] * fraction
        }

        return output
    }

    // MARK: - Script validation

    private static let latinRanges: [ClosedRange<UInt32>] = [
        0x0000...0x007F,
        0x0080...0x00FF,
        0x0100...0x024F,
        0x1E00...0x1EFF,
        0x2C60...0x2C7F,
        0xA720...0xA7FF,
        0x0300...0x036F,
    ]

    static func containsNonLatinScript(_ text: String) -> Bool {
        let log = Logger(subsystem: "com.dicticus", category: "validation")
        let letters = CharacterSet.letters
        let allowedSymbols = CharacterSet(charactersIn: "$€£¥©®™°%‰#@&*-+=/\\|<>{}[]()\"'`^~_")
        let allowedPunctuation = CharacterSet.punctuationCharacters
        let allowedNumbers = CharacterSet.decimalDigits

        for scalar in text.unicodeScalars {
            if allowedNumbers.contains(scalar) || allowedPunctuation.contains(scalar) || allowedSymbols.contains(scalar) {
                continue
            }
            if letters.contains(scalar) {
                let value = scalar.value
                let isLatin = latinRanges.contains { $0.contains(value) }
                if !isLatin {
                    log.warning("Blocked non-Latin character: \(String(scalar)) (U+\(String(value, radix: 16)))")
                    return true
                }
            }
        }
        return false
    }

    // MARK: - Language detection

    /// Word count below which NLLanguageRecognizer's unconstrained classification is too
    /// unreliable to trust for a third-language ("other") verdict — very short/ambiguous
    /// text (e.g. "ok", "hi") gets misclassified into unrelated languages at high confidence
    /// once the {de,en} constraint is lifted. Below this threshold we fall back to the
    /// original constrained behavior (always de or en).
    static let shortTextWordCountThreshold = 4

    /// Detect language of transcribed text. German and English classify as "de"/"en";
    /// any other confident classification on longer text returns "other" (D-08/MLANG-03,
    /// Phase 42-02) so non-de/en dictation can be routed to deterministic rules-only cleanup
    /// instead of the LLM. Empty/undetectable/very-short text still falls back to "en".
    func detectLanguage(_ text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        let wordCount = text.split(whereSeparator: { $0.isWhitespace }).count
        if wordCount < Self.shortTextWordCountThreshold {
            recognizer.languageConstraints = [.german, .english]
        }
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage else { return "en" }
        switch language {
        case .german: return "de"
        case .english: return "en"
        default: return "other"
        }
    }

    func restrictLanguage(_ detected: String) -> String {
        let allowed: Set<String> = ["de", "en"]
        return allowed.contains(detected) ? detected : "en"
    }
}

// MARK: - Test support

#if DEBUG
extension IOSTranscriptionService {
    static func testRestrictLanguage(_ detected: String) -> String {
        let allowed: Set<String> = ["de", "en"]
        return allowed.contains(detected) ? detected : "en"
    }

    static func testDetectLanguage(_ text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        let wordCount = text.split(whereSeparator: { $0.isWhitespace }).count
        if wordCount < shortTextWordCountThreshold {
            recognizer.languageConstraints = [.german, .english]
        }
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage else { return "en" }
        switch language {
        case .german: return "de"
        case .english: return "en"
        default: return "other"
        }
    }

    /// Returns true if the Parakeet TDT v3 model is cached on this machine.
    /// Used by tests to conditionally skip model-dependent tests. Renamed from
    /// `isWhisperKitAvailable` (Phase 47.1 Task 3) to reflect the FluidAudio engine
    /// swap — the implementation is FluidAudio's real `AsrModels.modelsExist(at:)`.
    static func isModelAvailable() -> Bool {
        AsrModels.modelsExist(at: AsrModels.defaultCacheDirectory())
    }

    /// Attempt to create an IOSTranscriptionService using a warm FluidAudio AsrManager.
    /// Returns nil if initialization fails (model not cached, etc.).
    /// Used by tests that need an actual service instance.
    static func makeForTesting() async throws -> IOSTranscriptionService? {
        do {
            let (asrManager, _) = try await AsrModelLoader.loadFluidAudio()
            return IOSTranscriptionService(asrManager: asrManager)
        } catch {
            return nil
        }
    }
}
#endif
