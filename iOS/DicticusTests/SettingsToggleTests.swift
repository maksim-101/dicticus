import XCTest
@testable import Dicticus

/// Wave 0 scaffold — Settings toggle defaults & orthogonality (CLEAN-01, D-08, D-15).
///
/// The two toggles (`aiCleanupEnabled`, `useSwissGerman`) land in Wave 3 Settings UI,
/// but their persistence keys are defined here so Wave 3's view code + tests agree on
/// the key strings. These tests exercise the UserDefaults layer directly.
@MainActor
final class SettingsToggleTests: XCTestCase {

    /// Canonical keys — Wave 3 must use these exact strings in SettingsView/@AppStorage.
    static let aiCleanupKey = "aiCleanupEnabled"
    static let swissGermanKey = "useSwissGerman"
    static let suiteName = "group.com.dicticus"

    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        // 260724-9v8: use the same store the code under test writes to. Under
        // XCTest that is the bootstrap's ephemeral suite, never the real
        // group.com.dicticus domain.
        defaults = DicticusDefaults.suite
        defaults.removeObject(forKey: Self.aiCleanupKey)
        defaults.removeObject(forKey: Self.swissGermanKey)
        defaults.removeObject(forKey: "swissDefaultMigratedV2_1")
    }

    override func tearDown() async throws {
        defaults.removeObject(forKey: Self.aiCleanupKey)
        defaults.removeObject(forKey: Self.swissGermanKey)
        defaults.removeObject(forKey: "swissDefaultMigratedV2_1")
        try await super.tearDown()
    }

    // MARK: - D-08 / D-10: aiCleanupEnabled defaults OFF (LLM strictly opt-in)

    func testAiCleanupDefaultOff() {
        // D-10: plain (rules-only) cleanup is the default path and the LLM is
        // strictly opt-in — Phase 45 closed the sentence 2..N capitalization
        // gap deterministically so plain cleanup loses nothing relative to AI
        // cleanup, making this opt-in default free for the user. This test is
        // the flip-guard: if a future change registers a `true` default for
        // aiCleanupEnabled, it fails here first.
        let storedObject = defaults.object(forKey: Self.aiCleanupKey)
        XCTAssertNil(storedObject, "aiCleanupEnabled must have no stored value → toggle renders OFF")
        // `bool(forKey:)` returns false for missing keys — matches a @AppStorage default of `false`.
        XCTAssertFalse(defaults.bool(forKey: Self.aiCleanupKey))
    }

    // MARK: - D-A3: Migration tests (Phase 19.5)

    func testSwissGermanDefaultOnAfterMigration() {
        // Pre-migration: object is nil. Post-migration: object is true.
        // 260724-9v8: assert against DicticusDefaults.suite — the store
        // SwissDefaultMigration actually writes through (ephemeral under tests).
        let suite = DicticusDefaults.suite
        XCTAssertNil(suite.object(forKey: Self.swissGermanKey),
                     "Pre-migration the key must be unset")

        SwissDefaultMigration.runIfNeeded()

        XCTAssertNotNil(suite.object(forKey: Self.swissGermanKey),
                        "Migration must set useSwissGerman explicitly (D-A3)")
        XCTAssertTrue(suite.bool(forKey: Self.swissGermanKey),
                      "Default must be ON post-migration (D-A1)")
        XCTAssertTrue(suite.bool(forKey: "swissDefaultMigratedV2_1"),
                      "Migration flag must be set so subsequent runs are no-ops")
    }

    func testMigrationIsIdempotent() {
        let suite = UserDefaults(suiteName: Self.suiteName) ?? .standard
        SwissDefaultMigration.runIfNeeded()
        // User flips OFF after migration.
        suite.set(false, forKey: Self.swissGermanKey)
        // Second run must NOT re-flip — respects user choice.
        SwissDefaultMigration.runIfNeeded()
        XCTAssertFalse(suite.bool(forKey: Self.swissGermanKey),
                       "Migration must not overwrite the user's later opt-out")
    }

    func testMigrationDoesNotOverwriteExplicitFalse() {
        let suite = UserDefaults(suiteName: Self.suiteName) ?? .standard
        // User explicitly set OFF before migration ever ran.
        suite.set(false, forKey: Self.swissGermanKey)
        // Migration runs.
        SwissDefaultMigration.runIfNeeded()
        // The migration only writes when the key is unset; an explicit false stays false.
        XCTAssertFalse(suite.bool(forKey: Self.swissGermanKey),
                       "Migration must not overwrite an explicit pre-migration OFF")
    }

    // MARK: - Toggles are orthogonal (D-15: independent keys)

    func testTogglesAreOrthogonal() {
        defaults.set(true, forKey: Self.aiCleanupKey)
        XCTAssertTrue(defaults.bool(forKey: Self.aiCleanupKey))
        XCTAssertFalse(defaults.bool(forKey: Self.swissGermanKey),
                       "Setting aiCleanupEnabled must NOT mutate useSwissGerman")

        defaults.removeObject(forKey: Self.aiCleanupKey)
        defaults.set(true, forKey: Self.swissGermanKey)
        XCTAssertTrue(defaults.bool(forKey: Self.swissGermanKey))
        XCTAssertFalse(defaults.bool(forKey: Self.aiCleanupKey),
                       "Setting useSwissGerman must NOT mutate aiCleanupEnabled")
    }

    // MARK: - Both keys can coexist ON

    func testBothTogglesCanBeOnSimultaneously() {
        defaults.set(true, forKey: Self.aiCleanupKey)
        defaults.set(true, forKey: Self.swissGermanKey)
        XCTAssertTrue(defaults.bool(forKey: Self.aiCleanupKey))
        XCTAssertTrue(defaults.bool(forKey: Self.swissGermanKey))
    }
}
