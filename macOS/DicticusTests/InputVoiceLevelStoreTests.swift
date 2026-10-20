import XCTest
@testable import Dicticus

// Quick task 261020-dvf: the per-microphone absolute floor of the Layer 2 gate. The store runs on a
// throwaway defaults suite that tearDown removes; UserDefaults.standard is never touched.
final class InputVoiceLevelStoreTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: InputVoiceLevelStore!

    override func setUpWithError() throws {
        suiteName = "dvf-tests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        store = InputVoiceLevelStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    // Frames shaped like a logged Wave XLR hold (1.0 s): noise floor 0.0009, speech 0.003-0.0058.
    private static let waveXlrFrames: [Float] = [0.0009, 0.0009, 0.0031, 0.0042, 0.0058, 0.0050, 0.0036, 0.0029, 0.0012, 0.0010]
    // A MacBook silent tap (0.8 s): noise floor 0.0005, loudest frame 0.0056.
    private static let macBookSilentTap: [Float] = [0.0005, 0.0005, 0.0021, 0.0035, 0.0056, 0.0040, 0.0018, 0.0009]

    // MARK: - floor(fromPeaks:)

    func testNoHistoryKeepsTheDefaultFloor() {
        XCTAssertEqual(InputVoiceLevelStore.floor(fromPeaks: []), AdaptiveVoiceGate.defaultAbsoluteFloor)
        XCTAssertEqual(AdaptiveVoiceGate.defaultAbsoluteFloor, 0.006)
    }

    func testLoudMicrophoneStaysAtTheDefaultFloor() {
        XCTAssertEqual(InputVoiceLevelStore.floor(fromPeaks: [0.04, 0.05]), 0.006)
    }

    func testQuietMicrophoneLearnsAQuarterOfItsPeak() {
        XCTAssertEqual(InputVoiceLevelStore.floor(fromPeaks: [0.0053]), 0.001325, accuracy: 1e-7)
    }

    func testFloorNeverFallsBelowTheMinimum() {
        XCTAssertEqual(InputVoiceLevelStore.floor(fromPeaks: [0.0001]), 0.001)
    }

    func testMedianOfAnOddList() {
        XCTAssertEqual(InputVoiceLevelStore.floor(fromPeaks: [0.0090, 0.0040, 0.0050]), 0.00125, accuracy: 1e-7)
    }

    func testMedianOfAnEvenListAveragesTheMiddlePair() {
        XCTAssertEqual(InputVoiceLevelStore.floor(fromPeaks: [0.0060, 0.0020, 0.0040, 0.0100]), 0.00125, accuracy: 1e-7)
    }

    func testOneLoudOutlierDoesNotMoveTheFloor() {
        let peaks = Array(repeating: Float(0.005), count: 19) + [0.2]
        XCTAssertEqual(InputVoiceLevelStore.floor(fromPeaks: peaks), 0.00125, accuracy: 1e-7)
    }

    // MARK: - Store

    func testRecordKeepsTheLastTwenty() {
        for i in 1...25 { store.record(peak: Float(i) / 1000, forDevice: "Elgato Wave XLR") }
        let kept = store.peaks(forDevice: "Elgato Wave XLR")
        XCTAssertEqual(kept.count, 20)
        XCTAssertEqual(kept.first ?? 0, 0.006, accuracy: 1e-7)
        XCTAssertEqual(kept.last ?? 0, 0.025, accuracy: 1e-7)
    }

    func testDevicesAreIndependent() {
        store.record(peak: 0.0053, forDevice: "Elgato Wave XLR")
        store.record(peak: 0.05, forDevice: "MacBook Pro Microphone")
        XCTAssertEqual(store.absoluteFloor(forDevice: "Elgato Wave XLR"), 0.001325, accuracy: 1e-7)
        XCTAssertEqual(store.absoluteFloor(forDevice: "MacBook Pro Microphone"), 0.006)
        XCTAssertEqual(store.absoluteFloor(forDevice: "AirPods"), 0.006)
    }

    func testUnknownEmptyAndNilDevicesAreIgnored() {
        store.record(peak: 0.0053, forDevice: "unknown")
        store.record(peak: 0.0053, forDevice: "")
        store.record(peak: 0.0053, forDevice: nil)
        XCTAssertNil(defaults.dictionary(forKey: InputVoiceLevelStore.defaultsKey))
        XCTAssertEqual(store.absoluteFloor(forDevice: "unknown"), 0.006)
        XCTAssertEqual(store.absoluteFloor(forDevice: nil), 0.006)
    }

    func testNonPositiveAndNonFinitePeaksAreIgnored() {
        store.record(peak: 0, forDevice: "Elgato Wave XLR")
        store.record(peak: -0.1, forDevice: "Elgato Wave XLR")
        store.record(peak: .nan, forDevice: "Elgato Wave XLR")
        store.record(peak: .infinity, forDevice: "Elgato Wave XLR")
        XCTAssertEqual(store.peaks(forDevice: "Elgato Wave XLR"), [])
    }

    func testHistorySurvivesANewStoreOnTheSameSuite() throws {
        store.record(peak: 0.0053, forDevice: "Elgato Wave XLR")
        store.record(peak: 0.0047, forDevice: "Elgato Wave XLR")
        let reopened = InputVoiceLevelStore(defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)))
        XCTAssertEqual(reopened.peaks(forDevice: "Elgato Wave XLR"), [0.0053, 0.0047])
        XCTAssertEqual(reopened.absoluteFloor(forDevice: "Elgato Wave XLR"), 0.00125, accuracy: 1e-7)
    }

    func testOnlyAHoldWithoutRestartsOrLostAudioIsLearnable() {
        XCTAssertTrue(InputVoiceLevelStore.isLearnable(restartCount: 0, audioLost: false))
        XCTAssertTrue(InputVoiceLevelStore.isLearnable(restartCount: nil, audioLost: nil))
        XCTAssertFalse(InputVoiceLevelStore.isLearnable(restartCount: 1, audioLost: false))
        XCTAssertFalse(InputVoiceLevelStore.isLearnable(restartCount: 0, audioLost: true))
    }

    // MARK: - Gate decisions with the learned floor

    func testShortWaveXlrHoldIsVoiceOnceTheMicrophoneIsLearned() {
        store.record(peak: 0.0053, forDevice: "Elgato Wave XLR")
        let learned = AdaptiveVoiceGate.evaluate(
            frameEnergies: Self.waveXlrFrames, absoluteFloor: store.absoluteFloor(forDevice: "Elgato Wave XLR"))
        XCTAssertTrue(learned.voiceDetected)
        XCTAssertEqual(learned.threshold, 0.0009 * AdaptiveVoiceGate.defaultNoiseRatio, accuracy: 1e-6)
        XCTAssertGreaterThan(learned.framesAboveThreshold(in: Self.waveXlrFrames), AdaptiveVoiceGate.nearSilentMaxVoicedFrames)
    }

    func testMedianPeakOfTwoWaveHoldsGivesAQuarter() {
        XCTAssertEqual(InputVoiceLevelStore.floor(fromPeaks: [0.0040, 0.0060]), 0.00125, accuracy: 1e-7)
    }

    func testMacBookPeaksStayCappedAtTheDefaultFloor() {
        XCTAssertEqual(InputVoiceLevelStore.floor(fromPeaks: [0.035, 0.04, 0.05, 0.09, 0.04]), 0.006)
    }

    // A spoken "Ja" on the Wave XLR (1.2 s, 12 frames): loudest frame 0.0036, learned peak 0.0072.
    func testShortJaOnWaveXlrIsVoiceWithTheLearnedFloor() {
        let ja: [Float] = [0.0005, 0.0005, 0.0005, 0.0005, 0.0018, 0.0026, 0.0036, 0.0030, 0.0022, 0.0005, 0.0005, 0.0005]
        store.record(peak: 0.0072, forDevice: "Elgato Wave XLR")
        let decision = AdaptiveVoiceGate.evaluate(
            frameEnergies: ja, absoluteFloor: store.absoluteFloor(forDevice: "Elgato Wave XLR"))
        XCTAssertTrue(decision.voiceDetected)
        XCTAssertGreaterThanOrEqual(decision.framesAboveThreshold(in: ja), 3)
    }

    func testShortWaveXlrHoldWithoutHistoryIsStillDiscarded() {
        let cold = AdaptiveVoiceGate.evaluate(
            frameEnergies: Self.waveXlrFrames, absoluteFloor: store.absoluteFloor(forDevice: "Elgato Wave XLR"))
        XCTAssertFalse(cold.voiceDetected)
        XCTAssertEqual(cold.threshold, 0.006)
    }

    func testMacBookSilentTapStaysDiscardedWithMacBookHistory() {
        for peak: Float in [0.035, 0.04, 0.05, 0.09, 0.04] { store.record(peak: peak, forDevice: "MacBook Pro Microphone") }
        let decision = AdaptiveVoiceGate.evaluate(
            frameEnergies: Self.macBookSilentTap, absoluteFloor: store.absoluteFloor(forDevice: "MacBook Pro Microphone"))
        XCTAssertFalse(decision.voiceDetected)
        XCTAssertEqual(decision.threshold, 0.006)
    }

    // MARK: - Near-silent short-clip rule

    func testNearSilentRuleAppliesAtAndAboveTheDefaultFloor() {
        XCTAssertTrue(InputVoiceLevelStore.appliesNearSilentRule(absoluteFloor: 0.006))
    }

    func testNearSilentRuleSkippedBelowTheDefaultFloor() {
        XCTAssertFalse(InputVoiceLevelStore.appliesNearSilentRule(absoluteFloor: 0.0016))
    }

    func testNearSilentRuleAppliesOnColdStart() {
        XCTAssertTrue(InputVoiceLevelStore.appliesNearSilentRule(absoluteFloor: store.absoluteFloor(forDevice: "Elgato Wave XLR")))
    }

    func testNearSilentRuleAppliesOnALearnedMacBook() {
        for peak: Float in [0.035, 0.04, 0.05, 0.09, 0.04] { store.record(peak: peak, forDevice: "MacBook Pro Microphone") }
        XCTAssertTrue(InputVoiceLevelStore.appliesNearSilentRule(absoluteFloor: store.absoluteFloor(forDevice: "MacBook Pro Microphone")))
    }

    func testNearSilentRuleSkippedOnALearnedWaveXlr() {
        store.record(peak: 0.0072, forDevice: "Elgato Wave XLR")
        XCTAssertFalse(InputVoiceLevelStore.appliesNearSilentRule(absoluteFloor: store.absoluteFloor(forDevice: "Elgato Wave XLR")))
    }
}
