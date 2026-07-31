import AppKit
import CoreGraphics
import Foundation
import Combine
import os.log

/// NSEvent-based listener for modifier-only hotkeys (Fn+Shift, Fn+Control, Fn+Option).
///
/// Runs in parallel with KeyboardShortcuts, which cannot capture modifier-only combos.
/// Per D-08: parallel system architecture.
/// Per D-09: Fn+Shift = plain dictation default, Fn+Control = AI cleanup default.
///
/// Uses NSEvent.addGlobalMonitorForEvents instead of CGEventTap because macOS 15
/// disables CGEventTap for ad-hoc signed apps even with Accessibility permission.
/// NSEvent global monitor works reliably within the app's security context.
///
/// Security: Only monitors `.flagsChanged` events — never sees keystrokes (T-05-01).
/// Requires Accessibility permission for global monitoring (T-05-02).
/// Handler performs O(1) flag comparison only — no blocking (T-05-03).
///
/// ObservableObject so SettingsSection can bind to combo properties via @EnvironmentObject.
/// @Published properties publish on MainActor (objectWillChange fires on main thread).
///
/// @unchecked Sendable: all mutable state is accessed on the main thread —
/// NSEvent global monitor handler runs on the main thread.
class ModifierHotkeyListener: ObservableObject, @unchecked Sendable {

    // MARK: - Configuration

    /// The modifier combo mapped to plain dictation mode.
    /// Default: .fnShift per D-09. @Published for SwiftUI Picker binding in SettingsSection.
    /// Persisted to UserDefaults via didSet so selections survive app restarts.
    @Published var plainDictationCombo: ModifierCombo {
        didSet {
            UserDefaults.standard.set("\(plainDictationCombo)", forKey: "modifierPlainDictation")
        }
    }

    /// The modifier combo mapped to AI cleanup mode.
    /// Default: .fnControl per D-09. @Published for SwiftUI Picker binding in SettingsSection.
    /// Persisted to UserDefaults via didSet so selections survive app restarts.
    @Published var cleanupCombo: ModifierCombo {
        didSet {
            UserDefaults.standard.set("\(cleanupCombo)", forKey: "modifierAiCleanup")
        }
    }

    // MARK: - Init

    init() {
        // Load persisted combo selections from UserDefaults; fall back to defaults (D-09).
        // T-05-04: Invalid UserDefaults values fall through to default — no crash.
        let savedPlain: ModifierCombo = {
            if let raw = UserDefaults.standard.string(forKey: "modifierPlainDictation"),
               let combo = ModifierCombo.allCases.first(where: { "\($0)" == raw }) {
                return combo
            }
            return .fnShift
        }()
        let savedCleanup: ModifierCombo = {
            if let raw = UserDefaults.standard.string(forKey: "modifierAiCleanup"),
               let combo = ModifierCombo.allCases.first(where: { "\($0)" == raw }) {
                return combo
            }
            return .fnControl
        }()
        // Assign directly (bypass didSet) to avoid redundant UserDefaults writes on launch.
        self._plainDictationCombo = Published(initialValue: savedPlain)
        self._cleanupCombo = Published(initialValue: savedCleanup)
    }

    // MARK: - Closures for HotkeyManager wiring

    /// Called when a modifier combo is fully pressed. Set by HotkeyManager in Plan 02.
    var onComboActivated: ((DictationMode) -> Void)?

    /// Called when a modifier combo is released. Set by HotkeyManager in Plan 02.
    var onComboReleased: ((DictationMode) -> Void)?

    // MARK: - Private state

    private var monitor: Any?

    /// Previous modifier flags state — updated in handler to detect transitions.
    /// Accessed only from the main thread (NSEvent handler runs on main thread).
    private var previousNSFlags: NSEvent.ModifierFlags = []

    /// In-flight release-debounce task (see debug session `ptt-stops-mid-hold`).
    /// macOS's HID dispatcher occasionally emits a spurious `flagsChanged` event during long
    /// modifier-only holds, briefly clearing a combo bit even though the user's fingers
    /// are still pressing. We delay the release fire by `releaseDebounceMillis` and re-check
    /// the live system flags before committing — if the combo is still satisfied we discard
    /// the transient. Cancelled and replaced on every new release-candidate, and cancelled
    /// on press events.
    private var pendingReleaseTask: Task<Void, Never>?

    /// Debounce window for spurious-flag-drop suppression. 100 ms provides a safer margin for
    /// transient drops during long holds while remaining below the human-perception threshold
    /// for push-to-talk release-to-action (~150 ms).
    private static let releaseDebounceMillis: UInt64 = 100

    // MARK: - Lifecycle

    /// Start monitoring modifier key changes via NSEvent global monitor.
    ///
    /// Requires Accessibility permission for global event monitoring (T-05-02).
    func start() {
        let log = Logger(subsystem: "com.dicticus", category: "modifier-hotkey")

        // Only monitor flagsChanged events — never sees keystrokes (T-05-01)
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self else { return }

            let currentFlags = event.modifierFlags
            let previous = self.previousNSFlags
            self.previousNSFlags = currentFlags

            let plain = self.plainDictationCombo
            let cleanup = self.cleanupCombo

            if let transition = ModifierHotkeyListener.detectNSTransition(
                from: previous,
                to: currentFlags,
                plainCombo: plain,
                cleanupCombo: cleanup
            ) {
                if transition.isPress {
                    // Cancel any in-flight release debounce — a press supersedes a pending release.
                    self.pendingReleaseTask?.cancel()
                    self.pendingReleaseTask = nil
                    log.info("combo activated: \(String(describing: transition.mode), privacy: .public)")
                    self.onComboActivated?(transition.mode)
                } else {
                    // Debounce: re-verify against live NSEvent.modifierFlags after a brief delay.
                    // macOS's HID dispatcher can emit transient flag-drops during long holds;
                    // a confirmed release must show the combo missing in the LIVE system state.
                    let comboFlags = (transition.mode == .plain ? plain : cleanup).nsFlags
                    self.pendingReleaseTask?.cancel()
                    self.pendingReleaseTask = Task { @MainActor [weak self] in
                        try? await Task.sleep(nanoseconds: ModifierHotkeyListener.releaseDebounceMillis * 1_000_000)
                        guard !Task.isCancelled, let self else { return }
                        let live = NSEvent.modifierFlags
                        if ModifierHotkeyListener.shouldFireRelease(liveFlags: live, comboFlags: comboFlags) {
                            log.info("combo released: \(String(describing: transition.mode), privacy: .public)")
                            self.onComboReleased?(transition.mode)
                        } else {
                            // Resync `previousNSFlags` to live state so the next genuine release
                            // is detected (otherwise `prev` would no longer be a superset of the
                            // combo and `detectNSTransition` could miss the real release).
                            self.previousNSFlags = live
                            log.info("release discarded — transient flag drop (\(String(describing: transition.mode), privacy: .public))")
                        }
                        self.pendingReleaseTask = nil
                    }
                }
            }
        }

        if monitor != nil {
            log.info("NSEvent global monitor started for flagsChanged")
        } else {
            log.error("NSEvent global monitor creation FAILED — accessibility permission may not be granted")
        }
    }

    /// Stop the global monitor.
    func stop() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        previousNSFlags = []
        pendingReleaseTask?.cancel()
        pendingReleaseTask = nil
    }

    // MARK: - Pure release decision (testable)

    /// Decide whether a candidate release event should fire after the debounce window.
    ///
    /// Pure function — given the live system modifier flags at debounce time, return
    /// `true` only if the combo is genuinely no longer held. If the live state still
    /// contains every combo flag, the original release event was a transient HID
    /// dispatcher hiccup and must be discarded.
    static func shouldFireRelease(
        liveFlags: NSEvent.ModifierFlags,
        comboFlags: NSEvent.ModifierFlags
    ) -> Bool {
        let relevantMask: NSEvent.ModifierFlags = [
            .function,
            .shift,
            .control,
            .option
        ]
        let live = liveFlags.intersection(relevantMask)
        return !live.isSuperset(of: comboFlags)
    }

    // MARK: - Pure transition detection — NSEvent.ModifierFlags (testable)

    /// Detect a combo press or release from an NSEvent.ModifierFlags transition.
    ///
    /// Pure function — no side effects, no hardware needed. Designed for unit testing.
    ///
    /// Logic:
    /// 1. Filter both previous and current flags to only the four relevant modifiers
    ///    (Fn, Shift, Control, Option). Ignores Caps Lock, Command, etc.
    /// 2. For each combo (plain, cleanup):
    ///    - Activation: current filtered flags EXACTLY match the combo flags AND
    ///      previous filtered flags did NOT fully contain the combo.
    ///    - Release: previous filtered flags fully contained the combo AND
    ///      current filtered flags do NOT fully contain it.
    static func detectNSTransition(
        from previous: NSEvent.ModifierFlags,
        to current: NSEvent.ModifierFlags,
        plainCombo: ModifierCombo,
        cleanupCombo: ModifierCombo
    ) -> (mode: DictationMode, isPress: Bool)? {
        // Only consider these four modifier flags — ignore unrelated bits
        let relevantMask: NSEvent.ModifierFlags = [
            .function,
            .shift,
            .control,
            .option
        ]

        let prev = previous.intersection(relevantMask)
        let curr = current.intersection(relevantMask)

        // Check each combo in priority order (plain first, then cleanup)
        for (combo, mode) in [(plainCombo, DictationMode.plain), (cleanupCombo, DictationMode.aiCleanup)] {
            let comboFlags = combo.nsFlags

            // Activation: current == exactly combo flags AND previous didn't have the full combo
            let comboActiveNow = curr == comboFlags
            let comboWasActive = prev.isSuperset(of: comboFlags)

            if comboActiveNow && !comboWasActive {
                return (mode: mode, isPress: true)
            }

            // Release: previous had all combo flags AND current is missing at least one
            if comboWasActive && !curr.isSuperset(of: comboFlags) {
                return (mode: mode, isPress: false)
            }
        }

        return nil
    }

    // MARK: - Pure transition detection — CGEventFlags (unit test compatibility)

    /// CGEventFlags-based transition detection. Kept for existing unit tests.
    /// The runtime now uses `detectNSTransition` via NSEvent global monitor.
    static func detectTransition(
        from previous: CGEventFlags,
        to current: CGEventFlags,
        plainCombo: ModifierCombo,
        cleanupCombo: ModifierCombo
    ) -> (mode: DictationMode, isPress: Bool)? {
        let relevantMask: CGEventFlags = [
            .maskSecondaryFn,
            .maskShift,
            .maskControl,
            .maskAlternate
        ]

        let prev = previous.intersection(relevantMask)
        let curr = current.intersection(relevantMask)

        for (combo, mode) in [(plainCombo, DictationMode.plain), (cleanupCombo, DictationMode.aiCleanup)] {
            let comboFlags = combo.flags

            let comboActiveNow = curr == comboFlags
            let comboWasActive = prev.isSuperset(of: comboFlags)

            if comboActiveNow && !comboWasActive {
                return (mode: mode, isPress: true)
            }

            if comboWasActive && !curr.isSuperset(of: comboFlags) {
                return (mode: mode, isPress: false)
            }
        }

        return nil
    }
}
