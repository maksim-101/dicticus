import Foundation

/// Per-microphone memory of how loud this user's speech is, for the Layer 2 gate's absolute floor
/// (quick task 261020-dvf).
///
/// `AdaptiveVoiceGate.defaultAbsoluteFloor` (0.006) was set from the built-in microphone. A quiet
/// microphone such as an Elgato Wave XLR peaks at 0.0045-0.0060 while the user speaks, so every hold
/// under `TranscriptionService.gateBypassDurationSeconds` was discarded as silence. One hold cannot tell
/// the built-in microphone's silence (ceiling ~0.0052) from the Wave XLR's speech, so the level comes from
/// the microphone's own history: the loudest frame of each of its last `maxPeaksPerDevice` successful holds,
/// keyed by input device name. With no history the floor is the default, which is today's behaviour.
struct InputVoiceLevelStore {

    static let defaultsKey = "inputVoiceLevels"
    static let maxPeaksPerDevice = 20
    /// Fraction of the median peak below which a frame is never voice.
    /// 0.25, not 0.5: on-device 2026-10-20 a learned Wave XLR peak of 0.0072 gave a 0.0036 floor and two spoken
    /// "Ja" (1.2-1.3 s, loudest frames 0.0036 and 0.0061) were discarded; a short word is quieter than a sentence's loudest frame.
    static let floorFactor: Float = 0.25
    /// Lower bound of the learned floor; the upper bound is `AdaptiveVoiceGate.defaultAbsoluteFloor`.
    static let minimumFloor: Float = 0.001

    private let defaults: UserDefaults

    init(defaults: UserDefaults = DicticusDefaults.suite) {
        self.defaults = defaults
    }

    /// `clamp(floorFactor x median(peaks), minimumFloor, defaultAbsoluteFloor)`; the default for no peaks.
    static func floor(fromPeaks peaks: [Float]) -> Float {
        guard !peaks.isEmpty else { return AdaptiveVoiceGate.defaultAbsoluteFloor }
        let sorted = peaks.sorted()
        let mid = sorted.count / 2
        let median = sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
        return min(max(floorFactor * median, minimumFloor), AdaptiveVoiceGate.defaultAbsoluteFloor)
    }

    /// A hold that restarted its engine or lost audio can contain another microphone's sound, so it never
    /// teaches the press device.
    static func isLearnable(restartCount: Int?, audioLost: Bool?) -> Bool {
        (restartCount ?? 0) == 0 && audioLost != true
    }

    func absoluteFloor(forDevice device: String?) -> Float {
        guard let device else { return AdaptiveVoiceGate.defaultAbsoluteFloor }
        return Self.floor(fromPeaks: peaks(forDevice: device))
    }

    func record(peak: Float, forDevice device: String?) {
        guard let device, Self.isTrackable(device), peak > 0, peak.isFinite else { return }
        var all = defaults.dictionary(forKey: Self.defaultsKey) as? [String: [Double]] ?? [:]
        var list = all[device] ?? []
        list.append(Double(peak))
        all[device] = Array(list.suffix(Self.maxPeaksPerDevice))
        defaults.set(all, forKey: Self.defaultsKey)
    }

    func peaks(forDevice device: String) -> [Float] {
        guard Self.isTrackable(device) else { return [] }
        let all = defaults.dictionary(forKey: Self.defaultsKey) as? [String: [Double]] ?? [:]
        return (all[device] ?? []).map { Float($0) }
    }

    private static func isTrackable(_ device: String) -> Bool {
        !device.isEmpty && device != "unknown"
    }
}
