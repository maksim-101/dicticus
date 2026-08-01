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
        "Fixed: AI cleanup no longer glues two sentences together (\"labeled.So\") when it rejects an over-eager sentence merge",
        "Changed: project home is now github.com/maksim-101/dicticus — the update feed moved with it",
    ]

    static let releasesURL = URL(string: "https://github.com/maksim-101/dicticus/releases")!
}
