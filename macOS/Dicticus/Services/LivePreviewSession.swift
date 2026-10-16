import Foundation

/// Cadence loop for the live transcript overlay (Phase 51, D-02, D-04).
///
/// At most one decode is in flight. When a decode outlasts the cadence the next one
/// starts right after it returns, so no queue builds up. `cancelAndDrain()` cancels the
/// loop and waits until the in-flight decode has unwound; the release path awaits it
/// before the final decode starts, because both share one non-Sendable WhisperKit.
@MainActor
final class LivePreviewSession {

    /// Settings key for the toggle (D-14). Absent means ON.
    nonisolated static let enabledKey = "livePreviewEnabled"

    /// Callers pass `DicticusDefaults.suite`, never `UserDefaults.standard`.
    nonisolated static func isEnabled(_ defaults: UserDefaults) -> Bool {
        defaults.object(forKey: enabledKey) == nil ? true : defaults.bool(forKey: enabledKey)
    }

    static let productionCadence: Duration = .milliseconds(500)

    /// A preview decode slower than this ends previews for the hold (review WR-02), so a
    /// slow Mac cannot make every release wait for a long in-flight decode. About twice the
    /// measured p90 of a 15 s preview decode on the development Mac (1025 ms) and above the
    /// 28 s-window p90 (1291 ms), spike 018 RESULTS.md, latency sweep.
    static let productionDecodeBudget: Duration = .seconds(2)

    struct Stats: Sendable {
        var ticks: Int
        var published: Int
        var cancelledInFlight: Bool
        var drainDuration: Duration
        /// Per model run and per publish; filled in DEBUG builds only (empty in Release).
        var decodeDurations: [Duration]
        var publishInstants: [ContinuousClock.Instant]
        /// The hold's previews were stopped because a decode exceeded the budget.
        var overBudget = false
        /// Ticks the voice gate skipped for lack of new voiced audio.
        var skippedNoVoice = 0
    }

    private let cadence: Duration
    private let isActive: @MainActor () -> Bool
    private let decode: @MainActor () async -> String?
    private let publish: @MainActor (String) -> Void
    private let decodeBudget: Duration
    private let ranModel: @MainActor () -> Bool
    private let skippedNoVoice: @MainActor () -> Int

    private var task: Task<Void, Never>?
    private var running = false
    private var decodeInFlight = false
    private var cancelledInFlight = false
    private var ticks = 0
    private var published = 0
    private var decodeDurations: [Duration] = []
    private var publishInstants: [ContinuousClock.Instant] = []
    private var drainDuration: Duration = .zero
    private var modelRuns = 0
    private var overBudget = false

    init(
        cadence: Duration,
        isActive: @escaping @MainActor () -> Bool,
        decode: @escaping @MainActor () async -> String?,
        publish: @escaping @MainActor (String) -> Void,
        decodeBudget: Duration = LivePreviewSession.productionDecodeBudget,
        ranModel: @escaping @MainActor () -> Bool = { true },
        skippedNoVoice: @escaping @MainActor () -> Int = { 0 }
    ) {
        self.cadence = cadence
        self.isActive = isActive
        self.decode = decode
        self.publish = publish
        self.decodeBudget = decodeBudget
        self.ranModel = ranModel
        self.skippedNoVoice = skippedNoVoice
    }

    var isRunning: Bool { running }

    func start() {
        guard task == nil else { return }
        running = true
        task = Task { @MainActor [self] in
            let clock = ContinuousClock()
            while !Task.isCancelled && isActive() {
                let started = clock.now
                decodeInFlight = true
                let text = await decode()
                decodeInFlight = false
                let elapsed = clock.now - started
                let ranTheModel = ranModel()
                #if DEBUG
                // Skipped ticks take no time worth reporting; only model runs are timed.
                if ranTheModel { decodeDurations.append(elapsed) }
                #endif
                ticks += 1
                // A decode that finishes after cancellation must never be published.
                if let text, !Task.isCancelled {
                    published += 1
                    #if DEBUG
                    publishInstants.append(clock.now)
                    #endif
                    publish(text)
                }
                // Budget stop (WR-02). Only ticks that ran the model count, and the first of
                // them is exempt: it can be slow after idle (CoreML/ANE warm-up), and stopping
                // there would disable previews for the dictation the user notices. The panel
                // keeps its last text and no decode is left in flight for the release to drain.
                if ranTheModel {
                    modelRuns += 1
                    if modelRuns > 1 && elapsed > decodeBudget {
                        overBudget = true
                        break
                    }
                }
                let rest = cadence - elapsed
                if rest > .zero { try? await Task.sleep(for: rest) }
            }
            running = false
        }
    }

    @discardableResult
    func cancelAndDrain() async -> Stats {
        let clock = ContinuousClock()
        let began = clock.now
        if decodeInFlight { cancelledInFlight = true }
        let pending = task
        pending?.cancel()
        await pending?.value
        task = nil
        running = false
        if pending != nil { drainDuration = clock.now - began }
        return Stats(
            ticks: ticks,
            published: published,
            cancelledInFlight: cancelledInFlight,
            drainDuration: drainDuration,
            decodeDurations: decodeDurations,
            publishInstants: publishInstants,
            overBudget: overBudget,
            skippedNoVoice: skippedNoVoice()
        )
    }
}
