import XCTest
@testable import Dicticus

/// Phase 46-05: exact-string display-contract tests for the pending-recordings UI
/// surface. `durationLabel`/`statusLabel` (Task 1) and `PendingQueueChip.label(for:)`/
/// `PendingRecordingStore.pendingCount` (Task 2) are pure functions precisely so this
/// contract is machine-checked rather than eyeballed.
final class PendingSurfaceTests: XCTestCase {

    // MARK: - PendingRecordingRow.durationLabel

    func testDurationLabelNilReturnsPlaceholder() {
        XCTAssertEqual(PendingRecordingRow.durationLabel(nil), "--:--")
    }

    func testDurationLabelZeroIsDistinguishableFromNil() {
        let zero = PendingRecordingRow.durationLabel(0)
        let nilLabel = PendingRecordingRow.durationLabel(nil)
        XCTAssertNotEqual(zero, nilLabel, "a real zero-length recording and an unknown duration must be distinguishable")
        XCTAssertEqual(zero, "0:00")
    }

    func testDurationLabelKnownValues() {
        XCTAssertEqual(PendingRecordingRow.durationLabel(42), "0:42")
        XCTAssertEqual(PendingRecordingRow.durationLabel(67), "1:07")
    }

    func testDurationLabelFractionalSecond() {
        // Truncates to whole seconds — a fractional value still renders a valid m:ss.
        XCTAssertEqual(PendingRecordingRow.durationLabel(0.7), "0:00")
    }

    func testDurationLabelExactlySixtySeconds() {
        XCTAssertEqual(PendingRecordingRow.durationLabel(60), "1:00")
    }

    func testDurationLabelOverAnHour() {
        // 62 minutes, 5 seconds — minutes are not clamped to 59.
        XCTAssertEqual(PendingRecordingRow.durationLabel(3725), "62:05")
    }

    func testDurationLabelInfinityReturnsPlaceholder() {
        XCTAssertEqual(PendingRecordingRow.durationLabel(.infinity), "--:--")
    }

    func testDurationLabelNegativeReturnsPlaceholder() {
        XCTAssertEqual(PendingRecordingRow.durationLabel(-5), "--:--")
    }

    // MARK: - PendingRecordingRow.statusLabel

    func testStatusLabelQueued() {
        XCTAssertEqual(PendingRecordingRow.statusLabel(for: .queued), "Waiting for model")
    }

    func testStatusLabelTranscribing() {
        XCTAssertEqual(PendingRecordingRow.statusLabel(for: .transcribing), "Transcribing\u{2026}")
    }

    func testStatusLabelFailed() {
        XCTAssertEqual(PendingRecordingRow.statusLabel(for: .failed), "Failed")
    }
}
