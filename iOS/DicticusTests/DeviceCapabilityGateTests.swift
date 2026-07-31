import XCTest
@testable import Dicticus

// Pure-logic tests for the WHISP-05 runtime device-floor gate. Drives
// DeviceCapabilityGate.isSupportedDevice(identifier:) directly over
// device-identifier strings (e.g. "iPhone15,4") — no WhisperKit import,
// no live device inspection required. RED until 41-07 lands the symbol.
final class DeviceCapabilityGateTests: XCTestCase {

    // iPhone 13 family (A15) — below the supported floor.
    func testIPhone14GenerationIsBlocked() {
        XCTAssertFalse(
            DeviceCapabilityGate.isSupportedDevice(identifier: "iPhone14,2"),
            "iPhone14,2 (iPhone 13 Pro, A15) is below the WHISP-05 device floor and must be blocked"
        )
    }

    // iPhone 14 family (A15) — below the supported floor.
    func testIPhone14FamilySecondIdentifierIsBlocked() {
        XCTAssertFalse(
            DeviceCapabilityGate.isSupportedDevice(identifier: "iPhone14,7"),
            "iPhone14,7 (iPhone 14, A15) is below the WHISP-05 device floor and must be blocked"
        )
    }

    // iPhone 15 family (A16+) — at the supported floor, must be allowed.
    func testIPhone15FamilyIsAllowed() {
        XCTAssertTrue(
            DeviceCapabilityGate.isSupportedDevice(identifier: "iPhone15,4"),
            "iPhone15,4 (iPhone 15, A16) is at the WHISP-05 device floor and must be allowed"
        )
    }

    // iPhone 16 family (A17+) — above the supported floor, must be allowed.
    func testIPhone16FamilyIsAllowed() {
        XCTAssertTrue(
            DeviceCapabilityGate.isSupportedDevice(identifier: "iPhone16,1"),
            "iPhone16,1 (iPhone 15 Pro, A17 Pro) is above the WHISP-05 device floor and must be allowed"
        )
    }

    // Unknown future device family — forward-compatible default is to allow,
    // since a device newer than any identifier this gate knows about is
    // assumed to exceed the performance floor.
    func testUnknownFutureDeviceIsAllowedByDefault() {
        XCTAssertTrue(
            DeviceCapabilityGate.isSupportedDevice(identifier: "iPhone99,1"),
            "An unrecognized future device identifier should be allowed (forward-compatible default)"
        )
    }
}
