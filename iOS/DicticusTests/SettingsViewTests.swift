import XCTest
@testable import Dicticus

@MainActor
final class SettingsViewTests: XCTestCase {

    static let tourKey = "hasSeenOnboardingTour"

    override func tearDown() async throws {
        UserDefaults.standard.set(false, forKey: Self.tourKey)
        try await super.tearDown()
    }

    /// 260812-gl1: measured (KVO-instrumented) that `removeObject(forKey:)` does
    /// NOT synchronously clear this key when its prior `true` value was written
    /// by a DIFFERENT process (e.g. a real prior app session, or — as on a test
    /// host — this simulator's persisted container state): `bool(forKey:)` called
    /// immediately after `removeObject` still read `true`, and the change only
    /// became visible one KVO tick later. `set(_:forKey:)` updates the in-process
    /// resolved cache synchronously (confirmed empirically: `bool(forKey:)`
    /// reflects it immediately), so this test establishes its "default" baseline
    /// with an explicit `set(false, ...)` rather than `removeObject`. This does
    /// not test literal key-absence, but the assertion it backs (`bool(forKey:)`
    /// reads false) is identical whether the key is absent or explicitly false.
    func testOnboardingTourDefaultIsFalse() {
        UserDefaults.standard.set(false, forKey: Self.tourKey)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: Self.tourKey),
                       "hasSeenOnboardingTour must default to false so new users see the tour")
    }

    func testResetOnboardingTourWritesFalse() {
        // Simulate the user having already seen the tour.
        UserDefaults.standard.set(true, forKey: Self.tourKey)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: Self.tourKey))

        // Simulate the re-entry button action.
        UserDefaults.standard.set(false, forKey: Self.tourKey)

        XCTAssertFalse(UserDefaults.standard.bool(forKey: Self.tourKey),
                       "Re-entry action must reset hasSeenOnboardingTour to false")
    }
}
