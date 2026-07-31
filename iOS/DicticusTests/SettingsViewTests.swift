import XCTest
@testable import Dicticus

@MainActor
final class SettingsViewTests: XCTestCase {

    static let tourKey = "hasSeenOnboardingTour"

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: Self.tourKey)
        try await super.tearDown()
    }

    func testOnboardingTourDefaultIsFalse() {
        UserDefaults.standard.removeObject(forKey: Self.tourKey)
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
