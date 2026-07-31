import AppKit
import CoreGraphics
@preconcurrency import ApplicationServices

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
        synthesizePaste()

        // Step 4: Wait for target app to process paste
        // 100ms is more reliable than 50ms across Electron apps and terminal emulators.
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Step 5: Restore original clipboard
        restoreClipboard(pasteboard, saved: saved)
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
