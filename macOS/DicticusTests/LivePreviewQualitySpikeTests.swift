import XCTest
import WhisperKit
@testable import Dicticus

/// Live-preview quality replay harness (spike 019).
///
/// Opt-in, model required, skips without `DICTICUS_SPIKE_CONFIG` (keys: replay_dir, file_list,
/// out, arms, verify_reuse). Drives the production `LivePreviewDecoder` and `PreviewStabilizer`
/// offline on a fixed 1 s tick schedule. Treatment arms change only the samples and options the
/// decoder's transcribe closure passes to WhisperKit. Rows carry dictated text, so `out` must be
/// a gitignored path.
final class LivePreviewQualitySpikeTests: XCTestCase {

    private static let rate: Double = 16000
    private static let firstTick = 1.5
    private static let tickStep = 1.0
    private static let pauseSearchSeconds = 5.0
    private static let pauseMinFrames = 3

    private enum Arm: String { case A, C, Cstar, D, CD }

    private struct Decode {
        var count: Int
        var language: String
        var results: [TranscriptionResult]
        var minLogprob: Float
        var maxCompression: Float
        var maxNoSpeech: Float
        var reused: Bool
        var trimSeconds: Double
        var ms: Double

        var failsThresholds: Bool { minLogprob < -1.0 || maxCompression > 2.4 }
    }

    @MainActor
    private final class ArmRun {
        let arm: Arm
        var tick = 0
        var tickTime = 0.0
        var pin: String?
        var last: Decode?
        var silenced = false
        var modelMs = 0.0
        init(arm: Arm, pin: String?) { self.arm = arm; self.pin = pin }
        var trimsWindow: Bool { arm == .D || arm == .CD }
        var pinsByRule: Bool { arm == .C || arm == .CD }
    }

    private final class RowWriter {
        private let handle: FileHandle
        init(path: String) throws {
            if !FileManager.default.fileExists(atPath: path) {
                FileManager.default.createFile(atPath: path, contents: nil)
            }
            handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
            try handle.seekToEnd()
        }
        func write(_ row: [String: Any]) {
            guard let data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) else { return }
            handle.write(data)
            handle.write(Data("\n".utf8))
            try? handle.synchronize()
        }
        deinit { try? handle.close() }
    }

    /// Seconds to drop from the head of the 15 s tail so it starts in a pause (arm D), or nil.
    @MainActor private static func pauseTrim(energies: [Float], tickTime t: Double) -> Double? {
        guard let (prefix, threshold, s0) = boundary(energies: energies, tickTime: t),
              !inQuietRun(prefix, at: s0, threshold: threshold) else { return nil }
        let lastStart = min(s0 + Int(pauseSearchSeconds * 10), prefix.count - pauseMinFrames)
        guard s0 <= lastStart else { return nil }
        for f in s0...lastStart where prefix[f..<f + pauseMinFrames].allSatisfy({ $0 <= threshold }) {
            var end = f + pauseMinFrames
            while end < prefix.count, prefix[end] <= threshold { end += 1 }
            let middle = Double(f + end) / 2
            return (middle - Double(s0)) / 10
        }
        return nil
    }

    @MainActor private static func boundaryVoiced(energies: [Float], tickTime t: Double) -> Bool {
        guard let (prefix, threshold, s0) = boundary(energies: energies, tickTime: t) else { return false }
        return !inQuietRun(prefix, at: s0, threshold: threshold)
    }

    /// Frames of clip[0, t), the gate threshold over them and the tail's start frame, when t > 15 s.
    @MainActor private static func boundary(energies: [Float], tickTime t: Double) -> ([Float], Float, Int)? {
        let tail = LivePreviewDecoder.tailSeconds
        guard t > tail else { return nil }
        let prefix = Array(energies.prefix(Int((t * 10).rounded())))
        let s0 = Int(((t - tail) * 10).rounded())
        guard s0 < prefix.count else { return nil }
        return (prefix, AdaptiveVoiceGate.evaluate(frameEnergies: prefix).threshold, s0)
    }

    /// True when frame `i` lies inside a run of at least `pauseMinFrames` quiet frames.
    private static func inQuietRun(_ frames: [Float], at i: Int, threshold: Float) -> Bool {
        guard frames[i] <= threshold else { return false }
        var lo = i, hi = i
        while lo > 0, frames[lo - 1] <= threshold { lo -= 1 }
        while hi + 1 < frames.count, frames[hi + 1] <= threshold { hi += 1 }
        return hi - lo + 1 >= pauseMinFrames
    }

    private static func milliseconds(_ d: Duration) -> Double {
        Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
    }

    @MainActor
    func testSpike019Quality() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let configPath = env["DICTICUS_SPIKE_CONFIG"] else {
            throw XCTSkip("Set DICTICUS_SPIKE_CONFIG to run spike 019.")
        }
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: configPath))) as? [String: Any])
        let replayDir = try XCTUnwrap(json["replay_dir"] as? String)
        let files = try String(contentsOfFile: try XCTUnwrap(json["file_list"] as? String), encoding: .utf8)
            .split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        let arms = ((json["arms"] as? [String]) ?? ["A", "C", "Cstar", "D", "CD"]).compactMap(Arm.init(rawValue:))
        var verifyReuse = (json["verify_reuse"] as? Int) ?? 0
        let writer = try RowWriter(path: try XCTUnwrap(json["out"] as? String))

        guard TranscriptionService.isWhisperKitAvailable() else {
            throw XCTSkip("WhisperKit model not cached — cannot decode.")
        }
        guard let service = try await TranscriptionService.makeForTesting() else {
            throw XCTSkip("Could not construct TranscriptionService.")
        }
        let whisperKit = service.testWhisperKit
        let dictionary: @MainActor (String) -> String = { DictionaryService.shared.apply(to: $0) }
        let clock = ContinuousClock()

        for name in files {
            let url = URL(fileURLWithPath: replayDir).appendingPathComponent(name)
            guard let (samples, rate) = AsrReplayHarnessTests.readWav(url), abs(rate - Self.rate) < 1 else {
                writer.write(["kind": "skip", "file": name, "reason": "unreadable or not 16 kHz"])
                continue
            }
            let duration = Double(samples.count) / Self.rate
            let fileStart = clock.now

            var finalText: String?
            var finalError = ""
            do {
                finalText = dictionary(try await service.testTranscribe(samples: samples, inputSampleRate: Self.rate).result.text)
            } catch {
                finalError = String(describing: error)
            }
            let oracle = try? await whisperKit.detectLangauge(audioArray: samples)
            let energies = TranscriptionService.frameEnergies(of: samples, sampleRate: Self.rate)
            let ticks = Array(stride(from: Self.firstTick, through: duration, by: Self.tickStep))

            var cacheA: [Int: Decode] = [:]
            var fileRow: [String: Any] = [
                "kind": "file", "file": name, "duration_s": duration, "ticks": ticks.count,
                "final_text": finalText ?? NSNull(), "final_error": finalError,
                "oracle_lang": oracle?.language ?? NSNull()
            ]

            for arm in arms {
                let run = ArmRun(arm: arm, pin: arm == .Cstar ? oracle?.language : nil)
                let transcribe: LivePreviewDecoder.Transcribe = { input, options in
                    var audio = input
                    var opts = options
                    var trim = 0.0
                    if run.trimsWindow, let t = Self.pauseTrim(energies: energies, tickTime: run.tickTime) {
                        trim = t
                        audio = Array(input.dropFirst(Int((t * Self.rate).rounded())))
                    }
                    if let pin = run.pin {
                        opts.language = pin
                        opts.detectLanguage = false
                    }
                    if run.arm != .A, let a = cacheA[run.tick], a.count == audio.count,
                       opts.language == nil || opts.language == a.language {
                        if run.arm == .Cstar, verifyReuse > 0, opts.language != nil {
                            verifyReuse -= 1
                            let again = try await whisperKit.transcribe(audioArray: audio, decodeOptions: opts)
                            writer.write([
                                "kind": "reuse_check", "file": name, "k": run.tick,
                                "same": again.map(\.text) == a.results.map(\.text)
                            ])
                        }
                        var reused = a
                        reused.reused = true
                        reused.trimSeconds = trim
                        run.last = reused
                        return a.results
                    }
                    let began = clock.now
                    let results = try await whisperKit.transcribe(audioArray: audio, decodeOptions: opts)
                    let ms = Self.milliseconds(clock.now - began)
                    run.modelMs += ms
                    let segments = results.flatMap(\.segments)
                    let decode = Decode(
                        count: audio.count,
                        language: results.first?.language ?? "",
                        results: results,
                        minLogprob: segments.map(\.avgLogprob).min() ?? 0,
                        maxCompression: segments.map(\.compressionRatio).max() ?? 0,
                        maxNoSpeech: segments.map(\.noSpeechProb).max() ?? 0,
                        reused: false, trimSeconds: trim, ms: ms)
                    if run.arm == .A { cacheA[run.tick] = decode }
                    run.last = decode
                    return results
                }

                let buffer = AudioSampleBuffer()
                let decoder = LivePreviewDecoder(
                    transcribe: transcribe, buffer: buffer, inputSampleRate: Self.rate,
                    dictionary: dictionary, onSilence: { run.silenced = true })
                var shown = PreviewStabilizer()
                var shownFiltered = PreviewStabilizer()
                var fed = 0

                for (k, t) in ticks.enumerated() {
                    run.tick = k
                    run.tickTime = t
                    run.last = nil
                    run.silenced = false
                    let end = min(samples.count, Int((t * Self.rate).rounded()))
                    if end > fed { buffer.append(Array(samples[fed..<end])) }
                    fed = end

                    let text = await decoder.decodeTail()
                    let ran = decoder.lastTickRanModel
                    let decode = ran ? run.last : nil
                    let fails = decode?.failsThresholds ?? false
                    if let text {
                        shown.ingest(text)
                        if !fails { shownFiltered.ingest(text) }
                    }
                    if run.silenced {
                        shown.settleAll()
                        shownFiltered.settleAll()
                    }
                    let pinBefore = run.pin
                    if run.pinsByRule, run.pin == nil, let text, let decode, !fails,
                       text.split(whereSeparator: \.isWhitespace).count >= 4 {
                        run.pin = decode.language
                    }

                    var row: [String: Any] = [
                        "kind": "tick", "file": name, "arm": arm.rawValue, "k": k, "t": t,
                        "ran": ran, "text": text ?? NSNull(), "silenced": run.silenced,
                        "displayed": [shown.settledText, shown.tentativeText].filter { !$0.isEmpty }.joined(separator: " "),
                        "displayed_filtered": [shownFiltered.settledText, shownFiltered.tentativeText]
                            .filter { !$0.isEmpty }.joined(separator: " "),
                        "boundary_voiced": Self.boundaryVoiced(energies: energies, tickTime: t),
                        "pin": pinBefore ?? NSNull()
                    ]
                    if let decode {
                        row["lang"] = decode.language
                        row["fails"] = fails
                        row["min_logprob"] = decode.minLogprob
                        row["max_compression"] = decode.maxCompression
                        row["max_no_speech"] = decode.maxNoSpeech
                        row["reused"] = decode.reused
                        row["trim_s"] = decode.trimSeconds
                        row["decode_ms"] = decode.ms
                    }
                    writer.write(row)
                }
                fileRow["model_ms_\(arm.rawValue)"] = run.modelMs
                fileRow["conflicts_\(arm.rawValue)"] = shown.conflicts
                fileRow["gaps_\(arm.rawValue)"] = shown.gaps
                fileRow["conflicts_filtered_\(arm.rawValue)"] = shownFiltered.conflicts
            }
            fileRow["wall_ms"] = Self.milliseconds(clock.now - fileStart)
            writer.write(fileRow)
        }
    }
}
