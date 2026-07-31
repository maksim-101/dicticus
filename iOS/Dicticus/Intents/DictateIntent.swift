import AppIntents
import Foundation

extension Notification.Name {
    static let startDictation = Notification.Name("com.dicticus.startDictation")
}

struct DictateIntent: AudioRecordingIntent {
    static let title: LocalizedStringResource = "Start Dictation"
    static let description = IntentDescription("Begin dictating in Dicticus")

    @available(*, deprecated)
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        // Action-Button toggle-to-stop (D-01a): if already recording, this
        // press stops; otherwise it starts. The isRecording flag is written by
        // DictationViewModel on every state change via App Group defaults.
        // Note: the stop branch still brings the app forward (AudioRecordingIntent
        // openAppWhenRun:true) — the lock-screen Live Activity Stop is the true
        // no-reopen stop surface.
        let isRecording = DicticusIPCBridge.defaults?.bool(forKey: "isRecording") ?? false
        if isRecording {
            NotificationCenter.default.post(name: .stopDictation, object: nil)
        } else {
            DicticusIPCBridge.defaults?.set(true, forKey: "pendingDictation")
            DicticusIPCBridge.defaults?.set(true, forKey: "isShortcutLaunch")
            NotificationCenter.default.post(name: .startDictation, object: nil)
        }
        return .result()
    }
}
