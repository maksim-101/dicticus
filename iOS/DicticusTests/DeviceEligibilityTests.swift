import XCTest
@testable import Dicticus

/// Wave 0 scaffold — RAM eligibility gating for AI cleanup (D-03).
///
/// D-03: devices with < 5 GB physical RAM must have the AI cleanup toggle
/// disabled/hidden. Wave 2 adds `IOSModelWarmupService.isAiCleanupSupported`
/// and a `ramThreshold` constant. Until then, this scaffold exercises the raw
/// `ProcessInfo.physicalMemory` read + documents the threshold contract.
@MainActor
final class DeviceEligibilityTests: XCTestCase {

    /// Wave 2 ready — `IOSModelWarmupService.requiredPhysicalMemoryBytes` +
    /// `isAiCleanupSupported` landed in 19-03.
    private let isWave2Ready = true

    /// D-03: cutoff is 5 GB. Mirrored by the implementation as
    /// `IOSModelWarmupService.requiredPhysicalMemoryBytes`.
    static let expectedRamThresholdBytes: UInt64 = 5 * 1024 * 1024 * 1024

    // MARK: - D-03: Threshold constant contract

    func testRamThresholdConstantIsFiveGb() throws {
        try XCTSkipIf(!isWave2Ready,
                      "Pending Wave 2: IOSModelWarmupService.requiredPhysicalMemoryBytes not yet exposed")
        XCTAssertEqual(IOSModelWarmupService.requiredPhysicalMemoryBytes,
                       Self.expectedRamThresholdBytes,
                       "D-03: threshold must be exactly 5 GiB")
    }

    // MARK: - D-03: Runtime eligibility on current device

    func testIsAiCleanupSupportedOnCurrentDevice() throws {
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        try XCTSkipIf(physicalMemory < Self.expectedRamThresholdBytes,
                      "Simulator/device has < 5 GB RAM — eligibility test intentionally skipped")
        try XCTSkipIf(!isWave2Ready,
                      "Pending Wave 2: IOSModelWarmupService.isAiCleanupSupported not yet implemented")
        XCTAssertTrue(IOSModelWarmupService.isAiCleanupSupported,
                      "Device with \(physicalMemory) bytes physicalMemory should be supported")
        // Cross-check against the raw ProcessInfo read (behavioral parity).
        XCTAssertEqual(
            IOSModelWarmupService.isAiCleanupSupported,
            ProcessInfo.processInfo.physicalMemory >= IOSModelWarmupService.requiredPhysicalMemoryBytes
        )
    }

    // MARK: - Sanity: ProcessInfo exposes physicalMemory

    func testPhysicalMemoryIsReadable() {
        let mem = ProcessInfo.processInfo.physicalMemory
        XCTAssertGreaterThan(mem, 0, "physicalMemory must be readable for D-03 gating")
    }
}
