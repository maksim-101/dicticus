// MemoryProbe — on-device peak-memory instrument for the Phase 44 Qwen3.5-4B
// iOS feasibility measurement (44-14 Task 1).
//
// Reports two numbers per checkpoint:
//   - phys_footprint          — the byte count iOS's jetsam killer actually watches
//   - os_proc_available_memory — headroom remaining before that kill fires
//
// Their SUM is this device's effective per-app memory ceiling. That is the fact
// that makes a measurement on one device transferable to another: the footprint
// is a property of the app (roughly device-independent), while the ceiling is a
// property of the device. Measuring both separates them.
//
// Uses os.Logger rather than the DebugRecorder JSONL probes because those are
// gated on DEBUG_RECORDER, which is defined only in the macOS project. os_log
// streams off-device via `xcrun devicectl device console`.

import Foundation
import os

public actor MemoryProbe {

    public static let shared = MemoryProbe()

    private static let log = Logger(subsystem: "com.dicticus", category: "memprobe")

    private var peakFootprint: UInt64 = 0
    private var samplerTask: Task<Void, Never>?

    private init() {}

    /// OFF unless launched with `-memProbe 1`. The sampler polls at 100 ms and every
    /// mark appends to a file, so leaving this live in production would burn a timer
    /// forever and grow `memprobe.jsonl` without bound.
    public nonisolated static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "memProbe")
    }

    /// Current phys_footprint — the byte count iOS's jetsam killer watches.
    public nonisolated static func footprintBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return UInt64(info.phys_footprint)
    }

    /// Headroom remaining before jetsam terminates the app. iOS/iPadOS only.
    public nonisolated static func availableBytes() -> UInt64 {
        #if os(iOS)
        return UInt64(os_proc_available_memory())
        #else
        return 0
        #endif
    }

    /// Poll continuously so the true peak is caught wherever it lands — model
    /// load, ASR inference, and LLM inference each peak at different moments,
    /// and a checkpoint-only probe would sample the troughs between them.
    public func startSampling(intervalMs: UInt64 = 100) {
        guard Self.isEnabled, samplerTask == nil else { return }
        samplerTask = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                let sample = MemoryProbe.footprintBytes()
                await self?.observe(sample)
                try? await Task.sleep(nanoseconds: intervalMs * 1_000_000)
            }
        }
    }

    private func observe(_ sample: UInt64) {
        if sample > peakFootprint { peakFootprint = sample }
    }

    /// Emit a labelled checkpoint line.
    ///
    /// `note` carries free-form diagnostic state (e.g. the warmup gating decision),
    /// so a stuck launch is readable from the same artifact as the memory numbers.
    public func mark(_ stage: String, model: String = "-", note: String = "") {
        guard Self.isEnabled else { return }

        let now = MemoryProbe.footprintBytes()
        if now > peakFootprint { peakFootprint = now }
        let available = MemoryProbe.availableBytes()
        let peak = peakFootprint

        Self.log.info("""
            MEMPROBE stage=\(stage, privacy: .public) \
            model=\(model, privacy: .public) \
            footprint_mb=\(now / 1_048_576, privacy: .public) \
            peak_mb=\(peak / 1_048_576, privacy: .public) \
            avail_mb=\(available / 1_048_576, privacy: .public) \
            ceiling_mb=\((now + available) / 1_048_576, privacy: .public) \
            note=\(note, privacy: .public)
            """)

        append([
            "ts": Self.iso8601Timestamp(),
            "stage": stage,
            "model": model,
            "footprint_mb": now / 1_048_576,
            "peak_mb": peak / 1_048_576,
            "avail_mb": available / 1_048_576,
            "ceiling_mb": (now + available) / 1_048_576,
            "note": note
        ])
    }

    // MARK: - JSONL sink
    //
    // os_log cannot be streamed off a physical device from this macOS (`log stream`
    // has no remote-device flag, and devicectl exposes no console subcommand), so
    // the durable artifact is a file in Documents, pulled via `devicectl device copy from`.

    private func append(_ obj: [String: Any]) {
        guard let documents = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first else { return }

        let url = documents.appendingPathComponent("memprobe.jsonl")
        guard var data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) else { return }
        data.append(0x0A)

        if FileManager.default.fileExists(atPath: url.path) {
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }

    private nonisolated static func iso8601Timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
