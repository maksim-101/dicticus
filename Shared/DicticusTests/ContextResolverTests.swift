import XCTest
@testable import Dicticus

/// Phase 38 Plan 01 (D-02/D-05/D-06, CTXFMT-01/CTXFMT-02), slice 54: `ContextResolver`
/// — pure (bundle ID, declared category) → `DictationContext` resolution. Proves the
/// 6-level precedence chain (disabled short-circuit → pin → override → developer-tools
/// category → terminal fallback → default).
final class ContextResolverTests: XCTestCase {

    private let devTools = ContextResolver.developerToolsCategory

    // MARK: - Category rule and terminal fallback

    func testDeveloperToolsCategoryResolvesToCodeForAnyBundleID() {
        for bundleID in ["dev.warp.Warp-Stable", "com.stablyai.orca", "com.example.new-editor"] {
            XCTAssertEqual(
                ContextResolver.resolve(bundleID: bundleID, category: devTools), .code,
                "\(bundleID) declaring developer-tools must resolve to .code without a list entry"
            )
        }
    }

    func testTerminalFallbackAppliesWhenCategorySaysOtherwise() {
        XCTAssertEqual(
            ContextResolver.resolve(bundleID: "com.apple.Terminal", category: "public.app-category.utilities"),
            .code,
            "Terminal declares utilities and still needs the code prompt"
        )
        for bundleID in ["com.googlecode.iterm2", "com.mitchellh.ghostty"] {
            XCTAssertEqual(ContextResolver.resolve(bundleID: bundleID, category: nil), .code)
        }
    }

    func testOtherCategoriesResolveToDefault() {
        for category in ["public.app-category.productivity", "public.app-category.social-networking", "public.app-category.utilities"] {
            XCTAssertEqual(
                ContextResolver.resolve(bundleID: "com.example.app", category: category), .default,
                "\(category) must not select the code prompt"
            )
        }
    }

    func testUnknownAndNilBundleIDOrCategoryResolveToDefault() {
        XCTAssertEqual(ContextResolver.resolve(bundleID: "com.example.unknown-app"), .default)
        XCTAssertEqual(ContextResolver.resolve(bundleID: nil), .default)
        XCTAssertEqual(ContextResolver.resolve(bundleID: nil, category: nil), .default)
    }

    func testOverrideBeatsDeveloperToolsCategory() {
        XCTAssertEqual(
            ContextResolver.resolve(
                bundleID: "com.anthropic.claudefordesktop", category: devTools,
                overrides: ["com.anthropic.claudefordesktop": .default]
            ),
            .default,
            "the owner's override must win over the app's declared category"
        )
    }

    // MARK: - Precedence level 1: disabled short-circuit

    func testDisabledShortCircuitsEvenWithCodeBundleID() {
        XCTAssertEqual(
            ContextResolver.resolve(bundleID: "com.apple.Terminal", disabled: true), .default,
            "disabled:true must short-circuit even a curated .code bundle ID"
        )
    }

    func testDisabledShortCircuitsEvenWithPin() {
        XCTAssertEqual(
            ContextResolver.resolve(bundleID: "com.apple.Terminal", pin: .code, disabled: true), .default,
            "disabled:true must short-circuit even an explicit pin (rule 1 beats rule 2)"
        )
    }

    // MARK: - Precedence level 2: pin beats override beats category and fallback

    func testPinBeatsOverride() {
        XCTAssertEqual(
            ContextResolver.resolve(
                bundleID: "com.apple.Terminal",
                pin: .prose,
                overrides: ["com.apple.Terminal": .default]
            ),
            .prose,
            "an explicit pin must win over a per-app override"
        )
    }

    func testOverrideBeatsTerminalFallback() {
        XCTAssertEqual(
            ContextResolver.resolve(
                bundleID: "com.apple.Terminal",
                overrides: ["com.apple.Terminal": .prose]
            ),
            .prose,
            "a per-app override must win over the terminal fallback (com.apple.Terminal is .code there)"
        )
    }

    func testFallbackAppliesWhenNoPinOrOverride() {
        XCTAssertEqual(
            ContextResolver.resolve(bundleID: "com.apple.Terminal", overrides: ["com.apple.Safari": .code]),
            .code,
            "an override for a DIFFERENT bundle ID must not affect this resolution"
        )
    }

    // MARK: - Full precedence chain, one call

    func testFullPrecedenceChain() {
        // disabled beats everything
        XCTAssertEqual(
            ContextResolver.resolve(
                bundleID: "com.apple.Terminal", pin: .prose, disabled: true,
                overrides: ["com.apple.Terminal": .default]
            ),
            .default
        )
        // pin beats override beats category
        XCTAssertEqual(
            ContextResolver.resolve(
                bundleID: "dev.warp.Warp-Stable", category: devTools, pin: .prose, disabled: false,
                overrides: ["dev.warp.Warp-Stable": .default]
            ),
            .prose
        )
        // override beats category
        XCTAssertEqual(
            ContextResolver.resolve(
                bundleID: "dev.warp.Warp-Stable", category: devTools, pin: nil, disabled: false,
                overrides: ["dev.warp.Warp-Stable": .default]
            ),
            .default
        )
        // category beats the terminal fallback's absence
        XCTAssertEqual(
            ContextResolver.resolve(bundleID: "dev.warp.Warp-Stable", category: devTools, pin: nil, disabled: false, overrides: [:]),
            .code
        )
        // terminal fallback beats the .default fallback
        XCTAssertEqual(
            ContextResolver.resolve(bundleID: "com.apple.Terminal", category: "public.app-category.utilities", pin: nil, disabled: false, overrides: [:]),
            .code
        )
        // nothing matches -> .default
        XCTAssertEqual(
            ContextResolver.resolve(bundleID: "com.example.unknown", pin: nil, disabled: false, overrides: [:]),
            .default
        )
    }

    // MARK: - Guarded override-map persistence (Plan 38-03, CTXFMT-03)
    //
    // Mirrors DictionaryDataLossGuardTests exactly in shape: the same
    // present-but-unreadable -> suppress-seed contract, applied to the
    // contextOverrides blob instead of the dictionary blob.

    private func tempDefaults() -> UserDefaults {
        InMemoryUserDefaults()
    }

    func testLoadGuardedAbsentKeyReturnsEmptyAndDoesNotSuppress() {
        let d = tempDefaults()

        let out = ContextResolver.loadGuarded(from: d, key: ContextResolver.overridesKey)

        XCTAssertFalse(out.suppressSeed, "genuine first run (no persisted blob) must allow seeding")
        XCTAssertTrue(out.overrides.isEmpty)
    }

    func testLoadGuardedPresentButUnreadableBlobSuppressesSeed() {
        let d = tempDefaults()
        d.set(Data([0x00, 0x01, 0x02, 0x03]), forKey: ContextResolver.overridesKey)  // present, not decodable

        let out = ContextResolver.loadGuarded(from: d, key: ContextResolver.overridesKey)

        XCTAssertTrue(out.suppressSeed, "present-but-unreadable override blob must suppress the seed-and-overwrite")
        XCTAssertTrue(out.overrides.isEmpty)
    }

    /// CR-01 regression: a genuinely-empty-but-VALIDLY-DECODED blob (e.g. a
    /// user added one override then removed it via the trash button, so
    /// `persist()` saved a real `"{}"`) must NOT be mistaken for the
    /// present-but-unreadable case. Before the fix, `decode()` collapsed
    /// "decode failed" and "decoded to an empty dictionary" onto the same
    /// `[:]` sentinel, so this ordinary flow spuriously reported
    /// `suppressSeed == true`.
    func testLoadGuardedGenuinelyEmptyDecodedMapDoesNotSuppressSeed() {
        let d = tempDefaults()
        let empty: [String: DictationContext] = [:]
        d.set(try! JSONEncoder().encode(empty), forKey: ContextResolver.overridesKey)  // present, decodes to real {}

        let out = ContextResolver.loadGuarded(from: d, key: ContextResolver.overridesKey)

        XCTAssertFalse(out.suppressSeed, "a validly-decoded empty map must not trip the corruption guard")
        XCTAssertTrue(out.overrides.isEmpty)
    }

    /// CR-01 regression, "no overwrite on next save" shape (mirrors
    /// `DictionaryDataLossGuardTests`): once `loadGuarded` reports
    /// `suppressSeed == true` for a present-but-unreadable blob, the
    /// original corrupted bytes must still be recoverable via `save`'s
    /// rolling backup — i.e. a subsequent save must stash what was on disk
    /// (not silently discard it with no trace) before the live key is
    /// overwritten.
    func testPresentButUnreadableBlobIsPreservedInBackupOnNextSave() {
        let d = tempDefaults()
        let corrupted = Data([0x00, 0x01, 0x02, 0x03])
        d.set(corrupted, forKey: ContextResolver.overridesKey)

        let loaded = ContextResolver.loadGuarded(from: d, key: ContextResolver.overridesKey)
        XCTAssertTrue(loaded.suppressSeed)

        ContextResolver.save(loaded.overrides, to: d, key: ContextResolver.overridesKey, backupKey: ContextResolver.overridesBackupKey)

        XCTAssertEqual(d.data(forKey: ContextResolver.overridesBackupKey), corrupted, "the unreadable blob must be preserved in the backup key, not silently lost")
    }

    func testSaveThenLoadRoundTripsOverrides() {
        let d = tempDefaults()
        let overrides: [String: DictationContext] = ["com.apple.Terminal": .prose, "com.example.editor": .code]

        ContextResolver.save(overrides, to: d, key: ContextResolver.overridesKey, backupKey: ContextResolver.overridesBackupKey)
        let out = ContextResolver.loadGuarded(from: d, key: ContextResolver.overridesKey)

        XCTAssertFalse(out.suppressSeed)
        XCTAssertEqual(out.overrides, overrides)
    }

    func testSaveCopiesPriorBlobToBackupKeyBeforeOverwriting() {
        let d = tempDefaults()
        let first: [String: DictationContext] = ["com.apple.Terminal": .code]
        ContextResolver.save(first, to: d, key: ContextResolver.overridesKey, backupKey: ContextResolver.overridesBackupKey)
        let firstBlob = d.data(forKey: ContextResolver.overridesKey)

        let second: [String: DictationContext] = ["com.apple.Terminal": .prose]
        ContextResolver.save(second, to: d, key: ContextResolver.overridesKey, backupKey: ContextResolver.overridesBackupKey)

        XCTAssertEqual(d.data(forKey: ContextResolver.overridesBackupKey), firstBlob, "save must stash the previous blob into the backup key before overwriting")
        let out = ContextResolver.loadGuarded(from: d, key: ContextResolver.overridesKey)
        XCTAssertEqual(out.overrides, second, "the live key must hold the newly-saved value")
    }

    func testSaveDoesNotWriteBackupWhenBlobUnchanged() {
        let d = tempDefaults()
        let overrides: [String: DictationContext] = ["com.apple.Terminal": .code]
        ContextResolver.save(overrides, to: d, key: ContextResolver.overridesKey, backupKey: ContextResolver.overridesBackupKey)
        ContextResolver.save(overrides, to: d, key: ContextResolver.overridesKey, backupKey: ContextResolver.overridesBackupKey)

        XCTAssertNil(d.data(forKey: ContextResolver.overridesBackupKey), "an identical re-save must not churn the backup key")
    }

    // MARK: - contextAwareFormattingEnabled shared helper

    func testIsEnabledDefaultsTrueOnAbsentKey() {
        let d = tempDefaults()
        XCTAssertTrue(ContextResolver.isEnabled(d), "absent key must default to enabled (D-09)")
    }

    func testIsEnabledReadsExplicitFalse() {
        let d = tempDefaults()
        d.set(false, forKey: ContextResolver.enabledKey)
        XCTAssertFalse(ContextResolver.isEnabled(d))
    }

    func testIsEnabledReadsExplicitTrue() {
        let d = tempDefaults()
        d.set(true, forKey: ContextResolver.enabledKey)
        XCTAssertTrue(ContextResolver.isEnabled(d))
    }
}
