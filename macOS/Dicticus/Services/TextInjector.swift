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
/// Per D-07: original clipboard contents are restored after
/// `clipboardRestoreDelayMilliseconds`, and only if the pasteboard still holds the transcript
/// that was written, compared trimmed of whitespace (Phase 50 plan 11; content-compare since
/// quick 260920-9m8 D-2).
/// Per Phase 50 plan 12 (CR-01): a call that arrives while a prior call's restore window is
/// still open waits for it before reading the pre-check signals or saving the clipboard.
/// Per D-08: Single Cmd+V code path for all apps including terminal emulators.
/// @MainActor isolation ensures all NSPasteboard and CGEvent calls happen on the main thread.
/// NSPasteboard.general and CGEvent.post are both main-thread-only AppKit/CoreGraphics APIs.
@MainActor
class TextInjector {

    /// Phase 50 plan 12 (CR-01): the app pastes through ONE instance so the busy window below
    /// (`pasteboardBusyUntil`) covers every caller — `HotkeyManager.textInjector` and
    /// `revertToRaw`'s default argument both resolve to this instance. Tests build their own
    /// instance and never touch this one (D-18).
    static let shared = TextInjector()

    /// Saved clipboard state — array of items, each with multiple type+data pairs.
    struct SavedClipboard {
        let items: [[(NSPasteboard.PasteboardType, Data)]]
    }

    /// Phase 50 D-02: which deterministic signal blocked delivery of the synthesized paste.
    /// Raw values are the exact `failure_signal` vocabulary logged by `PasteProbe` (D-05) — see
    /// `50-GATE-DIFF.md` §C. Backlog: `macos-paste-at-cursor-intermittent-failure.md` (text lands
    /// in history but never at the cursor) is the symptom this signal set diagnosed; quick
    /// 260920-9m8 superseded the `secureInput` half of that diagnosis (see below).
    enum DeliveryBlocker: String, Equatable {
        /// The frontmost app at paste time differs from the frontmost app at hotkey RELEASE
        /// (captured at key-up, not key-down, so a deliberate app switch during the hold is
        /// honoured and only a switch during the ASR/LLM wait is caught).
        case frontmostChanged = "frontmost_changed"
    }

    /// Phase 50 D-02: the outcome of one `injectText` call.
    enum Outcome: Equatable {
        /// The pre-check passed, Cmd+V was synthesized, and the prior clipboard was restored
        /// unless something else wrote to the pasteboard during the wait (Phase 50 plan 11).
        case delivered
        /// The pre-check failed before any paste was attempted; the transcript is left on the
        /// general pasteboard as a real user copy (no trailing space, no restore — D-02).
        case fallbackToClipboard(DeliveryBlocker)
        /// Accessibility was untrusted, the clipboard write itself failed, or the call was
        /// cancelled while waiting out a prior call's busy window (WR-07, 50-REVIEW.md) —
        /// unchanged from the pre-Phase-50 behaviour for the first two (AX already notifies; a
        /// failed write restores the clipboard silently), and by design for the third: a
        /// cancelled waiter resuming early would capture the prior call's not-yet-restored
        /// transcript as "the previous clipboard", so all three make a `.pasteUndeliverable`
        /// notification there a lie.
        case blocked
    }

    /// Phase 50 D-02: pure eligibility predicate for the delivery pre-check. An unknown bundle id
    /// on either side is never evidence of a switch — `revertToRaw` passes `nil` for
    /// `expectedBundleID` and so gets no pre-check at all. Quick 260920-9m8 (D-1): this used to
    /// also block on `IsSecureEventInputEnabled()`, ranked above a frontmost-app change. Dropped —
    /// measured 2026-09-20 to not block a CGEvent-posted Cmd+V.
    nonisolated static func deliveryBlocker(expectedBundleID: String?, currentBundleID: String?) -> DeliveryBlocker? {
        if let expectedBundleID, let currentBundleID, expectedBundleID != currentBundleID {
            return .frontmostChanged
        }
        return nil
    }

    /// Phase 50 plan 11: how long to wait after synthesizing Cmd+V before restoring the saved
    /// clipboard. Live record 2026-09-12 (`paste-2026-09-12.jsonl` line 122, `exit: success`):
    /// the first dictation into Gemini for macOS after an idle `model_reload` pasted the
    /// PREVIOUS clipboard content, not the transcript — the app's Electron renderer read the
    /// pasteboard asynchronously after the old fixed-delay restore had already run. Asymmetry: an
    /// early restore silently pastes the wrong text (data corruption); a late restore only
    /// leaves the transcript on the clipboard a little longer, which is the D-02 fallback state
    /// anyway. 750 is 7.5x the failing value — above an idle renderer's page-in plus IPC
    /// clipboard read, below the gap before a user's next deliberate Cmd+C/Cmd+V. This is a
    /// bias, not an elimination; the four `PasteProbe` fields (plan 11) make the next
    /// occurrence attributable.
    static let clipboardRestoreDelayMilliseconds: UInt64 = 750

    /// Quick 260920-9m8 (D-2): replaces the Phase 50 plan 11 changeCount-equality guard, which
    /// never fired in production — `restore_performed: false` on 281/281 successful pastes
    /// Sep 13-19, because Pure Paste.app re-declares the pasteboard as plain text after every
    /// write (changeCount +1, trailing space trimmed). Restores iff the pasteboard's current
    /// string, trimmed of whitespace/newlines, equals the written transcript trimmed the same
    /// way — a rewrite of the same content restores through; a user's Cmd+C of different content
    /// (the realistic case) still wins.
    nonisolated static func shouldRestoreClipboard(currentString: String?, writtenText: String) -> Bool {
        guard let currentString else { return false }
        return currentString.trimmingCharacters(in: .whitespacesAndNewlines) == writtenText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Phase 50 plan 12 (CR-01, 50-REVIEW.md 2026-09-12): a second `injectText`/`revertToRaw`
    /// call landing inside a prior call's restore window used to save that prior call's
    /// just-written transcript as the "previous clipboard" and re-install it after its own
    /// paste, silently replacing the user's real clipboard with an earlier dictation's text.
    /// The slack exists because the prior call's own `clipboardRestoreDelayMilliseconds` sleep
    /// starts AFTER its synthesized Cmd+V, while a waiter's deadline is computed from the same
    /// `pasteInstant` — without slack the two timers would fire at the same instant and the
    /// waiter could run its save before the prior call's restore decision. Both timers resume
    /// on the main actor in fire order, so 50ms is ample margin. The wait is bounded by
    /// construction: a waiter never waits past `pasteInstant + clipboardRestoreDelayMilliseconds
    /// + pasteboardBusySlackMilliseconds`, even if the prior call never cleared the window. If
    /// the waiter's own enclosing `Task` is cancelled before that deadline, it does not fall
    /// through early to save the clipboard (WR-07, 50-REVIEW.md) — it bails out and returns
    /// `.blocked` instead, so cancellation can only shorten the wait to `.blocked`, never to a
    /// premature `saveClipboard()`.
    static let pasteboardBusySlackMilliseconds: UInt64 = 50

    /// Test seams (Phase 50 D-02/D-05) — `var` properties, not initializer parameters, because
    /// production shares one instance, `TextInjector.shared` (Phase 50 plan 12, CR-01), used by
    /// `HotkeyManager.textInjector` and `revertToRaw`'s default argument; tests construct their
    /// own instance so per-instance seams and the busy window (`pasteboardBusyUntil`) stay
    /// hermetic. Production defaults match today's behaviour exactly.
    var axTrustedProbe: () -> Bool = { AXIsProcessTrusted() }
    var secureInputProbe: () -> Bool = { IsSecureEventInputEnabled() }
    var frontmostBundleIDProvider: () -> String? = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
    var pasteSynthesizer: (() -> Void)?

    /// Phase 50 plan 12 (CR-01): set right after a delivered paste's synthesized Cmd+V, to
    /// `pasteInstant` advanced by the restore delay + slack; cleared after the restore
    /// decision. A later `injectText`/`revertToRaw` call waits until this has passed before it
    /// reads the pre-check signals or saves the clipboard, so no save ever observes another
    /// call's not-yet-restored write.
    private var pasteboardBusyUntil: ContinuousClock.Instant?

    /// Inject text at the current cursor position.
    ///
    /// Pipeline (Phase 50 D-02/D-05; D-1/D-2 revised by quick 260920-9m8):
    ///   1. Guard: verify Accessibility permission (CGEvent.post fails silently without it) — exit `ax_untrusted`
    ///   2. Delivery pre-check: frontmost-app change only — exit `delivery_precheck_failed`,
    ///      leaves the transcript on the clipboard as a real user copy (no save/restore, no trailing space)
    ///   3. Save current clipboard contents (all types per item) — after waiting for a prior
    ///      call's restore window to close (Phase 50 plan 12, CR-01)
    ///   4. Clear clipboard and write transcription text as plain string — exit `clipboard_write_failed`
    ///   5. Synthesize Cmd+V keystroke via CGEvent
    ///   6. Wait `clipboardRestoreDelayMilliseconds` (Phase 50 plan 11), then restore the
    ///      original clipboard only if the pasteboard still holds the transcript we wrote,
    ///      content-compared after trimming (D-2) — exit `success`, recording `restore_delay_ms`,
    ///      `changecount_after_write`, `changecount_at_restore`, `restore_performed`
    ///
    /// - Parameters:
    ///   - text: The transcription text to inject.
    ///   - expectedFrontmostBundleID: The frontmost app's bundle id captured at hotkey RELEASE
    ///     (nil for callers with no release instant, e.g. `revertToRaw` — an unknown id never blocks).
    /// - Returns: `.delivered`, `.fallbackToClipboard(blocker)`, or `.blocked`.
    @discardableResult
    func injectText(_ text: String, expectedFrontmostBundleID: String? = nil) async -> Outcome {
        // Guard: Accessibility must be granted or CGEvent.post silently fails
        guard axTrustedProbe() else {
            NotificationService.shared.post(DicticusNotification.transcriptionFailed(
                TextInjectionError.accessibilityNotGranted
            ))
            #if DEBUG_RECORDER
            await PasteProbe.shared.record(secureInputEnabled: secureInputProbe(), injectionSucceeded: false, exit: "ax_untrusted")
            #endif
            return .blocked
        }

        // Phase 50 plan 12 (CR-01): wait out a prior call's still-open restore window before
        // reading the pre-check signals or saving the clipboard, so no save ever observes
        // another call's not-yet-restored transcript. One ContinuousClock instance serves this
        // wait, the busy deadline below, and the restoreDelayMs measurement.
        let clock = ContinuousClock()
        let entryInstant = clock.now
        while let busyUntil = pasteboardBusyUntil, clock.now < busyUntil {
            // WR-07 (50-REVIEW.md): cancellation must not let this call fall through to
            // saveClipboard() while a prior call's window is still open — a waiter that
            // resumes early would capture the prior call's not-yet-restored transcript as
            // the previous clipboard, reintroducing the CR-01 race. Bail out here instead
            // of falling through; no PasteProbe record on this path — the `exit:` vocabulary
            // is pinned by 50-GATE-DIFF.md §C and this exit is unreachable in production.
            if Task.isCancelled { return .blocked }
            try? await Task.sleep(until: busyUntil, clock: clock)
        }
        let waitedForPriorMs = Int((clock.now - entryInstant) / .milliseconds(1))

        let pasteboard = NSPasteboard.general

        // secureInput is read for the PasteProbe `secure_input_enabled` diagnostic field only —
        // it is not a delivery blocker. Measured 2026-09-20 (`secure-input-paste-test.swift`, the
        // same CGEvent path as `synthesizePaste()`): a synthesized Cmd+V was delivered both with
        // a BACKGROUND secure-input holder (Infuse.app; `paste-2026-09-20.jsonl` refused 8/8
        // dictations on this premise) and with the FRONTMOST app (iTerm2) holding it. Phase 50
        // RESEARCH.md:198's premise was never observed in either case (quick 260920-9m8, D-1).
        let secureInput = secureInputProbe()
        // Delivery pre-check (D-02): read the signal once, reuse below.
        let currentBundleID = frontmostBundleIDProvider()
        if let blocker = Self.deliveryBlocker(
            expectedBundleID: expectedFrontmostBundleID,
            currentBundleID: currentBundleID
        ) {
            // The fallback IS the user's copy (D-02) — deliberately no save/restore of the
            // prior clipboard and no trailing space; `backlog/pasteboard-transient-marker.md`'s
            // transient marker is scoped to the normal path only, not this one.
            pasteboard.clearContents()
            _ = pasteboard.setString(text, forType: .string)
            #if DEBUG_RECORDER
            await PasteProbe.shared.record(
                secureInputEnabled: secureInput,
                injectionSucceeded: false,
                exit: "delivery_precheck_failed",
                failureSignal: blocker.rawValue,
                waitedForPriorMs: waitedForPriorMs
            )
            #endif
            return .fallbackToClipboard(blocker)
        }

        // Step 1: Save original clipboard contents
        let saved = saveClipboard(pasteboard)

        // Step 2: Write transcription text
        pasteboard.clearContents()
        // Append space after injected text so consecutive dictation segments
        // don't merge into one word. A trailing space is standard for dictation
        // (cursor sits after the space, ready for the next word or segment).
        let writtenText = text + " "
        let wrote = pasteboard.setString(writtenText, forType: .string)
        if !wrote {
            restoreClipboard(pasteboard, saved: saved)
            #if DEBUG_RECORDER
            await PasteProbe.shared.record(secureInputEnabled: secureInput, injectionSucceeded: false, exit: "clipboard_write_failed", waitedForPriorMs: waitedForPriorMs)
            #endif
            return .blocked
        }

        // changeCount right after our write — the baseline the restore guard compares against.
        let changeCountAfterWrite = pasteboard.changeCount

        // Step 3: Synthesize Cmd+V
        if let pasteSynthesizer {
            pasteSynthesizer()
        } else {
            synthesizePaste()
        }

        // Step 4: Wait for the target app to process the paste (Phase 50 plan 11).
        let pasteInstant = clock.now
        // Phase 50 plan 12 (CR-01): open this call's restore window for any overlapping caller.
        pasteboardBusyUntil = pasteInstant.advanced(by: .milliseconds(Self.clipboardRestoreDelayMilliseconds + Self.pasteboardBusySlackMilliseconds))
        try? await Task.sleep(nanoseconds: Self.clipboardRestoreDelayMilliseconds * 1_000_000)

        // Step 5: Restore original clipboard, but only if it still holds the transcript we wrote
        // (D-2) — a user's Cmd+C of different content in the meantime wins instead.
        let changeCountAtRestore = pasteboard.changeCount
        let restorePerformed = Self.shouldRestoreClipboard(
            currentString: pasteboard.string(forType: .string),
            writtenText: writtenText
        )
        if restorePerformed {
            restoreClipboard(pasteboard, saved: saved)
        }
        // Phase 50 plan 12 (CR-01): the restore decision is made — close this call's window
        // before any suspension so a waiting caller can proceed.
        pasteboardBusyUntil = nil
        let restoreDelayMs = Int((clock.now - pasteInstant) / .milliseconds(1))
        #if DEBUG_RECORDER
        await PasteProbe.shared.record(
            secureInputEnabled: secureInput,
            injectionSucceeded: true,
            exit: "success",
            restoreDelayMs: restoreDelayMs,
            changeCountAfterWrite: changeCountAfterWrite,
            changeCountAtRestore: changeCountAtRestore,
            restorePerformed: restorePerformed,
            waitedForPriorMs: waitedForPriorMs
        )
        #endif
        return .delivered
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
