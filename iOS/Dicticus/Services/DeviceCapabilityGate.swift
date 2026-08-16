import Foundation

/// Runtime device-capability gate enforcing the iPhone 15+ (A16) hardware floor
/// required to run the ASR engine reliably on-device (WHISP-05). Phase 47.1 (D-03):
/// the floor is kept unchanged across the WhisperKit -> FluidAudio/Parakeet engine
/// swap by explicit user decision, even though Parakeet's ~36 MB footprint no longer
/// technically requires it.
///
/// MECHANISM DEVIATION from CONTEXT D-04: no native Info.plist / App Store Connect
/// key gates specifically to iPhone 15+ — the only performance-tier key,
/// `iphone-ipad-minimum-performance-a12`, is four chip generations too permissive
/// (41-RESEARCH.md Pitfall 3). This runtime check preserves the INTENT (iPhone 15+
/// only) until Phase 37 (iOS Distribution, currently HELD) revisits fine-grained
/// App Store enforcement.
///
/// Mirrors the `nonisolated static` shape of
/// `IOSModelWarmupService.isAiCleanupSupported` (a parallel RAM-based runtime gate) —
/// this gate checks the device identifier (chip generation) instead of RAM.
enum DeviceCapabilityGate {

    /// Pure predicate over a raw device-identifier string (e.g. "iPhone15,4"), as
    /// returned by `deviceName()` below. Byte-identical to the pre-47.1 WhisperKit-era
    /// logic (D-03) — only the identifier's SOURCE changed (inlined uname()/utsname
    /// read instead of `WhisperKit.deviceName()`, since WhisperKit is no longer linked
    /// on iOS).
    ///
    /// Parses the `iPhoneMAJOR,MINOR` shape and allows MAJOR >= 15 (iPhone 15 family
    /// and later). Non-iPhone identifiers — iPad, Mac (simulator's placeholder reports
    /// a non-"iPhone"-prefixed string), or any unparseable/unknown string — are allowed
    /// by default: forward-compatible for future device families and simulator-friendly
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

    /// Real-device identifier string (e.g. "iPhone15,4"), inlined verbatim from
    /// WhisperKit's own `deviceName()` implementation (argmax-oss-swift
    /// `Sources/WhisperKit/Core/WhisperKit.swift:141-154`, read directly this session
    /// per 47.1-RESEARCH.md Pitfall 1) now that WhisperKit is no longer linked on iOS.
    /// The `#else` (Mac/Simulator) branch uses a literal placeholder — `isSupportedDevice`
    /// above already allows any non-"iPhone"-prefixed string, so the exact placeholder
    /// value doesn't affect gate correctness (RESEARCH Assumption A1).
    private static func deviceName() -> String {
        #if !os(macOS) && !targetEnvironment(simulator)
        var sysinfo = utsname()
        uname(&sysinfo)
        let deviceName = withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) {
                String(cString: $0)
            }
        }
        #else
        let deviceName = "simulator"
        #endif
        return deviceName
    }

    /// Whether the current device meets the WHISP-05 iPhone 15+ floor.
    /// `nonisolated` so it can be read at launch (e.g. from `DicticusApp`'s root
    /// view branch) without actor hops, mirroring `isAiCleanupSupported`.
    nonisolated static var isCurrentDeviceSupported: Bool {
        isSupportedDevice(identifier: deviceName())
    }
}
