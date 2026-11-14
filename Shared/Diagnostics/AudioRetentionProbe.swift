// AudioRetentionProbe — slice 60: keeps the audio of each dictation for seven days so a
// transcript the owner doubts can be re-transcribed and compared with what was said.
//
// COMPILED OUT unless built with `-D DEBUG_RECORDER` (same gate as DebugRecorder and the
// other probes). Never present in the public Release / GitHub artifact. The audio stays on
// this Mac, under the DebugRecordings folder (the test override of slice 53 redirects it).
//
// Output: <DebugRecordings>/audio/<ISO8601 timestamp>.wav (16 kHz mono PCM16, the buffer
// handed to Whisper). Retention: 7 days, purged once per launch. The cleanup record names
// the file in `audio_file`.

#if DEBUG_RECORDER

import Foundation

public actor AudioRetentionProbe {

    public static let shared = AudioRetentionProbe()

    public static let retentionDays = 7

    nonisolated let directoryURL: URL
    private var hasPurgedThisLaunch = false

    private init() {
        self.directoryURL = DebugRecorder.recordingsDirectory().appendingPathComponent("audio", isDirectory: true)
    }

    /// Test-only: a probe writing into any folder.
    init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    /// Writes the dictation's 16 kHz samples as a WAV and returns the file name, or nil when the
    /// write failed.
    @discardableResult
    public func retain(samples16k: [Float], date: Date = Date()) -> String? {
        guard !samples16k.isEmpty else { return nil }
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        purgeIfNeeded(now: date)
        let name = DebugRecorder.iso8601Timestamp(date).replacingOccurrences(of: ":", with: "-") + ".wav"
        let url = directoryURL.appendingPathComponent(name)
        do {
            try Self.wavData(samples16k, sampleRate: 16_000).write(to: url, options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    /// 16-bit PCM mono WAV (RIFF) for the given samples.
    static func wavData(_ samples: [Float], sampleRate: UInt32) -> Data {
        let pcm = samples.map { f -> Int16 in
            let clamped = max(-1.0, min(1.0, f))
            return Int16(clamped * 32767.0)
        }
        let dataBytes = UInt32(pcm.count * 2)
        var d = Data(capacity: 44 + Int(dataBytes))
        func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        d.append("RIFF".data(using: .ascii)!); u32(36 + dataBytes); d.append("WAVE".data(using: .ascii)!)
        d.append("fmt ".data(using: .ascii)!); u32(16); u16(1); u16(1)
        u32(sampleRate); u32(sampleRate * 2); u16(2); u16(16)
        d.append("data".data(using: .ascii)!); u32(dataBytes)
        pcm.withUnsafeBufferPointer { d.append(Data(buffer: $0)) }
        return d
    }

    private func purgeIfNeeded(now: Date) {
        guard !hasPurgedThisLaunch else { return }
        hasPurgedThisLaunch = true
        purge(olderThan: now.addingTimeInterval(-Double(Self.retentionDays * 86_400)))
    }

    /// Removes every WAV whose modification date is before `cutoff`. Test-visible.
    func purge(olderThan cutoff: Date) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for entry in entries where entry.pathExtension == "wav" {
            if let mod = try? entry.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, mod < cutoff {
                try? fm.removeItem(at: entry)
            }
        }
    }
}

#endif
