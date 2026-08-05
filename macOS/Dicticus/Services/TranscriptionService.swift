import SwiftUI
import WhisperKit
@preconcurrency import AVFoundation
import NaturalLanguage
import os

/// Errors thrown by TranscriptionService during the record-transcribe cycle.
enum TranscriptionError: Error, Sendable {
    /// Recording was shorter than minimumDurationSeconds (D-06 in 02-RESEARCH.md).
    case tooShort
    /// No voice activity detected — adaptive energy gate or no-speech-prob discard (D-10 in 02.1-RESEARCH.md).
    case silenceOnly
    /// ASR engine returned no transcription results.
    case noResult
    /// ASR models not available (model not warmed up).
    case modelNotReady
    /// stopRecordingAndTranscribe() called when not recording.
    case notRecording
    /// startRecording() called while already recording or transcribing.
    case busy
    /// ASR output contains non-Latin script (Cyrillic, CJK, Arabic, etc.) — likely an
    /// ASR hallucination when the spoken language doesn't match model expectations.
    case unexpectedLanguage
}

/// Thread-safe audio sample buffer for real-time AVAudioEngine tap callbacks.
/// Extracted as a standalone Sendable class so the tap closure doesn't inherit
/// @MainActor isolation from TranscriptionService — Swift 6 enforces actor
/// isolation on closures defined inside @MainActor methods even when self
/// isn't captured, causing a runtime crash on the audio thread.
final class AudioSampleBuffer: @unchecked Sendable {
    private var samples: [Float] = []
    private let lock = NSLock()

    func append(_ newSamples: [Float]) {
        lock.lock()
        samples.append(contentsOf: newSamples)
        lock.unlock()
    }

    func drain() -> [Float] {
        lock.lock()
        let result = samples
        samples.removeAll()
        lock.unlock()
        return result
    }

    func clear() {
        lock.lock()
        samples.removeAll()
        lock.unlock()
    }
}

/// Core ASR pipeline: record audio via AVAudioEngine, apply silence-discard
/// checks, transcribe via WhisperKit large-v3-turbo, and detect language
/// post-hoc with NLLanguageRecognizer.
///
/// Silence defense (WHISP-03; see whisper-dictation-dropout debug session for
/// the two-cycle history — cycle 1 removed the fixed-threshold EnergyVAD
/// pre-filter that misclassified genuine speech as silence on some
/// microphones; cycle 2 reintroduced Layer 2 as an adaptive, clip-relative gate
/// after cycle 1's removal reopened D-09 silence-hallucination pastes):
///   1. Minimum duration guard: discard clips shorter than 0.3s (D-11 in 02.1-CONTEXT.md)
///   2. Adaptive voice-activity gate: discard if no frame's energy dwarfs the clip's own noise floor (AdaptiveVoiceGate)
///   3. No-speech discard: discard if every segment's noSpeechProb exceeds threshold (NoSpeechDiscard, WHISP-03)
///
/// Consumes ModelWarmupService.whisperKitInstance directly.
/// Does NOT create its own WhisperKit instances outside of test support.
///
/// Phase 3 will call startRecording() on hotkey press and
/// stopRecordingAndTranscribe() on hotkey release.
@MainActor
class TranscriptionService: ObservableObject {

    // MARK: - State machine

    /// Pipeline state. Phase 3 observes this for UI feedback (e.g., pulsing icon during recording).
    enum State: Equatable, Sendable {
        case idle
        case recording
        case transcribing
    }

    @Published var state: State = .idle
    @Published var lastResult: DicticusTranscriptionResult?
    @Published var error: String?

    // MARK: - Configuration

    /// Legacy VAD probability threshold retained for API/test compatibility. The
    /// original EnergyVAD pre-filter that once consulted an energy-based threshold
    /// was removed 2026-07-05 (whisper-dictation-dropout debug session, cycle 1); its
    /// reintroduced replacement (AdaptiveVoiceGate, cycle 2) uses its own adaptive
    /// constants, not this value — this field is no longer consulted by the
    /// transcription pipeline at all.
    static let vadProbabilityThreshold: Float = 0.75

    /// Legacy silence threshold retained for API/test compatibility (see
    /// `vadProbabilityThreshold`). Not consulted by the current pipeline.
    var silenceThreshold: Float = TranscriptionService.vadProbabilityThreshold

    /// Minimum recording duration in seconds (D-11 in 02.1-CONTEXT.md).
    /// Sub-0.3s clips are noise or accidental key presses, not speech.
    let minimumDurationSeconds: Float = 0.3

    // MARK: - Private

    private let whisperKit: WhisperKit
    private let audioEngine = AVAudioEngine()
    /// Thread-safe buffer for audio samples — see AudioSampleBuffer doc comment.
    private let sampleBuffer = AudioSampleBuffer()
    /// Target sample rate for WhisperKit (16kHz mono).
    private let sampleRate: Double = 16000

    // MARK: - Initialization

    /// Initialize with a warm WhisperKit instance from ModelWarmupService.
    /// - Parameter whisperKit: Initialized WhisperKit instance from ModelWarmupService.whisperKitInstance
    init(whisperKit: WhisperKit) {
        self.whisperKit = whisperKit
    }

    // MARK: - Recording

    /// Start recording via AVAudioEngine.
    ///
    /// Installs a tap on the input node to accumulate raw Float32 samples.
    /// The hardware's native sample rate is captured; resampling to 16kHz
    /// occurs in stopRecordingAndTranscribe() before ASR inference.
    ///
    /// - Throws: TranscriptionError.busy if already recording or transcribing.
    /// - Throws: AVFoundation error if microphone access is denied or hardware unavailable.
    func startRecording() throws {
        guard state == .idle else { throw TranscriptionError.busy }
        sampleBuffer.clear()

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Install tap via nonisolated helper to prevent the closure from
        // inheriting @MainActor isolation (Swift 6 strict concurrency).
        Self.installTap(on: inputNode, format: inputFormat, buffer: sampleBuffer)

        try audioEngine.start()
        state = .recording
    }

    /// Install audio tap in a nonisolated context so the closure has no actor affinity.
    /// Swift 6 strict concurrency makes closures inside @MainActor methods inherit
    /// that isolation — even @Sendable closures check actor identity at runtime,
    /// crashing when AVAudioEngine calls them on the real-time audio thread.
    nonisolated private static func installTap(
        on inputNode: AVAudioInputNode,
        format: AVAudioFormat,
        buffer: AudioSampleBuffer
    ) {
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) {
            pcmBuffer, _ in
            if let channelData = pcmBuffer.floatChannelData?[0] {
                let frameCount = Int(pcmBuffer.frameLength)
                let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))
                buffer.append(samples)
            }
        }
    }

    // MARK: - Transcription

    /// Stop recording and run the full transcription pipeline.
    ///
    /// Pipeline steps:
    ///   1. Stop AVAudioEngine recording (always stop before reading samples)
    ///   2. Resample from hardware rate to 16kHz mono (WhisperKit expects 16kHz)
    ///   3. Check minimum duration (D-11: reject clips shorter than 0.3s)
    ///   4. Adaptive voice-activity gate: reject if no frame dwarfs the clip's own noise floor
    ///   5. Transcribe via WhisperKit large-v3-turbo
    ///   6. No-speech discard: reject if every segment's noSpeechProb exceeds threshold
    ///   7. Detect language post-hoc with NLLanguageRecognizer (D-13)
    ///   8. Build DicticusTranscriptionResult
    ///
    /// - Returns: DicticusTranscriptionResult with text, language, and confidence
    /// - Throws: TranscriptionError for pipeline failures (tooShort, silenceOnly, noResult)
    func stopRecordingAndTranscribe() async throws -> DicticusTranscriptionResult {
        guard state == .recording else { throw TranscriptionError.notRecording }

        // Always stop before accessing audioSamples
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        state = .transcribing

        // Ensure state always resets to .idle even if transcription throws
        defer { if state == .transcribing { state = .idle } }

        let samples = sampleBuffer.drain()
        let inputSampleRate = audioEngine.inputNode.outputFormat(forBus: 0).sampleRate

        let transcriptionResult = try await transcribe(
            rawSamples: samples,
            inputSampleRate: inputSampleRate
        ).result

        lastResult = transcriptionResult
        state = .idle
        return transcriptionResult
    }

    /// The transcription path proper, from raw captured samples to a result:
    /// resample → duration guard → AdaptiveVoiceGate → WhisperKit → NoSpeechDiscard
    /// → script validation → language detection → confidence.
    ///
    /// Split out of `stopRecordingAndTranscribe()` (quick task 260802-ass) so archived
    /// capture WAVs can be replayed through the exact same path the live hotkey uses,
    /// without an audio engine. The live caller owns `lastResult`/`state`; this function
    /// is pure with respect to service state so a replay cannot perturb it.
    ///
    /// Returns the per-segment `avgLogprob`/`noSpeechProb` alongside the result — the
    /// live path discards them, the replay harness records them.
    private func transcribe(
        rawSamples samples: [Float],
        inputSampleRate: Double
    ) async throws -> (result: DicticusTranscriptionResult, avgLogprobs: [Float], noSpeechProbs: [Float]) {
        // Resample to 16kHz mono if hardware sample rate differs.
        // WhisperKit requires 16kHz Float32 mono input.
        let resampledSamples: [Float]
        if abs(inputSampleRate - sampleRate) > 1.0 {
            resampledSamples = resampleAudio(samples, from: inputSampleRate, to: sampleRate)
        } else {
            resampledSamples = samples
        }

        let durationSeconds = Float(resampledSamples.count) / Float(sampleRate)

        // Layer 1: Minimum duration guard (D-11)
        guard durationSeconds >= minimumDurationSeconds else {
            #if DEBUG_RECORDER
            let energy = AudioProcessor.calculateEnergy(of: resampledSamples)
            await DiscardProbe.shared.record(
                reason: "tooShort",
                platform: "macOS",
                rawSampleCount: samples.count,
                resampledSampleCount: resampledSamples.count,
                hwSampleRate: inputSampleRate,
                durationSeconds: durationSeconds,
                rms: energy.avg,
                peak: energy.max
            )
            #endif
            throw TranscriptionError.tooShort  // defer resets to .idle
        }

        // Layer 2: Adaptive voice-activity gate (WHISP-03 cycle 2 — reintroduces an
        // input-energy pre-filter after cycle 1 removed the fixed-threshold EnergyVAD
        // entirely; see whisper-dictation-dropout debug session). Unlike the removed
        // EnergyVAD, the threshold is computed relative to THIS clip's own noise floor,
        // so it self-calibrates across microphones instead of assuming one fixed RMS
        // ceiling. This exists because Layer 3 (NoSpeechDiscard, below) cannot catch a
        // CONFIDENT Whisper silence hallucination — a low noSpeechProb by definition —
        // so an energy gate ahead of WhisperKit is the only mechanism that can.
        let gateFrameEnergies = Self.frameEnergies(of: resampledSamples, sampleRate: sampleRate)
        let gateDecision = AdaptiveVoiceGate.evaluate(frameEnergies: gateFrameEnergies)
        guard gateDecision.voiceDetected else {
            #if DEBUG_RECORDER
            // Discard-path regression net only — the temporary pass-path probe used to
            // verify the quiet-speech margin during on-device UAT was removed 2026-07-05
            // once both directions (silence discarded, quiet/normal speech transcribed)
            // were confirmed on-device.
            let gateEnergy = AudioProcessor.calculateEnergy(of: resampledSamples)
            await DiscardProbe.shared.record(
                reason: "silenceOnly_energyGate",
                platform: "macOS",
                rawSampleCount: samples.count,
                resampledSampleCount: resampledSamples.count,
                hwSampleRate: inputSampleRate,
                durationSeconds: durationSeconds,
                rms: gateEnergy.avg,
                peak: gateEnergy.max,
                vadFrameCount: gateFrameEnergies.count,
                vadTrueFrameCount: gateFrameEnergies.filter { $0 > gateDecision.threshold }.count,
                vadMaxFrameEnergy: gateDecision.maxFrameEnergy,
                gateNoiseFloor: gateDecision.noiseFloor,
                gateThreshold: gateDecision.threshold
            )
            #endif
            throw TranscriptionError.silenceOnly  // defer resets to .idle
        }

        // Layer 3: Transcribe via WhisperKit large-v3-turbo.
        //
        // Whisper's seq2seq decoder does not need the trailing-silence tail-pad Parakeet's
        // TDT decoder required to flush its final token (spike 008 Fix B) — removed per the
        // 41-05 decision (Whisper has no equivalent terminal-punctuation tail-drop failure mode).
        // Do NOT reintroduce `promptTokens` here. Spike 260802 wired Whisper's
        // initial-prompt bias to pre-empt the user's German-L1 phoneme confusions and
        // measured it over 154 archived captures: it breaks ~50% of decodes into
        // noResult AND fabricates content absent from every baseline transcript. A
        // 24-file matrix with an in-batch control falsified both alternative causes
        // (detectLanguage, and the quality-fallback thresholds) — the promptTokens path
        // itself is the failure, so it is not a tuning problem. See commits 5978e66 /
        // 85a933c and .planning/quick/260802-ass-*.
        let decodeOptions = DecodingOptions(
            language: nil,
            detectLanguage: true,
            withoutTimestamps: true,
            suppressBlank: true,
            compressionRatioThreshold: 2.4,
            logProbThreshold: -1.0,
            noSpeechThreshold: 0.6,
            chunkingStrategy: .vad
        )
        let results = try await whisperKit.transcribe(audioArray: resampledSamples, decodeOptions: decodeOptions)
        let allSegments = results.flatMap { $0.segments }

        // No-speech discard (WHISP-03 Pitfall 2): WhisperKit does not auto-blank `text` for
        // pure silence — noSpeechProb only drives internal decoder fallback, not output
        // suppression. Inspect segments ourselves before building the result.
        guard !NoSpeechDiscard.looksLikeSilence(noSpeechProbs: allSegments.map(\.noSpeechProb)) else {
            #if DEBUG_RECORDER
            let energy = AudioProcessor.calculateEnergy(of: resampledSamples)
            await DiscardProbe.shared.record(
                reason: "silenceOnly_noSpeechDiscard",
                platform: "macOS",
                rawSampleCount: samples.count,
                resampledSampleCount: resampledSamples.count,
                hwSampleRate: inputSampleRate,
                durationSeconds: durationSeconds,
                rms: energy.avg,
                peak: energy.max,
                segments: allSegments.map {
                    DiscardProbe.SegmentInfo(text: $0.text, noSpeechProb: $0.noSpeechProb, avgLogProb: $0.avgLogprob)
                }
            )
            #endif
            throw TranscriptionError.silenceOnly  // defer resets to .idle
        }

        #if DEBUG_RECORDER
        // Quick task 260719-9a6, MEASURE-FIRST: the discard paths above already log each
        // segment's noSpeechProb/avgLogProb, but a SUCCESSFUL transcription never has —
        // there is currently no way to check whether a mid-utterance ASR phantom (a
        // fabricated clause inserted during a pause) is separable from real speech by
        // its own per-segment signals. This call has no effect on control flow or the
        // produced text; it only appends every kept segment to the same discard-*.jsonl
        // writer under reason: "pass" for a future measurement pass.
        await DiscardProbe.shared.record(
            reason: "pass",
            platform: "macOS",
            rawSampleCount: samples.count,
            resampledSampleCount: resampledSamples.count,
            hwSampleRate: inputSampleRate,
            durationSeconds: durationSeconds,
            segments: allSegments.map {
                DiscardProbe.SegmentInfo(
                    text: $0.text,
                    noSpeechProb: $0.noSpeechProb,
                    avgLogProb: $0.avgLogprob,
                    startSeconds: $0.start,
                    endSeconds: $0.end
                )
            },
            lowConfidenceShort: LowConfidenceShort.flag(
                durationSeconds: durationSeconds,
                avgLogProbs: allSegments.map(\.avgLogprob)
            )
        )
        #endif

        let combinedText = results.map(\.text).joined(separator: " ")

        #if DEBUG_RECORDER
        // Spike 008's Fix A/B distinction was Parakeet-specific (tail-drop vs capture-cut).
        // Kept for ongoing monitoring of genuine capture-cuts (audio severed mid-word) —
        // no second transcribe is needed.
        if AudioCaptureProbe.looksClipped(combinedText) {
            await AudioCaptureProbe.shared.record(
                samples16k: resampledSamples,
                rawSampleCount: samples.count,
                hwSampleRate: inputSampleRate,
                unpaddedText: combinedText,
                paddedText: nil
            )
        }
        #endif

        let trimmedText = combinedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            #if DEBUG_RECORDER
            let energy = AudioProcessor.calculateEnergy(of: resampledSamples)
            await DiscardProbe.shared.record(
                reason: "noResult",
                platform: "macOS",
                rawSampleCount: samples.count,
                resampledSampleCount: resampledSamples.count,
                hwSampleRate: inputSampleRate,
                durationSeconds: durationSeconds,
                rms: energy.avg,
                peak: energy.max,
                segments: allSegments.map {
                    DiscardProbe.SegmentInfo(text: $0.text, noSpeechProb: $0.noSpeechProb, avgLogProb: $0.avgLogprob)
                }
            )
            #endif
            throw TranscriptionError.noResult  // defer resets to .idle
        }

        // Script validation: reject non-Latin output (ASR may output Cyrillic/CJK/Arabic
        // when spoken language doesn't match expectations — T-03-13 mitigation)
        guard !Self.containsNonLatinScript(trimmedText) else {
            throw TranscriptionError.unexpectedLanguage
        }

        // Post-hoc language detection restricted to {de, en} (D-13) — WhisperKit's native
        // result.language comes from auto-detect and drives decoding only; kept separate
        // per the 41-05 decision (lower-risk "nothing downstream changes").
        let detectedLanguage = detectLanguage(combinedText)

        // Confidence derived from segment avgLogprob (WhisperKit has no direct .confidence).
        let avgLogprobs = allSegments.map(\.avgLogprob)
        let meanLogprob = avgLogprobs.isEmpty ? 0 : avgLogprobs.reduce(0, +) / Float(avgLogprobs.count)
        let confidence = exp(meanLogprob)

        let transcriptionResult = DicticusTranscriptionResult(
            text: trimmedText,
            language: detectedLanguage,
            confidence: confidence
        )

        return (transcriptionResult, avgLogprobs, allSegments.map(\.noSpeechProb))
    }

    // MARK: - Adaptive voice gate support

    /// Compute per-frame RMS energies for AdaptiveVoiceGate, chunking `samples`
    /// into `frameLengthSeconds`-long windows (default 0.1s, matching the
    /// removed EnergyVAD's frame length) and reusing WhisperKit's own
    /// `AudioProcessor.calculateAverageEnergy(of:)` per chunk rather than
    /// hand-rolling an RMS calculation.
    static func frameEnergies(of samples: [Float], sampleRate: Double, frameLengthSeconds: Float = 0.1) -> [Float] {
        guard !samples.isEmpty else { return [] }
        let frameLengthSamples = max(1, Int(frameLengthSeconds * Float(sampleRate)))
        var energies: [Float] = []
        energies.reserveCapacity((samples.count + frameLengthSamples - 1) / frameLengthSamples)
        var start = 0
        while start < samples.count {
            let end = min(start + frameLengthSamples, samples.count)
            energies.append(AudioProcessor.calculateAverageEnergy(of: Array(samples[start..<end])))
            start = end
        }
        return energies
    }

    // MARK: - Resampling

    /// Resample audio from one sample rate to another.
    ///
    /// Primary path: AVAudioConverter (Apple's high-quality resampler, recommended per RESEARCH.md).
    /// Fallback: Linear interpolation if AVAudioConverter setup fails.
    ///
    /// - Parameter samples: Input audio samples at sourceSampleRate
    /// - Parameter sourceSampleRate: Native hardware sample rate (typically 44.1kHz or 48kHz)
    /// - Parameter targetSampleRate: Parakeet's required rate (16kHz)
    private func resampleAudio(_ samples: [Float], from sourceSampleRate: Double, to targetSampleRate: Double) -> [Float] {
        // Primary path: AVAudioConverter
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
            // Fallback to linear interpolation if AVAudioConverter setup fails
            return resampleLinear(samples, from: sourceSampleRate, to: targetSampleRate)
        }

        // Copy samples into source buffer
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
        
        // Fix for "Mutation of captured var 'didProvideData' in concurrently-executing code"
        // Use a class to wrap the boolean for thread-safe access in the closure.
        final class ConversionState: @unchecked Sendable { var didProvideData = false }
        let state = ConversionState()
        
        converter.convert(to: outputBuffer, error: &conversionError) { inNumPackets, outStatus in
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

    /// Fallback resampler using linear interpolation.
    /// Used when AVAudioConverter setup fails (e.g., invalid format parameters).
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

    /// Latin Unicode scalar ranges that are allowed in transcription output.
    /// Covers Basic Latin, Latin Extended-A/B, Latin Extended Additional,
    /// Latin Extended-C, and Latin Extended-D blocks.
    private static let latinRanges: [ClosedRange<UInt32>] = [
        0x0000...0x007F,   // Basic Latin (ASCII)
        0x0080...0x00FF,   // Latin-1 Supplement (umlauts, accented chars)
        0x0100...0x024F,   // Latin Extended-A + B
        0x1E00...0x1EFF,   // Latin Extended Additional
        0x2C60...0x2C7F,   // Latin Extended-C
        0xA720...0xA7FF,   // Latin Extended-D
        0x0300...0x036F,   // Combining Diacritical Marks (accents on Latin base)
    ]

    /// Check if text contains non-Latin script characters (Cyrillic, CJK, Arabic, etc.).
    ///
    /// The ASR engine may output characters from unexpected scripts when the spoken
    /// language doesn't match well. This guard prevents garbled text from being injected
    /// at the user's cursor.
    ///
    /// Logic: any Unicode letter that is NOT in the Latin character sets is flagged.
    /// Numbers, punctuation, symbols, and combining marks are always allowed.
    ///
    /// Static so it can be unit tested without a WhisperKit instance.
    static func containsNonLatinScript(_ text: String) -> Bool {
        let log = Logger(subsystem: "com.dicticus", category: "validation")
        let letters = CharacterSet.letters
        
        // Symbols and punctuation we explicitly want to allow even if they aren't 'Latin'
        let allowedSymbols = CharacterSet(charactersIn: "$€£¥©®™°%‰#@&*-+=/\\|<>{}[]()\"'`^~_")
        let allowedPunctuation = CharacterSet.punctuationCharacters
        let allowedNumbers = CharacterSet.decimalDigits
        
        for scalar in text.unicodeScalars {
            // If it's a number, punctuation, or common symbol, it's fine.
            if allowedNumbers.contains(scalar) || allowedPunctuation.contains(scalar) || allowedSymbols.contains(scalar) {
                continue
            }
            
            // If it's a letter, check if it's in a Latin range.
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
    ///
    /// WhisperKit's native `result.language` comes from auto-detect and drives decoding
    /// only (41-05 decision); we use Apple's NLLanguageRecognizer post-hoc on the
    /// transcribed text for the result's `language` field to keep this "nothing
    /// downstream changes" lower-risk.
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

    // MARK: - Language restriction

    /// Restrict a detected language code to the allowed set {de, en} (D-13 in 02.1-CONTEXT.md).
    ///
    /// Used as a validation layer after post-hoc language detection.
    /// Any other detected language defaults to English.
    ///
    /// - Parameter detected: Language code string
    /// - Returns: "de" or "en"
    func restrictLanguage(_ detected: String) -> String {
        let allowed: Set<String> = ["de", "en"]
        return allowed.contains(detected) ? detected : "en"
    }
}

// MARK: - Test support

#if DEBUG
extension TranscriptionService {

    /// Static wrapper for `restrictLanguage` allowing unit tests to call it without
    /// a WhisperKit instance. This avoids a protocol-based architecture just for testing.
    ///
    /// Tests call: `TranscriptionService.testRestrictLanguage("fr") == "en"`
    static func testRestrictLanguage(_ detected: String) -> String {
        let allowed: Set<String> = ["de", "en"]
        return allowed.contains(detected) ? detected : "en"
    }

    /// Static wrapper for `detectLanguage` allowing unit tests to call it without
    /// a WhisperKit instance.
    ///
    /// Tests call: `TranscriptionService.testDetectLanguage("Dies ist ein Satz") == "de"`
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

    /// Returns true if the WhisperKit large-v3-turbo model is cached on this machine.
    /// Used by tests to conditionally skip model-dependent tests.
    static func isWhisperKitAvailable() -> Bool {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        guard let base = documentsDir else { return false }
        let modelDir = base
            .appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml")
            .appendingPathComponent(AsrModelLoader.modelName)
        return (try? FileManager.default.contentsOfDirectory(atPath: modelDir.path))?.isEmpty == false
    }

    /// Attempt to create a TranscriptionService using a WhisperKit-backed instance.
    /// Returns nil if initialization fails (model not cached, etc.).
    /// Used by tests that need an actual service instance.
    static func makeForTesting() async throws -> TranscriptionService? {
        do {
            let wk = try await AsrModelLoader.loadWhisperKit()
            return TranscriptionService(whisperKit: wk)
        } catch {
            return nil
        }
    }

    /// Replay already-captured samples through the live transcription path.
    ///
    /// Used by the archived-WAV replay harness (quick task 260802-ass) to measure ASR
    /// behaviour across recordings without an audio engine. Because it calls the same
    /// `transcribe(rawSamples:inputSampleRate:)` the hotkey path calls, the gates
    /// (duration, AdaptiveVoiceGate, NoSpeechDiscard) apply identically — a replay that
    /// throws `.silenceOnly` is a faithful reproduction, not a harness artifact.
    func testTranscribe(
        samples: [Float],
        inputSampleRate: Double
    ) async throws -> (result: DicticusTranscriptionResult, avgLogprobs: [Float], noSpeechProbs: [Float]) {
        try await transcribe(rawSamples: samples, inputSampleRate: inputSampleRate)
    }
}
#endif
