import XCTest
@testable import Dicticus

/// Regression net for the preview session state machine, with injected decode closures
/// (no model): D-04 (one decode in flight, no queue) and D-02 (the release path can wait
/// for the in-flight decode to unwind, and a late result is never published).
///
/// No test depends on tight timing: decodes are held by a `Gate` the test controls, tests wait on
/// state with a generous cap (a passing run returns at once), and the only elapsed-time checks are
/// lower bounds, which a loaded machine can only satisfy more easily.
@MainActor
final class LivePreviewSessionTests: XCTestCase {

    /// A decode that waits here ignores cancellation until the test lets it through, like a
    /// CoreML prediction: `grant()` releases one waiter, `openAll()` releases every present and future one.
    @MainActor
    private final class Gate {
        private var isOpen = false
        private var permits = 0
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            if isOpen { return }
            if permits > 0 { permits -= 1; return }
            await withCheckedContinuation { waiters.append($0) }
        }

        func grant() {
            if waiters.isEmpty { permits += 1 } else { waiters.removeFirst().resume() }
        }

        func openAll() {
            isOpen = true
            for waiter in waiters { waiter.resume() }
            waiters.removeAll()
        }
    }

    @MainActor
    private final class Probe {
        var running = 0
        var maxRunning = 0
        var calls = 0
        var unwound = false
        var drained = false
        var published: [String] = []
        var starts: [ContinuousClock.Instant] = []
    }

    private func waitUntil(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(15)
        while !condition(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(5)) }
    }

    func testAtMostOneDecodeInFlightAndNoDecodeIsQueuedBehindASlowOne() async {
        let probe = Probe()
        let gate = Gate()
        let session = LivePreviewSession(
            cadence: .milliseconds(1),
            isActive: { true },
            decode: {
                probe.calls += 1
                probe.running += 1
                probe.maxRunning = max(probe.maxRunning, probe.running)
                await gate.wait()
                probe.running -= 1
                return nil
            },
            publish: { _ in }
        )
        session.start()
        for expected in 1...4 {
            await waitUntil { probe.calls == expected }
            XCTAssertEqual(probe.calls, expected, "a decode started while the previous one was still held")
            XCTAssertEqual(probe.running, 1)
            gate.grant()
            await waitUntil { probe.calls == expected + 1 }
        }
        gate.openAll()
        let stats = await session.cancelAndDrain()

        XCTAssertEqual(probe.maxRunning, 1)
        XCTAssertGreaterThanOrEqual(stats.ticks, 4)
    }

    func testTicksAreSpacedByAtLeastTheCadence() async {
        let probe = Probe()
        let clock = ContinuousClock()
        let cadence = Duration.milliseconds(100)
        let session = LivePreviewSession(
            cadence: cadence,
            isActive: { probe.calls < 4 },
            decode: { probe.starts.append(clock.now); probe.calls += 1; return nil },
            publish: { _ in }
        )
        session.start()
        await waitUntil { !session.isRunning }

        XCTAssertEqual(probe.starts.count, 4)
        for (earlier, later) in zip(probe.starts, probe.starts.dropFirst()) {
            XCTAssertGreaterThanOrEqual(later - earlier, cadence - .milliseconds(20), "ticks ran faster than the cadence")
        }
    }

    func testCancelAndDrainWaitsForTheDecodeAndNeverPublishesItsLateResult() async {
        let probe = Probe()
        let gate = Gate()
        let session = LivePreviewSession(
            cadence: .milliseconds(1),
            isActive: { true },
            decode: {
                probe.calls += 1
                await gate.wait()
                probe.unwound = true
                return "late"
            },
            publish: { probe.published.append($0) }
        )
        session.start()
        await waitUntil { probe.calls == 1 }
        let drain = Task { () -> LivePreviewSession.Stats in
            let stats = await session.cancelAndDrain()
            probe.drained = true
            return stats
        }
        // If the drain did not wait for the decode it would have returned by now.
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(probe.drained, "cancelAndDrain returned while the decode was still in flight")
        XCTAssertFalse(probe.unwound)

        gate.openAll()
        let stats = await drain.value

        XCTAssertTrue(probe.unwound)
        XCTAssertTrue(stats.cancelledInFlight)
        XCTAssertEqual(stats.published, 0)
        XCTAssertTrue(probe.published.isEmpty)
        XCTAssertGreaterThanOrEqual(stats.drainDuration, .milliseconds(40))
        XCTAssertFalse(session.isRunning)
    }

    func testCancelAndDrainIsSafeToCallTwice() async {
        let probe = Probe()
        let session = LivePreviewSession(
            cadence: .milliseconds(5),
            isActive: { true },
            decode: { "x" },
            publish: { probe.published.append($0) }
        )
        session.start()
        await waitUntil { probe.published.count >= 2 }
        let first = await session.cancelAndDrain()
        let second = await session.cancelAndDrain()

        XCTAssertGreaterThanOrEqual(first.published, 2)
        XCTAssertEqual(first.ticks, second.ticks)
        XCTAssertEqual(first.published, second.published)
    }

    func testLoopStopsWhenTheSessionIsNoLongerActive() async {
        let probe = Probe()
        let session = LivePreviewSession(
            cadence: .milliseconds(5),
            isActive: { probe.calls < 2 },
            decode: { probe.calls += 1; return nil },
            publish: { _ in }
        )
        session.start()
        await waitUntil { !session.isRunning }
        let stats = await session.cancelAndDrain()

        XCTAssertEqual(stats.ticks, 2)
    }

    // MARK: - decode budget (review WR-02)

    /// A model run slower than this ends the previews; `slow` is far above it and `fast` far below.
    private let budget = Duration.milliseconds(400)
    private let slow = 1500
    private let fast = 0

    private func budgetSession(
        decodeMs: [Int],
        ranModel: @escaping @MainActor () -> Bool = { true },
        publish: @escaping @MainActor (String) -> Void = { _ in }
    ) -> LivePreviewSession {
        var call = 0
        return LivePreviewSession(
            cadence: .milliseconds(5),
            isActive: { true },
            decode: {
                let ms = decodeMs[min(call, decodeMs.count - 1)]
                call += 1
                try? await Task.sleep(for: .milliseconds(ms))
                return "x"
            },
            publish: publish,
            decodeBudget: budget,
            ranModel: ranModel
        )
    }

    func testASlowDecodeEndsPreviewsForTheHoldAndStillPublishesItsText() async {
        let session = budgetSession(decodeMs: [fast, slow])
        session.start()
        await waitUntil { !session.isRunning }
        let stats = await session.cancelAndDrain()

        XCTAssertEqual(stats.ticks, 2)
        XCTAssertEqual(stats.published, 2)
        XCTAssertTrue(stats.overBudget)
        XCTAssertFalse(session.isRunning)
    }

    func testDecodesWithinTheBudgetKeepRunning() async {
        let probe = Probe()
        let session = budgetSession(decodeMs: [fast], publish: { probe.published.append($0) })
        session.start()
        await waitUntil { probe.published.count >= 4 }
        let stats = await session.cancelAndDrain()

        XCTAssertGreaterThanOrEqual(stats.ticks, 4)
        XCTAssertFalse(stats.overBudget)
    }

    func testTheFirstDecodeOfAHoldIsExemptFromTheBudget() async {
        let probe = Probe()
        let session = budgetSession(decodeMs: [slow, fast], publish: { probe.published.append($0) })
        session.start()
        await waitUntil { probe.published.count >= 3 }
        let stats = await session.cancelAndDrain()

        XCTAssertGreaterThanOrEqual(stats.ticks, 3)
        XCTAssertFalse(stats.overBudget)
    }

    func testTheExemptionBelongsToTheFirstTickThatRanTheModelNotTheFirstTick() async {
        // Ticks 1-2 return early like a hold shorter than 1.2 s; the first model run is
        // tick 3 and is slow. Only the second slow model run ends the previews.
        var tick = 0
        let slowMs = slow
        let session = LivePreviewSession(
            cadence: .milliseconds(5),
            isActive: { true },
            decode: {
                tick += 1
                if tick > 2 { try? await Task.sleep(for: .milliseconds(slowMs)) }
                return nil
            },
            publish: { _ in },
            decodeBudget: budget,
            ranModel: { tick > 2 }
        )
        session.start()
        await waitUntil { !session.isRunning }
        let stats = await session.cancelAndDrain()

        XCTAssertEqual(stats.ticks, 4)
        XCTAssertTrue(stats.overBudget)
        XCTAssertEqual(stats.decodeDurations.count, 2, "skipped ticks were timed as decodes")
    }

    func testStatsCarrySkippedTicksFromTheProvider() async {
        let session = LivePreviewSession(
            cadence: .milliseconds(10),
            isActive: { true },
            decode: { nil },
            publish: { _ in },
            skippedNoVoice: { 7 }
        )
        session.start()
        let stats = await session.cancelAndDrain()

        XCTAssertEqual(stats.skippedNoVoice, 7)
        XCTAssertFalse(stats.overBudget)
    }

    func testTheProductionBudgetIsTwoSeconds() {
        XCTAssertEqual(LivePreviewSession.productionDecodeBudget, .seconds(2))
    }

    // MARK: - release ordering (G1): drain the preview, then take the samples, then decode them

    func testTheReleaseDrainsThePreviewBeforeTakingTheSamplesAndDecodesExactlyThem() async throws {
        var events: [String] = []
        let started = Probe()
        let gate = Gate()
        let session = LivePreviewSession(
            cadence: .milliseconds(1),
            isActive: { true },
            decode: {
                started.calls += 1
                await gate.wait()  // ignores cancellation, like a CoreML prediction
                events.append("preview unwound")
                return nil
            },
            publish: { _ in }
        )
        session.start()
        await waitUntil { started.calls > 0 }
        // Opens after the drain has begun; the order below holds however long that takes.
        let opener = Task { try? await Task.sleep(for: .milliseconds(50)); gate.openAll() }

        let decoded = try await TranscriptionService.releaseSequence(
            previewSession: session,
            onDrained: { _ in events.append("drained") },
            takeSamples: { events.append("take samples"); return [1, 2, 3] },
            decode: { samples in events.append("final decode"); return samples }
        )
        await opener.value

        XCTAssertEqual(events, ["preview unwound", "drained", "take samples", "final decode"])
        XCTAssertEqual(decoded, [1, 2, 3], "the final decode got different samples than the drained buffer")
    }

    func testTheReleaseWithoutAPreviewStillDecodesTheSamples() async throws {
        var drained = false
        let decoded = try await TranscriptionService.releaseSequence(
            previewSession: nil,
            onDrained: { _ in drained = true },
            takeSamples: { [4, 5] },
            decode: { $0.map { $0 * 2 } }
        )
        XCTAssertEqual(decoded, [8, 10])
        XCTAssertFalse(drained)
    }

    func testAFailingFinalDecodeStillReportsTheDrainedPreviewStats() async {
        struct Boom: Error {}
        let session = LivePreviewSession(cadence: .milliseconds(1), isActive: { true }, decode: { nil }, publish: { _ in })
        session.start()
        var drained = false
        do {
            _ = try await TranscriptionService.releaseSequence(
                previewSession: session,
                onDrained: { _ in drained = true },
                takeSamples: { [] },
                decode: { _ -> Int in throw Boom() }
            )
            XCTFail("decode error was swallowed")
        } catch {
            XCTAssertTrue(error is Boom)
        }
        XCTAssertTrue(drained)
    }
}
