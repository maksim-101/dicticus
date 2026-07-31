import XCTest
@testable import Dicticus

/// Regression lock for the 2026-07-19 dictionary data-loss incident: a relaunch
/// where `load()` returned empty (present-but-unreadable blob, a cfprefsd race)
/// let the seed path overwrite 205 real entries with 95 bundled defaults. The
/// fix — `DictionaryService.loadGuarded` — must report `suppressSeed == true`
/// for the present-but-unreadable case so the caller never seeds over real data,
/// while still allowing a genuine first-run seed. Pure/injectable so this is a
/// true unit test, no singleton or on-disk state involved.
final class DictionaryDataLossGuardTests: XCTestCase {

    private let key = "customDictionaryMetadata"

    private func tempDefaults() -> UserDefaults {
        InMemoryUserDefaults()
    }

    /// A valid persisted dictionary must be loaded, NOT flagged for suppression.
    func testValidBlobLoadsAndDoesNotSuppress() {
        let d = tempDefaults()
        let entries = ["cell card": DictionaryMetadata(replacement: "Cellguard", createdAt: Date(), source: .imported)]
        d.set(try! JSONEncoder().encode(entries), forKey: key)

        let out = DictionaryService.loadGuarded(from: d, key: key)

        XCTAssertFalse(out.suppressSeed)
        XCTAssertEqual(out.dictionary["cell card"]?.replacement, "Cellguard")
    }

    /// THE incident shape: a blob is present but cannot be decoded. The guard
    /// MUST suppress the seed so a caller never overwrites the real (unreadable
    /// this instant) dictionary with defaults.
    func testPresentButUnreadableBlobSuppressesSeed() {
        let d = tempDefaults()
        d.set(Data([0x00, 0x01, 0x02, 0x03]), forKey: key)  // present, not decodable

        let out = DictionaryService.loadGuarded(from: d, key: key)

        XCTAssertTrue(out.suppressSeed, "present-but-unreadable dictionary must suppress the seed-and-overwrite")
        XCTAssertTrue(out.dictionary.isEmpty)
    }

    /// A genuine first run (no blob at all) must allow seeding.
    func testAbsentBlobIsSafeFirstRun() {
        let d = tempDefaults()  // nothing stored

        let out = DictionaryService.loadGuarded(from: d, key: key)

        XCTAssertFalse(out.suppressSeed, "genuine first run (no persisted blob) must allow seeding")
        XCTAssertTrue(out.dictionary.isEmpty)
    }
}
