import WhisperKit

/// Runtime device-capability gate enforcing the iPhone 15+ (A16) hardware floor
/// required to run WhisperKit large-v3-turbo reliably on-device (WHISP-05).
///
/// MECHANISM DEVIATION from CONTEXT D-04: no native Info.plist / App Store Connect
/// key gates specifically to iPhone 15+ — the only performance-tier key,
/// `iphone-ipad-minimum-performance-a12`, is four chip generations too permissive
/// (41-RESEARCH.md Pitfall 3). This runtime check preserves the INTENT (iPhone 15+
/// only, because A15 OOMs Whisper large-v3-turbo) until Phase 37 (iOS Distribution,
/// currently HELD) revisits fine-grained App Store enforcement.
///
/// Mirrors the `nonisolated static` shape of
/// `IOSModelWarmupService.isAiCleanupSupported` (a parallel RAM-based runtime gate) —
/// this gate checks the device identifier (chip generation) instead of RAM.
enum DeviceCapabilityGate {

    /// Pure predicate over a raw device-identifier string (e.g. "iPhone15,4"), as
    /// returned by `WhisperKit.deviceName()` (the same `uname`/`ProcessInfo.hwModel`
    /// derivation WhisperKit itself uses for its own device-tier tables — see
    /// `ModelUtilities.modelSupport(for:)`, 41-RESEARCH.md Don't-Hand-Roll).
    ///
    /// Parses the `iPhoneMAJOR,MINOR` shape and allows MAJOR >= 15 (iPhone 15 family
    /// and later). Non-iPhone identifiers — iPad, Mac (simulator's `ProcessInfo.hwModel`
    /// reports the host Mac model), or any unparseable/unknown string — are allowed by
    /// default: forward-compatible for future device families and simulator-friendly
    /// for UI work.
    static func isSupportedDevice(identifier: String) -> Bool {
        guard identifier.hasPrefix("iPhone") else { return true }
        let suffix = identifier.dropFirst("iPhone".count)
        guard let majorString = suffix.split(separator: ",").first,
              let major = Int(majorString) else {
            return true
        }
        return major >= 15
    }

    /// Whether the current device meets the WHISP-05 iPhone 15+ floor.
    /// `nonisolated` so it can be read at launch (e.g. from `DicticusApp`'s root
    /// view branch) without actor hops, mirroring `isAiCleanupSupported`.
    nonisolated static var isCurrentDeviceSupported: Bool {
        isSupportedDevice(identifier: WhisperKit.deviceName())
    }
}
