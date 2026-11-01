import Foundation

/// Routes the Live Activity's tap-through deep link (`dicticus://liveactivity`)
/// to a force-select of the Dictate tab. Recordings start through
/// `DictateIntent` (Action Button / Shortcuts), not through any URL.
///
/// This type owns ONLY navigation. It deliberately never touches
/// `pendingDictation` / `DicticusIPCBridge` — a stale `pendingDictation` flag
/// surviving process death previously caused a spontaneous recording start
/// (fixed by the `pendingDictationSetAt` staleness guard, commit 0a18fb2).
/// Conflating this navigation path with that flag would risk reintroducing
/// exactly that bug.
///
/// `dictateTabRequestCount` (not a Bool) so ContentView's `onChange` fires on
/// every tap, including a second consecutive tap while already on the
/// Dictate tab. ContentView reads it both in `onAppear` (covers cold launch,
/// where `onOpenURL` may fire before or after ContentView's first appearance)
/// and via `onChange` (covers foregrounding an already-running app, where
/// ContentView is already mounted and `onAppear` won't re-fire).
@MainActor
final class DeepLinkRouter: ObservableObject {
    static let shared = DeepLinkRouter()

    @Published private(set) var dictateTabRequestCount = 0

    private init() {}

    /// Returns `true` and bumps `dictateTabRequestCount` if `url` is the
    /// Live Activity's navigation-only deep link. Returns `false` (no side
    /// effect) for any other URL, including the removed record-start link.
    @discardableResult
    func handleLiveActivityTap(_ url: URL) -> Bool {
        guard url.scheme == "dicticus", url.host == "liveactivity" else { return false }
        dictateTabRequestCount += 1
        return true
    }

    /// Forces the Dictate tab for a genuine record-first launch (the
    /// `DictateIntent`/Action Button start) — 260815-ait Fix 2. Shares
    /// `dictateTabRequestCount` with `handleLiveActivityTap` so ContentView's existing
    /// onAppear/onChange hook handles both triggers with one mechanism. Callers must only
    /// invoke this once a pending record-first intent is confirmed genuine (not stale,
    /// not a normal in-app dictation start) — see `DictationViewModel.checkPendingIntent()`.
    func requestDictateTab() {
        dictateTabRequestCount += 1
    }
}
