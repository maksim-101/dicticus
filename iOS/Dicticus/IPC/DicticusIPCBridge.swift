import Foundation
import os

/// Shared IPC constants and helpers for Darwin notification-based communication
/// between the Dicticus main app and the DicticusKeyboard extension.
///
/// This file is compiled into BOTH the Dicticus app target and the DicticusKeyboard extension target.
/// It defines all notification names, UserDefaults keys, state types, and read/write helpers.
///
/// Communication pattern: Darwin notifications carry NO payload — they are pure signals.
/// All data is exchanged via App Group UserDefaults.
enum DicticusIPCBridge {

    // MARK: - App Group

    static let appGroupID = "group.com.dicticus"

    // MARK: - UserDefaults Keys

    enum Key {
        /// String: "idle" / "waitingForApp" / "recording" / "transcribing"
        static let recordingState = "recordingState"
        /// TimeInterval (epoch): timestamp of last state change
        static let recordingStateTimestamp = "recordingState_timestamp"
        /// String: final transcription text
        static let latestTranscription = "latestTranscription"
        /// TimeInterval: heartbeat timestamp (1Hz, written by main app)
        static let sessionTimestamp = "session_timestamp"
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

    // MARK: - Darwin Notification Names

    enum Notification {
        // Keyboard -> App commands
        static let startRecording = "com.dicticus.startRecording"
        static let stopRecording = "com.dicticus.stopRecording"
        static let cancelRecording = "com.dicticus.cancelRecording"

        // App -> Keyboard state updates
        static let recordingStarted = "com.dicticus.recordingStarted"
        static let transcribingStarted = "com.dicticus.transcribingStarted"
        static let transcriptionReady = "com.dicticus.transcriptionReady"
        static let noSpeech = "com.dicticus.noSpeech"
    }

    // MARK: - Recording State

    enum RecordingState: String {
        case idle
        case waitingForApp
        case recording
        case transcribing
    }

    // MARK: - Shared UserDefaults Accessor

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    // MARK: - State Read/Write

    static func setRecordingState(_ state: RecordingState) {
        defaults?.set(state.rawValue, forKey: Key.recordingState)
        defaults?.set(Date().timeIntervalSince1970, forKey: Key.recordingStateTimestamp)
    }

    static func currentRecordingState() -> RecordingState {
        guard let raw = defaults?.string(forKey: Key.recordingState),
              let state = RecordingState(rawValue: raw) else { return .idle }
        return state
    }

    static func currentRecordingStateAge() -> TimeInterval? {
        let ts = defaults?.double(forKey: Key.recordingStateTimestamp) ?? 0
        guard ts > 0 else { return nil }
        return Date().timeIntervalSince1970 - ts
    }

    // MARK: - Transcription Read/Write

    static func setTranscription(_ text: String) {
        defaults?.set(text, forKey: Key.latestTranscription)
    }

    static func latestTranscription() -> String? {
        defaults?.string(forKey: Key.latestTranscription)
    }

    // MARK: - Heartbeat (1Hz, rate-limited)

    /// Session is considered "warm" if heartbeat is less than this many seconds old.
    static let heartbeatFreshnessWindow: TimeInterval = 5

    private static let heartbeatLock = OSAllocatedUnfairLock(initialState: TimeInterval(0))

    /// Returns true if the main app's heartbeat timestamp is fresh (< 5 seconds old).
    static func isSessionWarm() -> Bool {
        let ts = defaults?.double(forKey: Key.sessionTimestamp) ?? 0
        guard ts > 0 else { return false }
        return Date().timeIntervalSince1970 - ts < heartbeatFreshnessWindow
    }

    /// Updates the heartbeat timestamp. Rate-limited to at most once per second.
    static func touchHeartbeat() {
        let now = Date().timeIntervalSince1970
        heartbeatLock.withLock { lastUpdate in
            guard now - lastUpdate >= 1.0 else { return }
            lastUpdate = now
            defaults?.set(now, forKey: Key.sessionTimestamp)
        }
    }

    // MARK: - Transient State Cleanup

    /// Clears transcription text and resets recording state to idle.
    /// Called on cancel, crash recovery, or stale state reconciliation.
    static func clearTransientOperationState() {
        defaults?.removeObject(forKey: Key.latestTranscription)
        setRecordingState(.idle)
    }

    // MARK: - Darwin Notification Post Helper

    /// Posts a Darwin notification with the given name.
    /// Darwin notifications are system-level IPC signals that carry no payload.
    static func postDarwinNotification(named name: String) {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(center, CFNotificationName(name as CFString), nil, nil, true)
    }
}
