import XCTest
@testable import Dicticus

/// Phase 20.05 ACT-3-VISIBILITY — CleanupCopyMode UserDefaults round-trip.
///
/// Verifies the cross-platform Copy-mode default key (`cleanupCopyMode`) defaults
/// to `.raw` on first read (per CONTEXT.md decision — default Raw until LLM trust
/// is rebuilt) and round-trips through the standard UserDefaults suite. Both iOS
/// and macOS Settings UIs and per-row Copy buttons read the same key.
final class CleanupCopyModeTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: CleanupCopyMode.userDefaultsKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: CleanupCopyMode.userDefaultsKey)
        super.tearDown()
    }

    func testDefaultsToRaw() {
        XCTAssertEqual(CleanupCopyMode.current, .raw,
                       "Missing key must resolve to .raw per CONTEXT.md (default Raw until LLM trust rebuilt)")
    }

    func testSetterPersists() {
        CleanupCopyMode.current = .polished
        XCTAssertEqual(UserDefaults.standard.string(forKey: CleanupCopyMode.userDefaultsKey), "polished")
        XCTAssertEqual(CleanupCopyMode.current, .polished)
    }

    func testRoundTripBothValues() {
        CleanupCopyMode.current = .polished
        XCTAssertEqual(CleanupCopyMode.current, .polished)
        CleanupCopyMode.current = .raw
        XCTAssertEqual(CleanupCopyMode.current, .raw)
    }

    func testCorruptValueResolvesToRaw() {
        UserDefaults.standard.set("garbage", forKey: CleanupCopyMode.userDefaultsKey)
        XCTAssertEqual(CleanupCopyMode.current, .raw,
                       "Unknown stored value must fall back to .raw — never trap")
    }

    func testUserDefaultsKeyIsCanonical() {
        XCTAssertEqual(CleanupCopyMode.userDefaultsKey, "cleanupCopyMode",
                       "Key string is canonical — both Settings UIs and Copy buttons depend on it")
    }
}
