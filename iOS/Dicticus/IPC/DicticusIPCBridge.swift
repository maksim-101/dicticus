import Foundation

/// The shared App Group UserDefaults suite and the keys the app, DictateIntent and
/// the dictation view model read and write: recording flag and start time for the
/// Action-Button toggle-to-stop, and the pending-transcript UUIDs persisted while
/// backgrounded. There is no keyboard extension and no Darwin notification traffic.
enum DicticusIPCBridge {

    // MARK: - App Group

    static let appGroupID = "group.com.dicticus"

    // MARK: - UserDefaults Keys

    enum Key {
        /// String (UUID): UUID of the most-recent History entry persisted while backgrounded.
        /// Set by `stopDictation()` on the background path; cleared by `deliverPendingTranscriptsIfNeeded()`.
        /// The UUID identifies the most-recent pending transcript for foreground delivery (D-02/D-05).
        /// DEPRECATED in favour of pendingTranscriptUUIDs (list). Kept for legacy migration only.
        static let pendingTranscriptUUID = "pendingTranscriptUUID"
        /// [String] (UUID list): ordered list of pending transcript UUIDs persisted while backgrounded.
        /// Background stops APPEND to this list; foreground delivery reads the full batch and clears it.
        /// Older entries toward index 0; newest toward the end (append order = session order).
        /// Legacy single-key `pendingTranscriptUUID` is migrated to a one-element list on first read.
        static let pendingTranscriptUUIDs = "pendingTranscriptUUIDs"
        /// Bool: true while a recording session is active. Written by DictationViewModel.state didSet.
        /// Read by DictateIntent.perform() to implement Action-Button toggle-to-stop (D-01a).
        static let isRecording = "isRecording"
        /// TimeInterval (epoch): timestamp when the current/last recording was started.
        /// Persisted to App Group so a freshly-launched process can detect a stale cap and finalize.
        static let recordingStartedAt = "recordingStartedAt"
    }

    // MARK: - Shared UserDefaults Accessor

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }
}
