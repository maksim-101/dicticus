// PreviewFlagRecorder — "Flag last preview" capture (quick 261016-nx0, spike 019 fallback).
//
// Unlike OverlayProbe this file DOES store audio and dictated text (published previews,
// final ASR text, pasted text). It stays on this Mac and is written only when the user
// presses "Flag last preview" in the popover.
//
// Keeps only the most recent hold in memory; each new overlay show replaces it.
//
// COMPILED OUT unless built with `-D DEBUG_RECORDER`.
//
// Output: ~/Library/Application Support/Dicticus/DebugRecordings/preview-flags/
//   flag-<yyyyMMdd'T'HHmmss'Z'>.wav   (mono, 16 kHz, Float32)
//   flag-<yyyyMMdd'T'HHmmss'Z'>.json  (same stem; hold timeline)
// Retention: 14 days, purged once per launch at the first hold.

#if DEBUG_RECORDER

import Foundation
import AVFoundation

@MainActor
final class PreviewFlagRecorder: ObservableObject {

    static let shared: PreviewFlagRecorder = {
        let fm = FileManager.default
        let appSupport = (try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support")
        return PreviewFlagRecorder(directoryURL: appSupport
            .appendingPathComponent("Dicticus", isDirectory: true)
            .appendingPathComponent("DebugRecordings", isDirectory: true)
            .appendingPathComponent("preview-flags", isDirectory: true))
    }()

    nonisolated static let retentionDays = 14

    @Published private(set) var canFlag = false

    enum Outcome: Equatable {
        case written(stem: String)
        case noHold
        case alreadyFlagged(stem: String)
        case failed(String)

        var message: String {
            switch self {
            case .written(let stem): return "Saved \(stem)"
            case .noHold: return "No preview hold to flag"
            case .alreadyFlagged(let stem): return "Already saved as \(stem)"
            case .failed(let reason): return "Could not save: \(reason)"
            }
        }
    }

    // MARK: - Hold state

    private struct Event: Sendable {
        let kind: String
        let offsetMs: Double
        let text: String?
        let settled: String
        let tentative: String
    }

    private struct Hold {
        let generation: Int
        let seq: Int
        let bundleID: String?
        let startInstant: ContinuousClock.Instant
        let startDate: Date
        var events: [Event] = []
        var releaseMs: Double?
        var samples: [Float]?
        var inputSampleRate: Double = 0
        var finalText: String?
        var finalLanguage: String?
        var pastedText: String?
        var flaggedStem: String?
    }

    private struct Snapshot: Sendable {
        let stem: String
        let flaggedAt: Date
        let holdStartedAt: Date
        let seq: Int
        let bundleID: String?
        let events: [Event]
        let releaseMs: Double?
        let samples: [Float]
        let inputSampleRate: Double
        let finalText: String?
        let finalLanguage: String?
        let finalTextDictionary: String?
        let pastedText: String?
        let gitCommit: String?
        let appVersion: String?
    }

    private let directoryURL: URL
    private var hold: Hold?
    private var generation = 0
    private var hasPurgedThisLaunch = false

    init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    private func ms(since hold: Hold) -> Double {
        OverlayProbe.milliseconds(ContinuousClock.now - hold.startInstant)
    }

    func beginHold(seq: Int, bundleID: String?) {
        generation += 1
        hold = Hold(generation: generation, seq: seq, bundleID: bundleID,
                    startInstant: ContinuousClock.now, startDate: Date())
        canFlag = false
        if !hasPurgedThisLaunch {
            hasPurgedThisLaunch = true
            let dir = directoryURL
            Task.detached(priority: .utility) { Self.purgeExpired(in: dir) }
        }
    }

    func notePublish(seq: Int, text: String, settled: String, tentative: String) {
        guard let h = hold, h.seq == seq, h.releaseMs == nil else { return }
        hold?.events.append(Event(kind: "publish", offsetMs: ms(since: h), text: text,
                                  settled: settled, tentative: tentative))
    }

    func noteSettle(seq: Int, settled: String, tentative: String) {
        guard let h = hold, h.seq == seq, h.releaseMs == nil else { return }
        hold?.events.append(Event(kind: "settle", offsetMs: ms(since: h), text: nil,
                                  settled: settled, tentative: tentative))
    }

    func noteRelease(seq: Int) {
        guard let h = hold, h.seq == seq, h.releaseMs == nil else { return }
        hold?.releaseMs = ms(since: h)
    }

    func noteSamples(_ samples: [Float], inputSampleRate: Double) {
        guard let h = hold, h.releaseMs != nil, h.samples == nil, !samples.isEmpty else { return }
        hold?.samples = samples
        hold?.inputSampleRate = inputSampleRate
        canFlag = true
    }

    func noteFinal(text: String, language: String) {
        guard let h = hold, h.samples != nil, h.finalText == nil else { return }
        hold?.finalText = text
        hold?.finalLanguage = language
    }

    func notePasted(seq: Int, text: String) {
        guard let h = hold, h.seq == seq, h.samples != nil, h.pastedText == nil else { return }
        hold?.pastedText = text
    }

    // MARK: - Flag

    func flag() async -> Outcome {
        guard let h = hold, let samples = h.samples, !samples.isEmpty else { return .noHold }
        if let stem = h.flaggedStem { return .alreadyFlagged(stem: stem) }

        let now = Date()
        let stem = "flag-" + Self.stemFormatter().string(from: now)
        let info = Bundle.main.infoDictionary
        let version: String? = {
            guard let short = info?["CFBundleShortVersionString"] as? String,
                  let build = info?["CFBundleVersion"] as? String else { return nil }
            return "\(short) (\(build))"
        }()
        let snapshot = Snapshot(
            stem: stem, flaggedAt: now, holdStartedAt: h.startDate, seq: h.seq, bundleID: h.bundleID,
            events: h.events, releaseMs: h.releaseMs, samples: samples, inputSampleRate: h.inputSampleRate,
            finalText: h.finalText, finalLanguage: h.finalLanguage,
            finalTextDictionary: h.finalText.map { DictionaryService.shared.apply(to: $0) },
            pastedText: h.pastedText,
            gitCommit: info?["GitCommit"] as? String, appVersion: version)

        hold?.flaggedStem = stem
        canFlag = false

        let dir = directoryURL
        let result = await Task.detached(priority: .userInitiated) {
            Self.writeFiles(snapshot, in: dir)
        }.value

        switch result {
        case .success:
            return .written(stem: stem)
        case .failure(let error):
            if hold?.generation == h.generation {
                hold?.flaggedStem = nil
                canFlag = true
            }
            return .failed(error.localizedDescription)
        }
    }

    private nonisolated static func stemFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return f
    }

    private nonisolated static func iso8601(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    private nonisolated static func writeFiles(_ s: Snapshot, in dir: URL) -> Result<Void, Error> {
        let fm = FileManager.default
        let wavURL = dir.appendingPathComponent(s.stem + ".wav")
        let jsonURL = dir.appendingPathComponent(s.stem + ".json")
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            if fm.fileExists(atPath: wavURL.path) {
                throw CocoaError(.fileWriteFileExists)
            }

            let target = 16_000.0
            let out = abs(s.inputSampleRate - target) > 1.0
                ? TranscriptionService.resampleAudio(s.samples, from: s.inputSampleRate, to: target)
                : s.samples

            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: target,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false
            ]
            do {
                let file = try AVAudioFile(forWriting: wavURL, settings: settings,
                                           commonFormat: .pcmFormatFloat32, interleaved: false)
                guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                    frameCapacity: AVAudioFrameCount(out.count)),
                      let channel = buffer.floatChannelData?[0] else {
                    throw CocoaError(.fileWriteUnknown)
                }
                buffer.frameLength = AVAudioFrameCount(out.count)
                out.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: out.count) }
                try file.write(from: buffer)
                file.close()
            }

            func opt(_ v: String?) -> Any { v ?? NSNull() }
            let events: [[String: Any]] = s.events.map { e in
                var d: [String: Any] = [
                    "kind": e.kind, "offset_ms": e.offsetMs,
                    "settled": e.settled, "tentative": e.tentative
                ]
                if let t = e.text { d["text"] = t }
                return d
            }
            let obj: [String: Any] = [
                "schema": 1,
                "flagged_at": iso8601(s.flaggedAt),
                "hold_started_at": iso8601(s.holdStartedAt),
                "overlay_seq": s.seq,
                "bundle_id": opt(s.bundleID),
                "wav": s.stem + ".wav",
                "sample_rate": Int(target),
                "n_samples": out.count,
                "input_sample_rate": s.inputSampleRate,
                "release_ms": s.releaseMs ?? NSNull(),
                "events": events,
                "final_text": opt(s.finalText),
                "final_language": opt(s.finalLanguage),
                "final_text_dictionary": opt(s.finalTextDictionary),
                "pasted_text": opt(s.pastedText),
                "git_commit": opt(s.gitCommit),
                "app_version": opt(s.appVersion)
            ]
            do {
                let data = try JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .prettyPrinted])
                try data.write(to: jsonURL, options: .atomic)
            } catch {
                try? fm.removeItem(at: wavURL)
                throw error
            }
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Retention

    nonisolated static func purgeExpired(in directory: URL, now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-Double(retentionDays) * 86_400)
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        for entry in entries where entry.lastPathComponent.hasPrefix("flag-") {
            if let mod = try? entry.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
               mod < cutoff {
                try? fm.removeItem(at: entry)
            }
        }
    }
}

#endif
