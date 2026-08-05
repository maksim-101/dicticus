import Foundation
import SwiftUI
import WhisperKit
@preconcurrency import AVFoundation
import NaturalLanguage
import os

/// Errors thrown by IOSTranscriptionService during the record-transcribe cycle.
enum TranscriptionError: Error, Sendable {
    /// Recording was shorter than minimumDurationSeconds.
    case tooShort
    /// No voice activity detected — adaptive energy gate or no-speech-prob discard.
    case silenceOnly
    /// ASR engine returned no transcription results.
    case noResult
    /// ASR models not available (model not warmed up).
    case modelNotReady
    /// stopRecordingAndTranscribe() called when not recording.
    case notRecording
    /// startRecording() called while already recording or transcribing.
    case busy
    /// ASR output contains non-Latin script (Cyrillic, CJK, Arabic, etc.) — likely a
    /// Parakeet hallucination when the spoken language doesn't match model expectations.
    case unexpectedLanguage
}

/// Thread-safe audio sample buffer for real-time AVAudioEngine tap callbacks.
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

/// Core ASR pipeline for iOS: record audio via AVAudioEngine, apply silence-discard
/// checks, transcribe via WhisperKit large-v3-turbo, and detect language post-hoc
/// with NLLanguageRecognizer. (See whisper-dictation-dropout debug session for the
/// two-cycle Layer 2 history: cycle 1 removed the fixed-threshold EnergyVAD
/// pre-filter that misclassified genuine speech as silence on some microphones;
/// cycle 2 reintroduced Layer 2 as AdaptiveVoiceGate, a clip-relative energy gate,
/// after cycle 1's removal reopened D-09 silence-hallucination pastes.)
@MainActor
class IOSTranscriptionService: ObservableObject {

    // MARK: - State machine

    enum State: Equatable, Sendable {
        case idle
        case recording
        case transcribing
    }

    @Published var state: State = .idle
    @Published var lastResult: DicticusTranscriptionResult?
    @Published var error: String?

    @AppStorage("useCustomDictionary", store: DicticusIPCBridge.defaults)
    var useCustomDictionary = true
    @AppStorage("useITN", store: DicticusIPCBridge.defaults)
    var useITN = true
    @AppStorage("useAutoStop", store: DicticusIPCBridge.defaults)
    var useAutoStop = true

    // MARK: - Configuration

    static let vadProbabilityThreshold: Float = 0.75
    var silenceThreshold: Float = IOSTranscriptionService.vadProbabilityThreshold
    let minimumDurationSeconds: Float = 0.3
    let autoStopSilenceSeconds: Double = 2.5
    let autoStopGracePeriod: Double = 3.0

    // MARK: - Private

    private let whisperKit: WhisperKit
    private let audioEngine = AVAudioEngine()
    private let sampleBuffer = AudioSampleBuffer()
    private let sampleRate: Double = 16000

    /// Callback triggered when Auto-Stop detects sustained silence.
    var onSilenceDetected: (() -> Void)?

    // MARK: - Initialization

    /// Initialize with a warm WhisperKit instance from IOSModelWarmupService.
    /// - Parameter whisperKit: Initialized WhisperKit instance from IOSModelWarmupService.whisperKitInstance
    init(whisperKit: WhisperKit) {
        self.whisperKit = whisperKit
    }

    // MARK: - Recording

    /// Start recording via AVAudioEngine.
    /// On iOS, this requires explicit AVAudioSession management.
    func startRecording() throws {
        guard state == .idle else { throw TranscriptionError.busy }
        sampleBuffer.clear()

        // iOS ONLY: activate AVAudioSession with .playAndRecord so the mic session
        // survives backgrounding (UIBackgroundModes: audio keeps it alive).
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        Self.installTap(
            on: inputNode,
            format: inputFormat,
            buffer: sampleBuffer,
            autoStopEnabled: useAutoStop,
            silenceThreshold: 0.01, // RMS threshold for "silence"
            silenceDuration: autoStopSilenceSeconds,
            gracePeriod: autoStopGracePeriod,
            onSilence: { [weak self] in
                Task { @MainActor in
                    self?.onSilenceDetected?()
                }
            }
        )

        try audioEngine.start()
        state = .recording
    }

    /// Install audio tap in a nonisolated context so the closure has no actor affinity.
    nonisolated private static func installTap(
        on inputNode: AVAudioInputNode,
        format: AVAudioFormat,
        buffer: AudioSampleBuffer,
        autoStopEnabled: Bool,
        silenceThreshold: Float,
        silenceDuration: Double,
        gracePeriod: Double,
        onSilence: @escaping @Sendable () -> Void
    ) {
        // Track silence state in a thread-safe way
        final class SilenceTracker: @unchecked Sendable {
            var startTime = Date()
            var lastSoundTime = Date()
            var didTrigger = false
        }
        let tracker = SilenceTracker()

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) {
            pcmBuffer, _ in
            guard let channelData = pcmBuffer.floatChannelData?[0] else { return }
            let frameCount = Int(pcmBuffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))
            buffer.append(samples)

            if autoStopEnabled {
                let now = Date()
                let elapsedTotal = now.timeIntervalSince(tracker.startTime)
                
                // Simple RMS calculation to detect "sound"
                var sum: Float = 0
                for sample in samples { sum += sample * sample }
                let rms = sqrt(sum / Float(frameCount))
                
                if rms > silenceThreshold {
                    tracker.lastSoundTime = now
                } else if !tracker.didTrigger && elapsedTotal > gracePeriod {
                    let silenceElapsed = now.timeIntervalSince(tracker.lastSoundTime)
                    if silenceElapsed >= silenceDuration {
                        tracker.didTrigger = true
                        onSilence()
                    }
                }
            }
        }
    }

    func cancelRecording() {
        guard state == .recording else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        sampleBuffer.clear()
        state = .idle
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Transcription

    func stopRecordingAndTranscribe() async throws -> DicticusTranscriptionResult {
        guard state == .recording else { throw TranscriptionError.notRecording }

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        // Release the mic session on every exit path (success or throw). Without this the
        // AVAudioSession stays active after a stop, and the next AudioRecordingIntent
        // (Action Button session 2) fatal-asserts: "active audio session but without a
        // Live Activity" (AppIntents PerformActionExecutorTask). Mirrors cancelRecording().
        defer { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
        state = .transcribing

        defer { if state == .transcribing { state = .idle } }

        let samples = sampleBuffer.drain()

        let inputSampleRate = audioEngine.inputNode.outputFormat(forBus: 0).sampleRate
        let resampledSamples: [Float]
        if abs(inputSampleRate - sampleRate) > 1.0 {
            resampledSamples = resampleAudio(samples, from: inputSampleRate, to: sampleRate)
        } else {
            resampledSamples = samples
        }

        let durationSeconds = Float(resampledSamples.count) / Float(sampleRate)

        // Layer 1: Minimum duration guard
        guard durationSeconds >= minimumDurationSeconds else {
            throw TranscriptionError.tooShort
        }

        // Layer 2: Adaptive voice-activity gate (cycle 2 — reintroduces an input-energy
        // pre-filter after cycle 1 removed the fixed-threshold EnergyVAD entirely; see
        // whisper-dictation-dropout debug session). The threshold is computed relative
        // to THIS clip's own noise floor, so it self-calibrates across microphones
        // instead of assuming one fixed RMS ceiling. This exists because Layer 3
        // (NoSpeechDiscard, below) cannot catch a CONFIDENT Whisper silence
        // hallucination — a low noSpeechProb by definition — so an energy gate ahead of
        // WhisperKit is the only mechanism that can.
        let gateFrameEnergies = Self.frameEnergies(of: resampledSamples, sampleRate: sampleRate)
        let gateDecision = AdaptiveVoiceGate.evaluate(frameEnergies: gateFrameEnergies)
        guard gateDecision.voiceDetected else {
            throw TranscriptionError.silenceOnly
        }

        // Layer 3: Transcribe via WhisperKit large-v3-turbo.
        //
        // Whisper's seq2seq decoder does not need the trailing-silence tail-pad Parakeet's
        // TDT decoder required to flush its final token (spike 008 Fix B) — removed per the
        // 41-05/41-06 decision (Whisper has no equivalent terminal-punctuation tail-drop
        // failure mode).
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

        // No-speech discard: WhisperKit does not auto-blank `text` for pure silence —
        // noSpeechProb only drives internal decoder fallback, not output suppression.
        // Inspect segments ourselves before building the result.
        guard !NoSpeechDiscard.looksLikeSilence(noSpeechProbs: allSegments.map(\.noSpeechProb)) else {
            throw TranscriptionError.silenceOnly
        }

        #if DEBUG_RECORDER
        // Quick task 260719-9a6, MEASURE-FIRST: mirrors the macOS pass-path probe added in
        // the same task — iOS never had ANY DiscardProbe call before this (the discard
        // guards above are silent). This has no effect on control flow or the produced
        // text; it only appends every kept segment to the same discard-*.jsonl writer under
        // reason: "pass" for a future measurement pass. NOTE: DEBUG_RECORDER is not
        // currently wired into iOS's project.yml/build configs, so this compiles out to
        // zero runtime effect today — it exists for source parity and to be ready if/when
        // an iOS debug-recorder config is added.
        await DiscardProbe.shared.record(
            reason: "pass",
            platform: "iOS",
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

        var processedText = combinedText.trimmingCharacters(in: .whitespacesAndNewlines)
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

        // Confidence derived from segment avgLogprob (WhisperKit has no direct .confidence).
        let avgLogprobs = allSegments.map(\.avgLogprob)
        let meanLogprob = avgLogprobs.isEmpty ? 0 : avgLogprobs.reduce(0, +) / Float(avgLogprobs.count)
        let confidence = exp(meanLogprob)

        let transcriptionResult = DicticusTranscriptionResult(
            text: processedText,
            language: detectedLanguage,
            confidence: confidence
        )

        lastResult = transcriptionResult
        state = .idle
        return transcriptionResult
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

    /// Attempt to create an IOSTranscriptionService using a WhisperKit-backed instance.
    /// Returns nil if initialization fails (model not cached, etc.).
    /// Used by tests that need an actual service instance.
    static func makeForTesting() async throws -> IOSTranscriptionService? {
        do {
            let wk = try await AsrModelLoader.loadWhisperKit()
            return IOSTranscriptionService(whisperKit: wk)
        } catch {
            return nil
        }
    }
}
#endif
