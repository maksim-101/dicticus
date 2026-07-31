import XCTest
@testable import Dicticus

/// Regression test for the CLEANRD-04 D-guard.
///
/// `reregisterAll()` cancels the previous pair of KeyboardShortcuts AsyncStream
/// consumer tasks and re-spawns fresh ones. KeyboardShortcuts' AsyncStream never
/// calls `finish()`, so a consumer's `for await` loop ends ONLY when its Task is
/// cancelled — which is exactly what happens to the "old" tasks on every
/// `reregisterAll()` call. Before the guard, that cancelled-loop termination
/// unconditionally set `registrationFailed = true`, racing against (and landing
/// after) the fresh call's `registrationFailed = false` reset — so clicking
/// "Re-register" on a perfectly healthy app falsely raised the hotkey Repair
/// banner. This test drives that exact sequence and asserts the flag settles false.
@MainActor
final class HotkeyManagerReregisterTests: XCTestCase {

    func testReregisterAllLeavesRegistrationFailedFalse() async throws {
        let manager = HotkeyManager()

        // First call: plainDictationTask/cleanupTask are nil, so cancelling them
        // is a no-op — this spawns the initial (generation-1) pair of AsyncStream
        // consumer tasks.
        manager.reregisterAll()

        // Second call: cancels the generation-1 tasks spawned above and spawns a
        // fresh (generation-2) pair. This is the exact sequence that triggers the
        // false positive pre-guard: the cancelled generation-1 tasks' `for await`
        // loops unwind asynchronously and (without the guard) flip
        // registrationFailed back to true after generation-2 already reset it.
        manager.reregisterAll()

        // Allow the cancelled generation-1 tasks' loops to unwind and their
        // trailing MainActor-hop assignments to run and settle.
        try await Task.sleep(nanoseconds: 200_000_000)
        await Task.yield()

        XCTAssertFalse(
            manager.registrationFailed,
            "reregisterAll() must not leave registrationFailed=true due to a cancelled prior-generation task"
        )
    }
}
