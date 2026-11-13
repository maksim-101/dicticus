import XCTest
@testable import Dicticus

/// Slice 54: the category reader reads `LSApplicationCategoryType` from an app bundle's own
/// Info.plist, returns nil for a bundle without the key, and reads each bundle once.
@MainActor
final class AppCategoryReaderTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppCategoryReaderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeBundle(named name: String, category: String?) throws -> URL {
        let app = root.appendingPathComponent("\(name).app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var plist: [String: Any] = [
            "CFBundleIdentifier": "com.example.\(name.lowercased())",
            "CFBundleName": name,
            "CFBundlePackageType": "APPL",
        ]
        if let category {
            plist[AppCategoryReader.categoryKey] = category
        }
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        return app
    }

    func testReadsDeclaredCategory() throws {
        let app = try makeBundle(named: "DevTool", category: ContextResolver.developerToolsCategory)
        XCTAssertEqual(AppCategoryReader().category(atBundleURL: app), ContextResolver.developerToolsCategory)
    }

    func testBundleWithoutKeyGivesNil() throws {
        let app = try makeBundle(named: "Plain", category: nil)
        XCTAssertNil(AppCategoryReader().category(atBundleURL: app))
    }

    func testEachBundleIsReadOnce() throws {
        let dev = try makeBundle(named: "DevTool", category: ContextResolver.developerToolsCategory)
        let plain = try makeBundle(named: "Plain", category: nil)
        let reader = AppCategoryReader()
        _ = reader.category(atBundleURL: dev)
        _ = reader.category(atBundleURL: dev)
        _ = reader.category(atBundleURL: plain)
        _ = reader.category(atBundleURL: plain)
        XCTAssertEqual(reader.plistReads, 2, "two bundles, four lookups, two plist reads")
        XCTAssertNil(reader.category(atBundleURL: plain), "a cached nil stays nil")
        XCTAssertEqual(reader.plistReads, 2)
    }

    func testUnreadablePlistIsNotCached() throws {
        let missing = root.appendingPathComponent("Gone.app", isDirectory: true)
        let reader = AppCategoryReader()
        XCTAssertNil(reader.category(atBundleURL: missing))
        XCTAssertNil(reader.category(atBundleURL: missing))
        XCTAssertEqual(reader.plistReads, 2, "a failed read must not be cached as 'no category'")
        // The bundle appears later (an update finished): the next lookup sees its category.
        let app = try makeBundle(named: "Gone", category: ContextResolver.developerToolsCategory)
        XCTAssertEqual(app, missing)
        XCTAssertEqual(reader.category(atBundleURL: missing), ContextResolver.developerToolsCategory)
        XCTAssertEqual(reader.plistReads, 3)
    }

    func testNilAppGivesNil() {
        XCTAssertNil(AppCategoryReader().category(of: nil))
    }
}
