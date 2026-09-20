import UserNotifications
import os

private let notificationLog = Logger(subsystem: "com.dicticus", category: "notifications")

/// Notification types for user-facing error states.
///
/// Per D-15: macOS notification for real errors.
/// Per D-16: No notification for silence-only recordings.
/// Per D-10: No audio feedback — silent operation.
/// Per UI-SPEC Notification States table: exact wording specified.
enum DicticusNotification {
    /// D-19: Hotkey pressed while already transcribing
    case busy
    /// D-17: Hotkey pressed before model warm-up completes
    case modelLoading
    /// D-15: Transcription pipeline returned an error
    case transcriptionFailed(Error)
    /// Recording could not start (mic unavailable, permission denied)
    case recordingFailed(Error)
    /// ASR output contained non-Latin script (Cyrillic, CJK, Arabic, etc.)
    case unexpectedLanguage
    /// D-19: LLM cleanup failed — raw ASR text was pasted as fallback
    case cleanupFailed
    /// Phase 44 Plan 14: utterance too long for AI cleanup — inserted without cleanup (honest
    /// fallback, replaces a silent skip). The output-budget guard fired.
    case cleanupSkippedTooLong
    /// Phase 44 Plan 14: AI cleanup exceeded its time budget — inserted without cleanup.
    case cleanupTimedOut
    /// D-20: AI cleanup hotkey pressed before LLM warmup completes
    case llmLoading
    /// Phase 50 D-02: paste delivery pre-check failed — the transcript is on the clipboard as a
    /// real copy.
    case pasteUndeliverable
    /// Quick 260920-9m8 D-3: pre-check failed and the clipboard fallback setting is off — the
    /// pasteboard was not touched; the transcript is in history and the popover's last transcript.
    case pasteUndeliverableClipboardUntouched

    /// Notification title — always "Dicticus" per UI-SPEC copywriting contract.
    var title: String { "Dicticus" }

    /// Notification body — problem statement + action hint, under 80 characters.
    /// Exact wording per UI-SPEC copywriting contract.
    var message: String {
        switch self {
        case .busy:
            return "Still processing \u{2014} try again in a moment."
        case .modelLoading:
            return "Models still loading, please wait a moment."
        case .transcriptionFailed:
            // Singular "model" (one ASR model on macOS) and points at the menu bar dropdown's
            // WarmupRow, the one place the user can actually check model status — quick task
            // 260831-nt6. This case now only fires for genuine failures (model not ready,
            // recording-state errors, AVFoundation/WhisperKit throws); .noResult (no speech
            // captured) was misrouted here and is now silent — see TranscriptionFailureRouter.
            return "Transcription failed \u{2014} check model status in the menu bar."
        case .recordingFailed:
            return "Could not start recording. Check microphone permission."
        case .unexpectedLanguage:
            return "Unexpected language detected. Please try again."
        case .cleanupFailed:
            return "AI cleanup failed. Raw text was pasted instead."
        case .cleanupSkippedTooLong:
            return "Text too long for AI cleanup \u{2014} inserted without it."
        case .cleanupTimedOut:
            return "AI cleanup timed out \u{2014} inserted without it."
        case .llmLoading:
            return "AI model still loading, please wait a moment."
        case .pasteUndeliverable:
            return "Couldn't paste \u{2014} text is on your clipboard, \u{2318}V to paste."
        case .pasteUndeliverableClipboardUntouched:
            return "Couldn't paste \u{2014} open Dicticus to copy the transcript."
        }
    }

    /// Bare case identifier for logging (T-50-09-01) — never the payload. The two
    /// payload-carrying cases (`transcriptionFailed`, `recordingFailed`) never interpolate
    /// their `Error`; a log reader gets the case name only.
    var caseName: String {
        switch self {
        case .busy: return "busy"
        case .modelLoading: return "modelLoading"
        case .transcriptionFailed: return "transcriptionFailed"
        case .recordingFailed: return "recordingFailed"
        case .unexpectedLanguage: return "unexpectedLanguage"
        case .cleanupFailed: return "cleanupFailed"
        case .cleanupSkippedTooLong: return "cleanupSkippedTooLong"
        case .cleanupTimedOut: return "cleanupTimedOut"
        case .llmLoading: return "llmLoading"
        case .pasteUndeliverable: return "pasteUndeliverable"
        case .pasteUndeliverableClipboardUntouched: return "pasteUndeliverableClipboardUntouched"
        }
    }
}

/// Thin wrapper around UNUserNotificationCenter for posting error notifications.
///
/// Authorization is requested once from `HotkeyManager.setup` and its result logged under the
/// `notifications` category (`50-GATE-DIFF.md` §7). Notification Center delivery is subject to
/// the user's Focus/Do Not Disturb, which the app cannot observe, so `unreadNotice` (menu-bar
/// icon + popover notice row) is the guaranteed surface, independent of authorization/DND state.
///
/// @MainActor ensures Swift 6 concurrency safety for the singleton pattern.
/// All call sites (HotkeyManager, app lifecycle) are already on @MainActor.
@MainActor
class NotificationService: ObservableObject {
    static let shared = NotificationService()

    /// D-02 gap: the in-app notice surface. Set as the first statement of `post(_:)` so every
    /// existing call site gets it without edits. Cleared on read (`HomePane.onDisappear`) and
    /// superseded at the top of `HotkeyManager.handleKeyDown` before the next press's own post.
    @Published var unreadNotice: DicticusNotification?

    /// Latest authorization status, refreshed after each `setup()` authorization round-trip.
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    /// Internal (not `private`) so tests can construct their own instance (D-18) — `.shared`
    /// stays the production singleton.
    init() {}

    private static func statusName(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "notDetermined"
        case .denied: return "denied"
        case .authorized: return "authorized"
        case .provisional: return "provisional"
        case .ephemeral: return "ephemeral"
        @unknown default: return "unknown(\(status.rawValue))"
        }
    }

    /// Request notification authorization on first use and log the full round-trip — the
    /// result used to be discarded (50-VERIFICATION.md Anti-Patterns row 1).
    func setup() {
        let center = UNUserNotificationCenter.current()
        Task { @MainActor in
            let before = await center.notificationSettings()
            var granted = false
            var errorText = "nil"
            do {
                granted = try await center.requestAuthorization(options: [.alert])
            } catch {
                errorText = String(describing: error)
            }
            let after = await center.notificationSettings()
            self.authorizationStatus = after.authorizationStatus
            notificationLog.notice("""
                authorization before=\(Self.statusName(before.authorizationStatus), privacy: .public) \
                granted=\(granted, privacy: .public) \
                error=\(errorText, privacy: .public) \
                after=\(Self.statusName(after.authorizationStatus), privacy: .public) \
                alertStyle=\(after.alertStyle.rawValue, privacy: .public)
                """)
        }
    }

    /// Post a notification to the user.
    ///
    /// Delivered immediately via UNNotificationRequest with nil trigger.
    /// Identifier is unique per request to prevent deduplication.
    func post(_ notification: DicticusNotification) {
        unreadNotice = notification

        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.message

        let name = notification.caseName
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil  // Deliver immediately
        )
        UNUserNotificationCenter.current().add(request) { error in
            notificationLog.notice("""
                post case=\(name, privacy: .public) \
                add_error=\(String(describing: error), privacy: .public)
                """)
        }
    }
}
