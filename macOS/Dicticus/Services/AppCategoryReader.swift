import AppKit

/// Slice 54: the `LSApplicationCategoryType` an app declares in its own Info.plist, read
/// through the running app's bundle URL and cached per URL for this process's lifetime, so
/// a key press costs one plist read per new app and none after. A plist that cannot be read
/// (the bundle mid-update, a volume gone) is not cached, so the next press reads again. The
/// plist is read as a dictionary, not through `Bundle(url:)`, which would keep an `NSBundle`
/// per app resident. Never Spotlight: an `mdfind` probe froze the popover on every menu bar
/// click (CLAUDE.local.md, 22cf7a1).
@MainActor
final class AppCategoryReader {

    static let shared = AppCategoryReader()

    static let categoryKey = "LSApplicationCategoryType"

    private var cache: [URL: String?] = [:]

    /// Test-only counter: how many times a plist read was attempted.
    private(set) var plistReads = 0

    func category(of app: NSRunningApplication?) -> String? {
        guard let url = app?.bundleURL else { return nil }
        return category(atBundleURL: url)
    }

    func category(atBundleURL url: URL) -> String? {
        if let cached = cache[url] {
            return cached
        }
        plistReads += 1
        // macOS layout first, then the flat layout of an iPhone or iPad app running on
        // Apple Silicon (Info.plist at the bundle root).
        let candidates = [url.appendingPathComponent("Contents/Info.plist"), url.appendingPathComponent("Info.plist")]
        guard let info = candidates.lazy.compactMap({ NSDictionary(contentsOf: $0) }).first else {
            return nil
        }
        let value = info[Self.categoryKey] as? String
        cache[url] = .some(value)
        return value
    }
}
