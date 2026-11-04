import XCTest
@testable import Dicticus

/// Covers the AI Cleanup memory gate, `IOSModelWarmupService.isAiCleanupSupported`.
/// Devices below 6.5 GiB of reported memory get the explainer row instead of the toggle (261104-8k2).
@MainActor
final class DeviceEligibilityTests: XCTestCase {

    /// Wave 2 ready — `IOSModelWarmupService.requiredPhysicalMemoryBytes` +
    /// `isAiCleanupSupported` landed in 19-03.
    private let isWave2Ready = true

    /// 6.5 GiB, written out so the test does not restate the implementation's expression.
    static let expectedRamThresholdBytes: UInt64 = 6_979_321_856

    private static let gib: UInt64 = 1_073_741_824

    // MARK: - D-03: Threshold constant contract

    func testRamThresholdConstantIsSixAndAHalfGiB() throws {
        try XCTSkipIf(!isWave2Ready,
                      "Pending Wave 2: IOSModelWarmupService.requiredPhysicalMemoryBytes not yet exposed")
        XCTAssertEqual(IOSModelWarmupService.requiredPhysicalMemoryBytes,
                       Self.expectedRamThresholdBytes,
                       "threshold must be exactly 6.5 GiB")
    }

    // MARK: - Boundary cases of the pure predicate

    func testAiCleanupGateRejectsFourGiB() {
        XCTAssertFalse(IOSModelWarmupService.isAiCleanupSupported(physicalMemory: 4 * Self.gib),
                       "a 4 GB device must not offer AI Cleanup")
    }

    func testAiCleanupGateRejectsSixGiB() {
        XCTAssertFalse(IOSModelWarmupService.isAiCleanupSupported(physicalMemory: 6 * Self.gib),
                       "a 6 GB device must not offer AI Cleanup")
    }

    func testAiCleanupGateAdmitsSevenAndAHalfGiB() {
        XCTAssertTrue(IOSModelWarmupService.isAiCleanupSupported(physicalMemory: 15 * Self.gib / 2),
                      "an 8 GB device reporting 7.5 GiB must pass")
    }

    func testAiCleanupGateAdmitsEightGiB() {
        XCTAssertTrue(IOSModelWarmupService.isAiCleanupSupported(physicalMemory: 8 * Self.gib),
                      "an 8 GB device reporting 8 GiB must pass")
    }

    // MARK: - Settings explainer

    func testUnavailableMessageRoundsMemoryToWholeGB() {
        XCTAssertEqual(
            IOSModelWarmupService.aiCleanupUnavailableMessage(physicalMemory: 6_000_000_000),
            "AI Cleanup needs a device with 8 GB of memory. This one has about 6 GB.")
        XCTAssertEqual(
            IOSModelWarmupService.aiCleanupUnavailableMessage(physicalMemory: 3_900_000_000),
            "AI Cleanup needs a device with 8 GB of memory. This one has about 4 GB.")
    }

    // MARK: - D-03: Runtime eligibility on current device

    func testIsAiCleanupSupportedOnCurrentDevice() throws {
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        try XCTSkipIf(physicalMemory < Self.expectedRamThresholdBytes,
                      "Simulator/device reports less than 6.5 GiB — eligibility test intentionally skipped")
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
