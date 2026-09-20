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
/// Phase 50 D-02: the frontmost-app pre-check does not apply here — a menu action has no
/// release instant to capture an expected bundle id against, so `expectedFrontmostBundleID`
/// is left nil, which means no pre-check blocks this call at all (quick 260920-9m8 D-1 also
/// dropped the secure-input check this comment used to name, which never applied here either).
/// Phase 50 plan 12 (CR-01): the default injector is the app's shared instance, so a revert
/// pressed inside a dictation's restore window queues behind it instead of saving that
/// dictation's transcript as the "previous clipboard"; both callers (`HomePane`'s button and
/// the `.revertToRaw` hotkey in `DicticusApp`) use this default.
@MainActor
func revertToRaw(history: HistoryService = .shared, injector: TextInjector = .shared) async {
    guard let last = history.entries.first, last.rawText != last.text else {
        return
    }
    let outcome = await injector.injectText(last.rawText)
    if case .fallbackToClipboard = outcome {
        NotificationService.shared.post(.pasteUndeliverable)
    }
}
