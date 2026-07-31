import AppIntents
import Foundation

extension Notification.Name {
    static let stopDictation = Notification.Name("com.dicticus.stopDictation")
}

struct StopDictationIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Dictation"
    static let description = IntentDescription("Stop current dictation in Dicticus")

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .stopDictation, object: nil)
        return .result()
    }
}
