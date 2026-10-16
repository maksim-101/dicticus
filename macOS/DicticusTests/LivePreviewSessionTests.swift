import XCTest
@testable import Dicticus

/// Regression net for the preview session state machine, with injected decode closures
/// (no model): D-04 (one decode in flight, no queue) and D-02 (the release path can wait
/// for the in-flight decode to unwind, and a late result is never published).
@MainActor
final class LivePreviewSessionTests: XCTestCase {

    /// A decode that waits here ignores cancellation until the test opens the gate.
    @MainActor
    private final class Gate {
        private var isOpen = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            if isOpen { return }
            await withCheckedContinuation { waiters.append($0) }
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
        var published: [String] = []
    }

    func testAtMostOneDecodeInFlightWhenDecodeOutlastsCadence() async {
        let probe = Probe()
        let session = LivePreviewSession(
            cadence: .milliseconds(50),
            isActive: { true },
            decode: {
                probe.running += 1
                probe.maxRunning = max(probe.maxRunning, probe.running)
                try? await Task.sleep(for: .milliseconds(150))
                probe.running -= 1
                return nil
            },
            publish: { _ in }
        )
        session.start()
        try? await Task.sleep(for: .seconds(1))
        let stats = await session.cancelAndDrain()

        XCTAssertEqual(probe.maxRunning, 1)
        XCTAssertLessThanOrEqual(stats.ticks, 8, "decodes queued up behind a slow one")
        XCTAssertGreaterThanOrEqual(stats.ticks, 3)
    }

    func testInstantDecodeTicksAtTheCadence() async {
        let session = LivePreviewSession(
            cadence: .milliseconds(200),
            isActive: { true },
            decode: { nil },
            publish: { _ in }
        )
        session.start()
        try? await Task.sleep(for: .milliseconds(1050))
        let stats = await session.cancelAndDrain()

        XCTAssertGreaterThanOrEqual(stats.ticks, 5)
        XCTAssertLessThanOrEqual(stats.ticks, 7)
    }

    func testCancelAndDrainWaitsForTheDecodeAndNeverPublishesItsLateResult() async {
        let probe = Probe()
        let session = LivePreviewSession(
            cadence: .milliseconds(10),
            isActive: { true },
            decode: {
                // The detached sleep ignores cancellation, like a CoreML prediction.
                await Task.detached { try? await Task.sleep(for: .milliseconds(300)) }.value
                probe.unwound = true
                return "late"
            },
            publish: { probe.published.append($0) }
        )
        session.start()
        try? await Task.sleep(for: .milliseconds(60))
        XCTAssertFalse(probe.unwound)

        let stats = await session.cancelAndDrain()

        XCTAssertTrue(probe.unwound, "cancelAndDrain returned before the decode finished")
        XCTAssertTrue(stats.cancelledInFlight)
        XCTAssertEqual(stats.published, 0)
        XCTAssertTrue(probe.published.isEmpty)
        XCTAssertGreaterThan(stats.drainDuration, .milliseconds(100))
        XCTAssertFalse(session.isRunning)
    }

    func testCancelAndDrainIsSafeToCallTwice() async {
        let session = LivePreviewSession(
            cadence: .milliseconds(20),
            isActive: { true },
            decode: { "x" },
            publish: { _ in }
        )
        session.start()
        try? await Task.sleep(for: .milliseconds(100))
        let first = await session.cancelAndDrain()
        let second = await session.cancelAndDrain()

        XCTAssertEqual(first.ticks, second.ticks)
        XCTAssertEqual(first.published, second.published)
    }

    func testLoopStopsWhenTheSessionIsNoLongerActive() async {
        let probe = Probe()
        let session = LivePreviewSession(
            cadence: .milliseconds(20),
            isActive: { probe.calls < 2 },
            decode: { probe.calls += 1; return nil },
            publish: { _ in }
        )
        session.start()
        try? await Task.sleep(for: .milliseconds(300))
        let stats = await session.cancelAndDrain()

        XCTAssertEqual(stats.ticks, 2)
    }

    // MARK: - decode budget (review WR-02)

    private func budgetSession(
        decodeMs: [Int],
        ranModel: @escaping @MainActor () -> Bool = { true },
        publish: @escaping @MainActor (String) -> Void = { _ in }
    ) -> LivePreviewSession {
        var call = 0
        return LivePreviewSession(
            cadence: .milliseconds(10),
            isActive: { true },
            decode: {
                let ms = decodeMs[min(call, decodeMs.count - 1)]
                call += 1
                try? await Task.sleep(for: .milliseconds(ms))
                return "x"
            },
            publish: publish,
            decodeBudget: .milliseconds(200),
            ranModel: ranModel
        )
    }

    func testASlowDecodeEndsPreviewsForTheHoldAndStillPublishesItsText() async {
        let session = budgetSession(decodeMs: [50, 300])
        session.start()
        try? await Task.sleep(for: .seconds(1))
        let stats = await session.cancelAndDrain()

        XCTAssertEqual(stats.ticks, 2)
        XCTAssertEqual(stats.published, 2)
        XCTAssertTrue(stats.overBudget)
        XCTAssertFalse(session.isRunning)
    }

    func testDecodesWithinTheBudgetKeepRunning() async {
        let session = budgetSession(decodeMs: [50])
        session.start()
        try? await Task.sleep(for: .seconds(1))
        let stats = await session.cancelAndDrain()

        XCTAssertGreaterThanOrEqual(stats.ticks, 3)
        XCTAssertFalse(stats.overBudget)
    }

    func testTheFirstDecodeOfAHoldIsExemptFromTheBudget() async {
        let session = budgetSession(decodeMs: [300, 50])
        session.start()
        try? await Task.sleep(for: .seconds(1))
        let stats = await session.cancelAndDrain()

        XCTAssertGreaterThanOrEqual(stats.ticks, 3)
        XCTAssertFalse(stats.overBudget)
    }

    func testTheExemptionBelongsToTheFirstTickThatRanTheModelNotTheFirstTick() async {
        // Ticks 1-2 return early like a hold shorter than 1.2 s; the first model run is
        // tick 3 and is slow. Only the second slow model run ends the previews.
        var tick = 0
        let session = LivePreviewSession(
            cadence: .milliseconds(10),
            isActive: { true },
            decode: {
                tick += 1
                if tick > 2 { try? await Task.sleep(for: .milliseconds(300)) }
                return nil
            },
            publish: { _ in },
            decodeBudget: .milliseconds(200),
            ranModel: { tick > 2 }
        )
        session.start()
        try? await Task.sleep(for: .seconds(1.5))
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
        try? await Task.sleep(for: .milliseconds(50))
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
        while started.calls == 0 { try await Task.sleep(for: .milliseconds(5)) }
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
