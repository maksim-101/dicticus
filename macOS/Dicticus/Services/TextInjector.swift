import AppKit
import CoreGraphics
@preconcurrency import ApplicationServices
import Carbon.HIToolbox

/// Injects text at the current cursor position via clipboard save + write + Cmd+V + restore.
///
/// Pattern from VocaMac, Speak2, Maccy — proven cross-app method.
/// Requires Accessibility permission for CGEvent posting (already checked by PermissionManager).
///
/// Per D-06: Clipboard + Cmd+V paste strategy.
/// Per D-07: Original clipboard contents preserved after injection (~100ms delay).
/// Per D-08: Single Cmd+V code path for all apps including terminal emulators.
/// @MainActor isolation ensures all NSPasteboard and CGEvent calls happen on the main thread.
/// NSPasteboard.general and CGEvent.post are both main-thread-only AppKit/CoreGraphics APIs.
@MainActor
class TextInjector {

    /// Saved clipboard state — array of items, each with multiple type+data pairs.
    struct SavedClipboard {
        let items: [[(NSPasteboard.PasteboardType, Data)]]
    }

    /// Phase 50 D-02: which deterministic signal blocked delivery of the synthesized paste.
    /// Raw values are the exact `failure_signal` vocabulary logged by `PasteProbe` (D-05) — see
    /// `50-GATE-DIFF.md` §C. Backlog: `macos-paste-at-cursor-intermittent-failure.md` (text lands
    /// in history but never at the cursor) is the symptom this signal set diagnoses.
    enum DeliveryBlocker: String, Equatable {
        /// `IsSecureEventInputEnabled()` is true — macOS silently drops synthesized keystrokes
        /// while a password field / secure terminal input has focus.
        case secureInput = "secure_input"
        /// The frontmost app at paste time differs from the frontmost app at hotkey RELEASE
        /// (captured at key-up, not key-down, so a deliberate app switch during the hold is
        /// honoured and only a switch during the ASR/LLM wait is caught).
        case frontmostChanged = "frontmost_changed"
    }

    /// Phase 50 D-02: the outcome of one `injectText` call.
    enum Outcome: Equatable {
        /// The pre-check passed, Cmd+V was synthesized, and the prior clipboard was restored.
        case delivered
        /// The pre-check failed before any paste was attempted; the transcript is left on the
        /// general pasteboard as a real user copy (no trailing space, no restore — D-02).
        case fallbackToClipboard(DeliveryBlocker)
        /// Accessibility was untrusted, or the clipboard write itself failed; unchanged from the
        /// pre-Phase-50 behaviour (AX already notifies; a failed write restores the clipboard
        /// silently, so a `.pasteUndeliverable` notification there would be a lie).
        case blocked
    }

    /// Phase 50 D-02: pure eligibility predicate for the delivery pre-check. Secure input outranks
    /// a frontmost-app change when both hold (an even more certain OS-level drop). An unknown
    /// bundle id on either side is never evidence of a switch — `revertToRaw` passes `nil` for
    /// `expectedBundleID` and gets only the secure-input check.
    nonisolated static func deliveryBlocker(secureInputEnabled: Bool, expectedBundleID: String?, currentBundleID: String?) -> DeliveryBlocker? {
        if secureInputEnabled {
            return .secureInput
        }
        if let expectedBundleID, let currentBundleID, expectedBundleID != currentBundleID {
            return .frontmostChanged
        }
        return nil
    }

    /// Test seams (Phase 50 D-02/D-05) — `var` properties, not initializer parameters, because
    /// `TextInjector()` is constructed bare at `HotkeyManager.swift:99` and by `revertToRaw`'s
    /// default argument. Production defaults match today's behaviour exactly.
    var axTrustedProbe: () -> Bool = { AXIsProcessTrusted() }
    var secureInputProbe: () -> Bool = { IsSecureEventInputEnabled() }
    var frontmostBundleIDProvider: () -> String? = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
    var pasteSynthesizer: (() -> Void)?

    /// Inject text at the current cursor position.
    ///
    /// Pipeline:
    ///   1. Guard: verify Accessibility permission (CGEvent.post fails silently without it)
    ///   2. Save current clipboard contents (all types per item)
    ///   3. Clear clipboard and write transcription text as plain string
    ///   4. Synthesize Cmd+V keystroke via CGEvent
    ///   5. Wait ~100ms for target app to process paste (D-07)
    ///   6. Restore original clipboard contents
    ///
    /// - Parameter text: The transcription text to inject
    /// - Returns: true if injection was attempted, false if blocked (e.g. missing permission)
    @discardableResult
    func injectText(_ text: String) async -> Bool {
        // Guard: Accessibility must be granted or CGEvent.post silently fails
        guard AXIsProcessTrusted() else {
            NotificationService.shared.post(DicticusNotification.transcriptionFailed(
                TextInjectionError.accessibilityNotGranted
            ))
            return false
        }

        let pasteboard = NSPasteboard.general

        // Step 1: Save original clipboard contents
        let saved = saveClipboard(pasteboard)

        // Step 2: Write transcription text
        pasteboard.clearContents()
        // Append space after injected text so consecutive dictation segments
        // don't merge into one word. A trailing space is standard for dictation
        // (cursor sits after the space, ready for the next word or segment).
        let wrote = pasteboard.setString(text + " ", forType: .string)
        if !wrote {
            restoreClipboard(pasteboard, saved: saved)
            return false
        }

        // Step 3: Synthesize Cmd+V
        #if DEBUG_RECORDER
        // Quick task 260830-si1: read Carbon's secure-input flag immediately
        // before the synthesized keystroke — macOS silently drops CGEventTap
        // keystrokes while secure input is active, a candidate root cause for
        // the unexplained "history has it, cursor doesn't" paste failure.
        let secureInputEnabled = PasteProbe.secureInputEnabled()
        #endif
        synthesizePaste()

        // Step 4: Wait for target app to process paste
        // 100ms is more reliable than 50ms across Electron apps and terminal emulators.
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Step 5: Restore original clipboard
        restoreClipboard(pasteboard, saved: saved)
        #if DEBUG_RECORDER
        await PasteProbe.shared.record(secureInputEnabled: secureInputEnabled, injectionSucceeded: true, exit: "success")
        #endif
        return true
    }

    /// Save all items and types from the pasteboard.
    ///
    /// Iterates every pasteboard item and captures all type+data pairs.
    /// Handles string, RTF, HTML, images, file URLs — whatever the source app placed.
    /// Per RESEARCH.md: lazy-loaded/promised data may not fully capture (accepted limitation).
    func saveClipboard(_ pasteboard: NSPasteboard) -> SavedClipboard {
        var saved: [[(NSPasteboard.PasteboardType, Data)]] = []
        for item in pasteboard.pasteboardItems ?? [] {
            var itemData: [(NSPasteboard.PasteboardType, Data)] = []
            for type in item.types {
                if let data = item.data(forType: type) {
                    itemData.append((type, data))
                }
            }
            saved.append(itemData)
        }
        return SavedClipboard(items: saved)
    }

    /// Restore previously saved clipboard contents.
    ///
    /// Clears current pasteboard and writes back all saved items with their original types.
    func restoreClipboard(_ pasteboard: NSPasteboard, saved: SavedClipboard) {
        pasteboard.clearContents()
        for itemData in saved.items {
            let item = NSPasteboardItem()
            for (type, data) in itemData {
                item.setData(data, forType: type)
            }
            pasteboard.writeObjects([item])
        }
    }

    /// Synthesize Cmd+V keystroke via CGEvent for cross-app paste.
    ///
    /// V key = keyCode 9 (layout-independent, verified via macOS keycode mapping).
    /// Uses a private CGEventSource to avoid inheriting stale modifier flags
    /// from the hardware state (e.g. Ctrl+Shift still held from the hotkey combo).
    /// Posts to .cgSessionEventTap for reliable cross-app delivery.
    /// Requires Accessibility permission — CGEvent.post silently fails without it.
    func synthesizePaste() {
        let vKeyCode: CGKeyCode = 9  // V key (layout-independent)

        // Use a private event source so the synthesized keystroke is independent
        // of whatever physical keys the user may still be releasing.
        let source = CGEventSource(stateID: .privateState)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            return
        }

        // Set ONLY Command flag — explicitly clear any other modifiers
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
    }
}

/// Errors specific to text injection.
enum TextInjectionError: Error, LocalizedError {
    case accessibilityNotGranted

    var errorDescription: String? {
        switch self {
        case .accessibilityNotGranted:
            return "Accessibility permission required to paste text."
        }
    }
}
