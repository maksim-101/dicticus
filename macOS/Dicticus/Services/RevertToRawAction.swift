import Foundation

/// Pure decision seam for the "Revert to Raw" safety valve (R-06).
///
/// Kept free of HistoryService/TextInjector dependencies so the enabled/disabled
/// + tooltip logic is directly unit-testable (see RevertToRawTests.swift).
enum RevertToRawState {
    static let noHistoryHelp = "No dictation yet to revert."
    static let nothingToRevertHelp = "Nothing to revert — raw and cleaned text match."

    /// Evaluate whether the revert action should be enabled for a given history entry,
    /// and which tooltip/accessibility copy applies.
    static func evaluate(entry: TranscriptionEntry?) -> (enabled: Bool, help: String) {
        guard let entry else {
            return (false, noHistoryHelp)
        }
        guard entry.rawText != entry.text else {
            return (false, nothingToRevertHelp)
        }
        return (true, "")
    }
}

/// Re-pastes the raw ASR text of the most recent dictation via the existing
/// TextInjector (clipboard save -> write -> Cmd+V -> restore) — the user-side
/// safety valve for the braver AI-cleanup prompt (R-06 / CLEANRD-02).
///
/// Silent no-op when there is nothing to revert (D-16 precedent: no notification
/// for a no-op). Accessibility-missing failure is already surfaced by
/// TextInjector.injectText via the existing transcriptionFailed notification.
@MainActor
func revertToRaw(history: HistoryService = .shared, injector: TextInjector = TextInjector()) async {
    guard let last = history.entries.first, last.rawText != last.text else {
        return
    }
    await injector.injectText(last.rawText)
}
