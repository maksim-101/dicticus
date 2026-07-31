import XCTest
@testable import Dicticus

// Phase 36.3 Plan 01 — Wave 0 contract test (SC1: entitlement removal)
//
// SC1 contract: the macOS app's entitlements plist MUST NOT contain
// com.apple.security.application-groups after Plan 04 removes it.
// This test reads the source plist from the repo (path derived from #filePath)
// so it catches drift in the entitlements file directly, not just the built binary.
//
// The plist is NOT modified in Plan 01 — this test will PASS right now (the key
// is still present) and must FAIL after Plan 04 removes it. Wait — actually the
// test asserts ABSENCE, so it currently FAILS (key is present) and will PASS after
// Plan 04 removes it. That is the intended RED state for Wave 0.

@MainActor
final class EntitlementTests: XCTestCase {

    // Resolve path: test file lives at
    //   <repo>/macOS/DicticusTests/EntitlementTests.swift
    // Entitlements plist lives at:
    //   <repo>/macOS/Dicticus/Dicticus.entitlements
    private var entitlementsURL: URL {
        // #filePath gives the source file path at compile time
        let thisFile = URL(fileURLWithPath: #filePath)
        // Walk up: EntitlementTests.swift → DicticusTests → macOS → repo root is NOT needed;
        // target is at same level: macOS/Dicticus/Dicticus.entitlements
        let macOSDir = thisFile
            .deletingLastPathComponent() // DicticusTests/
            .deletingLastPathComponent() // macOS/
        return macOSDir
            .appendingPathComponent("Dicticus")
            .appendingPathComponent("Dicticus.entitlements")
    }

    private func loadEntitlements() throws -> [String: Any] {
        let data = try Data(contentsOf: entitlementsURL)
        guard let plist = try PropertyListSerialization.propertyList(
            from: data, options: [], format: nil
        ) as? [String: Any] else {
            throw XCTestError(.failureWhileWaiting, userInfo: [NSLocalizedDescriptionKey: "Entitlements plist root is not a dictionary"])
        }
        return plist
    }

    /// SC1: application-groups entitlement MUST be absent from the macOS entitlements.
    /// RED until Plan 04 removes the key.
    func testApplicationGroupsEntitlementIsAbsent() throws {
        let plist = try loadEntitlements()
        XCTAssertNil(
            plist["com.apple.security.application-groups"],
            "SC1: com.apple.security.application-groups must be ABSENT from macOS entitlements after Plan 04 removes it (current RED state until Plan 04 lands)"
        )
    }

    /// Regression guard: the 5 required entitlement keys must remain present.
    /// Ensures Plan 04's entitlement edit does not accidentally strip other keys.
    func testRequiredEntitlementKeysArePresent() throws {
        let plist = try loadEntitlements()

        let requiredKeys: [(key: String, description: String)] = [
            ("com.apple.security.app-sandbox",                         "app-sandbox (must be false — non-sandboxed app)"),
            ("com.apple.security.automation.apple-events",             "automation.apple-events (media pause)"),
            ("com.apple.security.cs.allow-unsigned-executable-memory", "cs.allow-unsigned-executable-memory (llama.cpp)"),
            ("com.apple.security.cs.disable-library-validation",       "cs.disable-library-validation (unsigned dylibs)"),
            ("com.apple.security.device.audio-input",                  "device.audio-input (microphone)"),
        ]

        for (key, description) in requiredKeys {
            XCTAssertNotNil(
                plist[key],
                "Required entitlement key '\(key)' (\(description)) must remain present after Plan 04 edit"
            )
        }
    }

    /// Sanity: the plist file is reachable from the derived path.
    func testEntitlementsPlistIsReadable() throws {
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: entitlementsURL.path),
            "Dicticus.entitlements must exist at expected path: \(entitlementsURL.path)"
        )
    }
}
