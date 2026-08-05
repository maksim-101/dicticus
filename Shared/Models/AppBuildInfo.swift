import Foundation

enum AppBuildInfo {
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    static var gitCommit: String? {
        Bundle.main.infoDictionary?["GitCommit"] as? String
    }

    static var buildDate: String? {
        Bundle.main.infoDictionary?["BuildDate"] as? String
    }

    static var displayVersion: String {
        var s = "Dicticus v\(version) (build \(build))"
        if let hash = gitCommit {
            s += " · \(hash)"
        }
        return s
    }

    static let recentChanges: [String] = [
        "Fixed: pause-media-while-dictating no longer un-pauses an unrelated app when the playing audio comes from a player macOS can't pause — it now mutes the output instead",
        "Added: expanded brand and tech dictation corrections in Dictionary → Starter Packs",
        "Fixed: AI cleanup no longer glues two sentences together (\"labeled.So\") when it rejects an over-eager sentence merge",
    ]

    static let releasesURL = URL(string: "https://github.com/maksim-101/dicticus/releases")!
}
