import XCTest
import AVFoundation
@testable import Dicticus

/// Live-preview replay harness (Phase 51, spike 018).
///
/// A measurement tool in the style of `AsrReplayHarnessTests`: opt-in, model required,
/// skips without `DICTICUS_REPLAY_DIR`. It drives the shipping `LivePreviewDecoder`,
/// `LivePreviewSession` and the shared release path, and records counts and timings
/// only. No preview or final text is ever written to the output.
///
///     DICTICUS_REPLAY_DIR="$HOME/Library/Application Support/Dicticus/ReplayCorpus" \
///     TEST_RUNNER_DICTICUS_REPLAY_DIR="$DICTICUS_REPLAY_DIR" \
///     nice -n 10 xcodebuild test -only-testing:DicticusTests/LivePreviewLatencySpikeTests
final class LivePreviewLatencySpikeTests: XCTestCase {

    /// Live capture runs at the hardware rate (48 kHz in the discard logs).
    private static let captureRate: Double = 48000
    private static let smokeSeconds: Double = 8
    private static let chunkFrames = 4096

    private final class Recorder: @unchecked Sendable {
        var publishedCounts: [Int] = []
    }

    @MainActor
    func testSmoke_previewThenRelease() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let replayDir = env["DICTICUS_REPLAY_DIR"] else {
            throw XCTSkip("Set DICTICUS_REPLAY_DIR to run the live-preview smoke test.")
        }
        guard TranscriptionService.isWhisperKitAvailable() else {
            throw XCTSkip("WhisperKit model not cached — cannot decode.")
        }
        guard let service = try await TranscriptionService.makeForTesting() else {
            throw XCTSkip("Could not construct TranscriptionService.")
        }

        let wavs = try FileManager.default
            .contentsOfDirectory(at: URL(fileURLWithPath: replayDir), includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "wav" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var picked: (name: String, samples: [Float], rate: Double)?
        for wav in wavs {
            guard let (samples, rate) = AsrReplayHarnessTests.readWav(wav),
                  Double(samples.count) / rate >= Self.smokeSeconds else { continue }
            picked = (wav.lastPathComponent, samples, rate)
            break
        }
        guard let clip = picked else {
            throw XCTSkip("No capture of at least \(Int(Self.smokeSeconds)) s in \(replayDir).")
        }

        let head = Array(clip.samples.prefix(Int(Self.smokeSeconds * clip.rate)))
        let live = abs(clip.rate - Self.captureRate) > 1
            ? TranscriptionService.resampleAudio(head, from: clip.rate, to: Self.captureRate)
            : head

        let buffer = AudioSampleBuffer()
        let decoder = service.testMakeLivePreviewDecoder(buffer: buffer, inputSampleRate: Self.captureRate)
        let recorder = Recorder()
        let session = LivePreviewSession(
            cadence: LivePreviewSession.productionCadence,
            isActive: { true },
            decode: { await decoder.decodeTail() },
            publish: { recorder.publishedCounts.append($0.count) }
        )
        session.start()

        let chunkDelay = Duration.seconds(Double(Self.chunkFrames) / Self.captureRate)
        var offset = 0
        while offset < live.count {
            let end = min(offset + Self.chunkFrames, live.count)
            buffer.append(Array(live[offset..<end]))
            offset = end
            try await Task.sleep(for: chunkDelay)
        }

        let clock = ContinuousClock()
        let releasedAt = clock.now
        let out = try await service.testReleaseAndTranscribe(
            previewSession: session,
            samples: buffer.drain(),
            inputSampleRate: Self.captureRate
        )
        let releaseToFinal = clock.now - releasedAt

        let stats = try XCTUnwrap(out.stats)
        XCTAssertGreaterThanOrEqual(recorder.publishedCounts.count, 1, "no preview was published")
        XCTAssertTrue(recorder.publishedCounts.allSatisfy { $0 > 0 }, "an empty preview was published")
        XCTAssertGreaterThanOrEqual(stats.ticks, 1, "the session never ticked")
        XCTAssertFalse(out.result.text.isEmpty, "the final decode returned no text")

        let row: [String: Any] = [
            "file": clip.name,
            "duration": Double(live.count) / Self.captureRate,
            "ticks": stats.ticks,
            "published": stats.published,
            "published_chars": recorder.publishedCounts,
            "cancelled_in_flight": stats.cancelledInFlight,
            "drain_ms": Self.milliseconds(stats.drainDuration),
            "release_to_final_ms": Self.milliseconds(releaseToFinal),
            "decode_ms": stats.decodeDurations.map(Self.milliseconds),
            "final_chars": out.result.text.count
        ]
        let outPath = env["DICTICUS_REPLAY_OUT"]
            ?? NSTemporaryDirectory().appending("live-preview-smoke.jsonl")
        let data = try JSONSerialization.data(withJSONObject: row) + Data("\n".utf8)
        FileManager.default.createFile(atPath: outPath, contents: data)
        print("Live-preview smoke wrote 1 row to \(outPath)")
    }

    // MARK: - Spike 018 (plan 51-02): rung, latency sweep, aiCleanup arm
    //
    // Each method reads one JSON config named by DICTICUS_SPIKE_CONFIG (keys: replay_dir,
    // file_list, cadence_ms, seed, out, rows_tag) and skips without it. Rows carry file
    // names, durations, counts and timings only; no dictated text is ever stored.

    private struct SplitMix64: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }

    private struct SpikeConfig {
        let replayDir: String
        let files: [String]
        let cadenceMs: Int
        let seed: UInt64
        let out: String
        let rowsTag: String
    }

    private static func loadConfig() throws -> SpikeConfig {
        guard let path = ProcessInfo.processInfo.environment["DICTICUS_SPIKE_CONFIG"] else {
            throw XCTSkip("Set DICTICUS_SPIKE_CONFIG to run spike 018.")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let listPath = try XCTUnwrap(json["file_list"] as? String)
        let files = try String(contentsOfFile: listPath, encoding: .utf8)
            .split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        return SpikeConfig(
            replayDir: try XCTUnwrap(json["replay_dir"] as? String),
            files: files,
            cadenceMs: (json["cadence_ms"] as? Int) ?? 500,
            seed: UInt64((json["seed"] as? Int) ?? 51),
            out: try XCTUnwrap(json["out"] as? String),
            rowsTag: (json["rows_tag"] as? String) ?? "rung"
        )
    }

    private static func now() -> String {
        Date().formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
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

    /// Per-tick WhisperKit and filter timings, taken from the decoder's `lastTiming`
    /// after each tick; a snapshot identical to the previous one means the tick returned
    /// before reaching the decode and is not counted.
    @MainActor
    private final class TickLog {
        var decodeMs: [Double] = []
        var filterMs: [Double] = []
        private var last: LivePreviewDecoder.Timing?

        func note(_ t: LivePreviewDecoder.Timing?) {
            guard let t else { return }
            if let l = last, l.snapshotMs == t.snapshotMs, l.resampleMs == t.resampleMs,
               l.decodeMs == t.decodeMs, l.filterMs == t.filterMs { return }
            last = t
            decodeMs.append(t.decodeMs)
            filterMs.append(t.filterMs)
        }
    }

    private struct Clip {
        let name: String
        let index: Int
        let live: [Float]
    }

    @MainActor
    private static func loadClip(_ name: String, index: Int, dir: String) throws -> Clip {
        let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
        guard let (samples, rate) = AsrReplayHarnessTests.readWav(url) else {
            throw XCTSkip("Unreadable WAV \(name).")
        }
        let live = abs(rate - captureRate) > 1
            ? TranscriptionService.resampleAudio(samples, from: rate, to: captureRate)
            : samples
        return Clip(name: name, index: index, live: live)
    }

    /// One release, fed and timed as pre-registered. `arm` is "A", "B" or "W" (warm-up).
    @MainActor
    private func runOne(
        arm: String, rep: Int, clip: Clip, config: SpikeConfig, tag: String,
        service: TranscriptionService, writer: RowWriter,
        warmup: (@MainActor () -> Bool)? = nil
    ) async throws {
        let clock = ContinuousClock()
        let live = clip.live
        let buffer = AudioSampleBuffer()
        let feedFrames = min(Int(4.0 * Self.captureRate), live.count)
        let prefill = live.count - feedFrames
        if prefill > 0 { buffer.append(Array(live[0..<prefill])) }

        let log = TickLog()
        var session: LivePreviewSession?
        var starter: Task<Void, Never>?
        if arm == "B" {
            let decoder = service.testMakeLivePreviewDecoder(buffer: buffer, inputSampleRate: Self.captureRate)
            let s = LivePreviewSession(
                cadence: .milliseconds(config.cadenceMs),
                isActive: { true },
                decode: {
                    let text = await decoder.decodeTail()
                    log.note(decoder.lastTiming)
                    return text
                },
                publish: { _ in }
            )
            session = s
            var rng = SplitMix64(state: config.seed &* 1_000_003 &+ UInt64(clip.index) &* 10 &+ UInt64(rep))
            let delay = Double.random(in: 0..<(Double(config.cadenceMs) / 1000), using: &rng)
            starter = Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))
                s.start()
            }
        }
        let warmupEligible = warmup?()

        let feedStart = clock.now
        let chunkSeconds = Double(Self.chunkFrames) / Self.captureRate
        var offset = prefill
        var k = 0
        while offset < live.count {
            let end = min(offset + Self.chunkFrames, live.count)
            buffer.append(Array(live[offset..<end]))
            offset = end
            k += 1
            try await Task.sleep(until: feedStart + .seconds(Double(k) * chunkSeconds), clock: clock)
        }

        await starter?.value
        let releasedAt = clock.now
        var ok = true
        var errorName = ""
        do {
            _ = try await service.testReleaseAndTranscribe(
                previewSession: session, samples: live, inputSampleRate: Self.captureRate)
        } catch {
            ok = false
            errorName = String(describing: type(of: error))
        }
        let doneAt = clock.now

        var row: [String: Any] = [
            "file": clip.name,
            "duration_s": Double(live.count) / Self.captureRate,
            "arm": arm,
            "rep": rep,
            "cadence_ms": config.cadenceMs,
            "tag": tag,
            "release_ms": Self.milliseconds(doneAt - releasedAt),
            "run_wall_ms": Self.milliseconds(doneAt - feedStart),
            "ok": ok,
            "error": errorName,
            "ts": Self.now()
        ]
        if let warmupEligible { row["warmup_eligible"] = warmupEligible }
        if session != nil, let stats = service.lastLivePreviewStats {
            row["drain_ms"] = Self.milliseconds(stats.drainDuration)
            row["in_flight_at_release"] = stats.cancelledInFlight
            row["ticks"] = stats.ticks
            row["published"] = stats.published
            row["publish_offsets_ms"] = stats.publishInstants.map { Self.milliseconds($0 - feedStart) }
            row["loop_ms"] = stats.decodeDurations.map(Self.milliseconds)
            row["decode_ms"] = log.decodeMs
            row["filter_ms"] = log.filterMs
        }
        writer.write(row)
    }

    @MainActor
    private func runLadderRung(config: SpikeConfig, tag: String, warmup: (@MainActor () -> Bool)?) async throws {
        guard TranscriptionService.isWhisperKitAvailable() else {
            throw XCTSkip("WhisperKit model not cached — cannot decode.")
        }
        guard let service = try await TranscriptionService.makeForTesting() else {
            throw XCTSkip("Could not construct TranscriptionService.")
        }
        let writer = try RowWriter(path: config.out)
        let first = try XCTUnwrap(config.files.first)
        let warm = try Self.loadClip(first, index: 0, dir: config.replayDir)
        try await runOne(arm: "W", rep: 0, clip: warm, config: config, tag: tag,
                         service: service, writer: writer)
        for (index, name) in config.files.enumerated() {
            let clip = try Self.loadClip(name, index: index, dir: config.replayDir)
            try await runOne(arm: "A", rep: 1, clip: clip, config: config, tag: tag, service: service, writer: writer, warmup: warmup)
            try await runOne(arm: "B", rep: 1, clip: clip, config: config, tag: tag, service: service, writer: writer, warmup: warmup)
            try await runOne(arm: "A", rep: 2, clip: clip, config: config, tag: tag, service: service, writer: writer, warmup: warmup)
            try await runOne(arm: "B", rep: 2, clip: clip, config: config, tag: tag, service: service, writer: writer, warmup: warmup)
        }
    }

    @MainActor
    func testSpikeRung() async throws {
        let config = try Self.loadConfig()
        try await runLadderRung(config: config, tag: config.rowsTag, warmup: nil)
    }

    @MainActor
    func testSpikeAiCleanupArm() async throws {
        let config = try Self.loadConfig()
        let modelPath = ModelDownloadService.modelPath().path
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw XCTSkip("Cleanup GGUF not present — aiCleanup arm is a named gap.")
        }
        let cleanup = CleanupService()
        try cleanup.loadModel(from: modelPath)
        try await runLadderRung(config: config, tag: "aicleanup", warmup: {
            let eligible = CleanupService.shouldWarmUp(
                lastInferenceAt: cleanup.lastInferenceAt, now: Date(),
                idleThreshold: CleanupService.warmUpIdleThreshold)
            cleanup.warmUp()
            return eligible
        })
    }

    @MainActor
    func testSpikeLatencySweep() async throws {
        let config = try Self.loadConfig()
        guard TranscriptionService.isWhisperKitAvailable() else {
            throw XCTSkip("WhisperKit model not cached — cannot decode.")
        }
        guard let service = try await TranscriptionService.makeForTesting() else {
            throw XCTSkip("Could not construct TranscriptionService.")
        }
        let writer = try RowWriter(path: config.out)
        let decoder = service.testMakeLivePreviewDecoder(buffer: AudioSampleBuffer(), inputSampleRate: 16000)
        var fallback = LivePreviewDecoder.decodeOptions
        fallback.temperatureFallbackCount = 5
        let clock = ContinuousClock()

        var clips: [(name: String, samples: [Float])] = []
        for name in config.files {
            guard clips.count < 10 else { break }
            let url = URL(fileURLWithPath: config.replayDir).appendingPathComponent(name)
            guard let (samples, rate) = AsrReplayHarnessTests.readWav(url), abs(rate - 16000) < 1,
                  Double(samples.count) / rate >= 30 else { continue }
            clips.append((name, samples))
        }
        try XCTSkipIf(clips.isEmpty, "No selected file of at least 30 s.")

        _ = try? await decoder.decodeResampled(Array(clips[0].samples.prefix(2 * 16000)),
                                               options: LivePreviewDecoder.decodeOptions)
        for clip in clips {
            for window in [2, 4, 8, 15, 28] {
                let slice = Array(clip.samples.prefix(window * 16000))
                for (label, options) in [("preview", LivePreviewDecoder.decodeOptions),
                                         ("preview", LivePreviewDecoder.decodeOptions),
                                         ("fallback5", fallback)] {
                    let began = clock.now
                    var ok = true
                    var tokens = 0
                    var fired = false
                    do {
                        let results = try await decoder.decodeResampled(slice, options: options)
                        tokens = results.reduce(0) { $0 + $1.segments.reduce(0) { $0 + $1.tokens.count } }
                        fired = results.contains { $0.segments.contains { $0.temperature > 0 } }
                    } catch {
                        ok = false
                    }
                    writer.write([
                        "file": clip.name,
                        "duration_s": Double(clip.samples.count) / 16000,
                        "window_s": window,
                        "options": label,
                        "ms": Self.milliseconds(clock.now - began),
                        "tokens": tokens,
                        "fallback_fired": fired,
                        "ok": ok,
                        "tag": config.rowsTag,
                        "ts": Self.now()
                    ])
                }
            }
        }
    }


    private static func milliseconds(_ d: Duration) -> Double {
        Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
    }
}
