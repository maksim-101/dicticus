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

    struct Stats: Sendable {
        var ticks: Int
        var published: Int
        var cancelledInFlight: Bool
        var drainDuration: Duration
        var decodeDurations: [Duration]
        var publishInstants: [ContinuousClock.Instant]
    }

    private let cadence: Duration
    private let isActive: @MainActor () -> Bool
    private let decode: @MainActor () async -> String?
    private let publish: @MainActor (String) -> Void

    private var task: Task<Void, Never>?
    private var running = false
    private var decodeInFlight = false
    private var cancelledInFlight = false
    private var ticks = 0
    private var published = 0
    private var decodeDurations: [Duration] = []
    private var publishInstants: [ContinuousClock.Instant] = []
    private var drainDuration: Duration = .zero

    init(
        cadence: Duration,
        isActive: @escaping @MainActor () -> Bool,
        decode: @escaping @MainActor () async -> String?,
        publish: @escaping @MainActor (String) -> Void
    ) {
        self.cadence = cadence
        self.isActive = isActive
        self.decode = decode
        self.publish = publish
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
                decodeDurations.append(elapsed)
                ticks += 1
                // A decode that finishes after cancellation must never be published.
                if let text, !Task.isCancelled {
                    published += 1
                    publishInstants.append(clock.now)
                    publish(text)
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
            publishInstants: publishInstants
        )
    }
}
