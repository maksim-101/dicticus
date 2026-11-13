import AppKit

/// Slice 54: the `LSApplicationCategoryType` an app declares in its own Info.plist, read
/// through the running app's bundle URL and cached per URL for this process's lifetime, so
/// a key press costs one plist read per new app and none after. Never Spotlight: an
/// `mdfind` probe froze the popover on every menu bar click (CLAUDE.local.md, 22cf7a1).
@MainActor
final class AppCategoryReader {

    static let shared = AppCategoryReader()

    static let categoryKey = "LSApplicationCategoryType"

    private var cache: [URL: String?] = [:]

    /// Test-only counter: how many times a plist was read.
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
        let value = Bundle(url: url)?.infoDictionary?[Self.categoryKey] as? String
        cache[url] = .some(value)
        return value
    }
}
