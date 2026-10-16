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

    init(directoryURL: URL) {}

    func beginHold(seq: Int, bundleID: String?) {}
    func notePublish(seq: Int, text: String, settled: String, tentative: String) {}
    func noteSettle(seq: Int, settled: String, tentative: String) {}
    func noteRelease(seq: Int) {}
    func noteSamples(_ samples: [Float], inputSampleRate: Double) {}
    func noteFinal(text: String, language: String) {}
    func notePasted(seq: Int, text: String) {}

    func flag() async -> Outcome { .noHold }

    nonisolated static func purgeExpired(in directory: URL, now: Date = Date()) {}
}

#endif
