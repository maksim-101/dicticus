import XCTest
@testable import Dicticus

/// Phase 37 Plan 02 — Task 1 (D-05): pure decision-function coverage for the
/// cellular-vs-Wi-Fi download warning. Exercises
/// `IOSModelWarmupService.shouldWarnBeforeCellularDownload(isExpensive:isConstrained:)`
/// directly against the four `NWPath` flag combinations — no `NWPathMonitor`
/// instantiation needed, since the function is a pure static computation.
final class CellularDownloadWarningTests: XCTestCase {

    func testWarnsWhenExpensiveAndNotConstrained() {
        XCTAssertTrue(
            IOSModelWarmupService.shouldWarnBeforeCellularDownload(isExpensive: true, isConstrained: false)
        )
    }

    func testWarnsWhenConstrainedAndNotExpensive() {
        XCTAssertTrue(
            IOSModelWarmupService.shouldWarnBeforeCellularDownload(isExpensive: false, isConstrained: true)
        )
    }

    func testWarnsWhenBothExpensiveAndConstrained() {
        XCTAssertTrue(
            IOSModelWarmupService.shouldWarnBeforeCellularDownload(isExpensive: true, isConstrained: true)
        )
    }

    func testDoesNotWarnOnWiFiUnconstrained() {
        XCTAssertFalse(
            IOSModelWarmupService.shouldWarnBeforeCellularDownload(isExpensive: false, isConstrained: false)
        )
    }
}
