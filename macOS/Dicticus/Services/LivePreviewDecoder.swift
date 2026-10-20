import Foundation
import WhisperKit

/// Interim decode for the live transcript overlay (Phase 51, D-01..D-05, D-19).
///
/// Reads a non-destructive tail snapshot of the capture buffer, resamples it off the
/// main actor, decodes it on the service's WhisperKit instance and runs the text-only
/// phantom filters and the dictionary. The result feeds the preview panel and nothing
/// else; the pasted text always comes from the end-of-recording decode.
///
/// The energy gates and the short-clip rules of the final path are deliberately not
/// applied to decoded text (D-03), and this type writes no diagnostic records. A voice
/// gate (`LivePreviewVoiceGate`) only decides whether a tick decodes at all: ticks with
/// no new voiced audio since the last decode are skipped. Spike 018's latency figures
/// predate that gate.
@MainActor
final class LivePreviewDecoder {

    /// Newest audio decoded per tick. The pane shows 3-4 lines, about 10-12 s of speech.
    static let tailSeconds: Double = 15

    /// WhisperKit decodes nothing below about 1 s of audio (its window padding).
    static let minimumPreviewSeconds: Double = 1.2

    nonisolated static let targetSampleRate: Double = 16000

    /// The final path's decode options, plus no temperature fallback: a fallback
    /// re-decode would multiply the time the release has to wait for the drain.
    static let decodeOptions = DecodingOptions(
        language: nil,
        temperatureFallbackCount: 0,
        detectLanguage: true,
        withoutTimestamps: true,
        suppressBlank: true,
        compressionRatioThreshold: 2.4,
        logProbThreshold: -1.0,
        noSpeechThreshold: 0.6,
        chunkingStrategy: .vad
    )

    /// Per-tick timing for the latency spike and the recorder; compiled out of Release.
    struct Timing: Sendable {
        var snapshotMs: Double
        var resampleMs: Double
        var decodeMs: Double
        var filterMs: Double
        var tokenCount: Int
    }

    /// The model call: 16 kHz samples and options in, chunk results out. Production wraps
    /// the service's WhisperKit instance; a test supplies canned results.
    typealias Transcribe = @MainActor ([Float], DecodingOptions) async throws -> [TranscriptionResult]

    private let transcribe: Transcribe
    private let buffer: AudioSampleBuffer
    private let inputSampleRate: Double
    private let dictionary: @MainActor (String) -> String
    private let onSilence: (@MainActor () -> Void)?
    private var gate: LivePreviewVoiceGate

    /// Set only in DEBUG builds.
    private(set) var lastTiming: Timing?

    /// Ticks the voice gate skipped because no new voiced audio had arrived.
    private(set) var skippedNoVoice = 0

    /// True when the last `decodeTail()` call reached the model; false for ticks that
    /// returned early (too little audio, gate skip). The session's budget counts only
    /// ticks that ran the model.
    private(set) var lastTickRanModel = false

    convenience init(
        whisperKit: WhisperKit,
        buffer: AudioSampleBuffer,
        inputSampleRate: Double,
        dictionary: @escaping @MainActor (String) -> String = { DictionaryService.shared.apply(to: $0) },
        onSilence: (@MainActor () -> Void)? = nil
    ) {
        self.init(
            transcribe: { samples, options in try await whisperKit.transcribe(audioArray: samples, decodeOptions: options) },
            buffer: buffer, inputSampleRate: inputSampleRate, dictionary: dictionary, onSilence: onSilence)
    }

    init(
        transcribe: @escaping Transcribe,
        buffer: AudioSampleBuffer,
        inputSampleRate: Double,
        dictionary: @escaping @MainActor (String) -> String = { DictionaryService.shared.apply(to: $0) },
        onSilence: (@MainActor () -> Void)? = nil
    ) {
        self.transcribe = transcribe
        self.buffer = buffer
        self.inputSampleRate = inputSampleRate
        self.dictionary = dictionary
        self.onSilence = onSilence
        self.gate = LivePreviewVoiceGate(inputSampleRate: inputSampleRate)
    }

    /// The one WhisperKit call of this file. Takes 16 kHz samples and explicit options
    /// so the latency sweep can time both option sets through the same code.
    func decodeResampled(_ samples16k: [Float], options: DecodingOptions) async throws -> [TranscriptionResult] {
        try await transcribe(samples16k, options)
    }

    /// One preview tick. Returns nil when the voice gate skips the tick, when there is too
    /// little audio, on a decode error, a cancellation, or when the filters reject the text.
    ///
    /// The gate decides whether to decode and never filters a decoded text (D-03). It
    /// frames only the audio added since the last tick, but measures it against the noise
    /// floor of the whole hold, so continuous speech is not mistaken for its own floor.
    func decodeTail() async -> String? {
        #if DEBUG
        let clock = ContinuousClock()
        let t0 = clock.now
        #endif
        lastTickRanModel = false

        let rate = inputSampleRate
        // Before the gate: a short opening word must not be consumed without a decode.
        guard Double(buffer.count) / rate >= Self.minimumPreviewSeconds else { return nil }

        let fresh = buffer.snapshot(from: gate.framedSamples).samples
        switch gate.step(samples: fresh) {
        case .skip(let signalPause):
            skippedNoVoice += 1
            if signalPause { onSilence?() }
            return nil
        case .decode:
            lastTickRanModel = true
        }

        let tail = buffer.snapshotTail(maxSamples: Int(Self.tailSeconds * rate))
        #if DEBUG
        let t1 = clock.now
        #endif

        let samples16k: [Float]
        if abs(rate - Self.targetSampleRate) > 1.0 {
            samples16k = await Task.detached(priority: .userInitiated) {
                TranscriptionService.resampleAudio(tail, from: rate, to: Self.targetSampleRate)
            }.value
        } else {
            samples16k = tail
        }
        #if DEBUG
        let t2 = clock.now
        #endif

        let results: [TranscriptionResult]
        do {
            results = try await decodeResampled(samples16k, options: Self.decodeOptions)
        } catch {
            return nil
        }
        #if DEBUG
        let t3 = clock.now
        #endif

        // A cancelled decode can return normally with partial text.
        guard !Task.isCancelled else { return nil }

        let text = Self.previewText(
            from: results.map { (text: $0.text, language: $0.language) },
            dictionary: dictionary
        )
        #if DEBUG
        let t4 = clock.now
        lastTiming = Timing(
            snapshotMs: Self.milliseconds(t1 - t0),
            resampleMs: Self.milliseconds(t2 - t1),
            decodeMs: Self.milliseconds(t3 - t2),
            filterMs: Self.milliseconds(t4 - t3),
            tokenCount: results.reduce(0) { $0 + $1.segments.reduce(0) { $0 + $1.tokens.count } }
        )
        #endif
        return text
    }

    /// Text-only filter chain. Phantom chunks and whole-utterance boilerplate are
    /// dropped (D-03), foreign script is dropped (D-19), and the dictionary runs last,
    /// only on text that survived (D-05).
    static func previewText(
        from chunks: [(text: String, language: String)],
        dictionary: @MainActor (String) -> String
    ) -> String? {
        let drops = BoilerplateHallucination.chunkDropReasons(chunks)
        let joined = zip(chunks, drops)
            .filter { $0.1 == nil }
            .map(\.0.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !joined.isEmpty,
              BoilerplateHallucination.match(joined) == nil,
              !TranscriptionService.containsNonLatinScript(joined)
        else { return nil }
        return dictionary(joined)
    }

    private static func milliseconds(_ d: Duration) -> Double {
        Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
    }
}

/// Voice decision and per-tick bookkeeping of the preview scheduler (Phase 51-11).
///
/// Holds the 100 ms frame energies of the whole hold. A tick decodes only when a frame
/// added since the last decode exceeds the `AdaptiveVoiceGate` threshold computed over
/// every frame so far, the same function and measured constants as the final path's
/// Layer 2. A fixed threshold once dropped low-gain speech (AdaptiveVoiceGate header), and
/// a threshold over the new frames alone would read continuous speech as its own floor.
///
/// The absolute floor is per hold (`previewAbsoluteFloor`): a quiet microphone such as an
/// Elgato Wave XLR peaks at 0.0045-0.0060 on speech, below the final path's fixed 0.006, and
/// the preview, unlike the final path, has no duration bypass, so it stayed empty. Any hold
/// whose loudest frame reaches 0.012 keeps the 0.006 floor, so the main microphone is unchanged
/// once speech has occurred; a quieter hold gets half its own loudest frame, never below 0.001.
/// The noise-ratio term still rejects steady fan noise.
///
/// Sees energies only, never audio samples beyond framing and never any text.
@MainActor
struct LivePreviewVoiceGate: Sendable {

    enum Outcome: Equatable, Sendable {
        case decode
        /// `signalPause` is true on the first skipped tick after voiced audio.
        case skip(signalPause: Bool)
    }

    private(set) var energies: [Float] = []
    /// Samples already framed. The next snapshot starts here, so a partial frame at the
    /// end of one tick is read again, complete, on the next.
    private(set) var framedSamples = 0
    /// Frames up to this index were part of a decode.
    private(set) var decodedFrameCount = 0
    private var voicedSincePauseSignal = false
    private let inputSampleRate: Double
    private let frameSamples: Int

    /// Fraction of the loudest frame so far that the absolute floor follows on a quiet microphone.
    nonisolated static let previewPeakFraction: Float = 0.5
    /// Lowest absolute floor, so digital silence and dither never count as voice.
    nonisolated static let previewMinimumFloor: Float = 0.001

    init(inputSampleRate: Double) {
        self.inputSampleRate = inputSampleRate
        // Same expression as TranscriptionService.frameEnergies, so frames line up exactly.
        frameSamples = max(1, Int(0.1 * Float(inputSampleRate)))
    }

    /// The hold's absolute floor: half the loudest frame, capped at the final path's 0.006
    /// and never below `previewMinimumFloor`.
    nonisolated static func previewAbsoluteFloor(energies: [Float]) -> Float {
        let loudest = energies.max() ?? 0
        return max(previewMinimumFloor, min(AdaptiveVoiceGate.defaultAbsoluteFloor, previewPeakFraction * loudest))
    }

    /// True when a frame at or after `sinceFrame` exceeds the threshold computed over all
    /// of `energies`. No new frames means no voice.
    nonisolated static func hasNewVoice(energies: [Float], sinceFrame: Int) -> Bool {
        let first = max(0, sinceFrame)
        guard first < energies.count else { return false }
        let threshold = AdaptiveVoiceGate.evaluate(
            frameEnergies: energies,
            absoluteFloor: previewAbsoluteFloor(energies: energies)
        ).threshold
        return energies[first...].contains { $0 > threshold }
    }

    /// Frames the complete 100 ms frames in `samples` (the audio after `framedSamples`)
    /// and steps once.
    mutating func step(samples: [Float]) -> Outcome {
        let complete = samples.count / frameSamples
        guard complete > 0 else { return step(newFrameEnergies: []) }
        let consumed = complete * frameSamples
        let frames = TranscriptionService.frameEnergies(
            of: Array(samples[0..<consumed]),
            sampleRate: inputSampleRate
        )
        framedSamples += consumed
        return step(newFrameEnergies: frames)
    }

    mutating func step(newFrameEnergies: [Float]) -> Outcome {
        energies.append(contentsOf: newFrameEnergies)
        if Self.hasNewVoice(energies: energies, sinceFrame: decodedFrameCount) {
            decodedFrameCount = energies.count
            voicedSincePauseSignal = true
            return .decode
        }
        let signal = voicedSincePauseSignal
        voicedSincePauseSignal = false
        return .skip(signalPause: signal)
    }
}
