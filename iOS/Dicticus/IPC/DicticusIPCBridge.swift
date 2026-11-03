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
        /// [String] (UUID list): pending transcripts whose PLAIN text already went to the clipboard
        /// while AI cleanup was on and the LLM not yet loaded. Keeps repeated foregrounds from
        /// rewriting the clipboard; cleared wherever the pending list is cleared. App Group
        /// defaults, because the LLM-ready retry can run in a later process.
        static let deliveredPlainTranscriptUUIDs = "deliveredPlainTranscriptUUIDs"
        /// Int: `UIPasteboard.general.changeCount` read immediately after that plain write. The
        /// cleaned text may replace Dicticus's own plain write only while the count is unchanged.
        static let deliveredPlainClipboardChangeCount = "deliveredPlainClipboardChangeCount"
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
