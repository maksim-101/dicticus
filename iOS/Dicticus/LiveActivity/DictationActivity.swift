import ActivityKit
import Foundation

struct DictationAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var isRecording: Bool
        var startedAt: Date
    }

    /// Upper bound for the Live Activity's elapsed-time display. Mirrors
    /// `DictationViewModel.capFinalizeSeconds` (5:00 hard auto-finalize cap) —
    /// a dictation session can never run longer than this, so the Dynamic
    /// Island/lock-screen timer never needs to reserve layout width for
    /// anything beyond "4:59". Bounding `Text(timerInterval:)` to this instead
    /// of `Date.distantFuture` keeps the compact/minimal presentations sized
    /// like a native Live Activity instead of reserving space defensively for
    /// an unbounded duration. See 46-LIVEACTIVITY-REDESIGN.md for the measured
    /// before/after and the two files' coupling.
    static let maxDictationSeconds: TimeInterval = 300
}
