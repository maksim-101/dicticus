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
        "Fixed: AI cleanup no longer swaps a correctly dictated German compound for a different word",
        "Fixed: a dictation that starts with a number no longer capitalizes the word after it",
        "Fixed: technical terms such as WebUI or YAML are no longer \"corrected\" into a different brand or word",
        "Fixed: AI cleanup's commas in spoken lists and its sentence breaks in long dictations are kept",
        "Added: spoken punctuation for brackets, ellipsis, question and exclamation marks, and new lines",
    ]

    static let releasesURL = URL(string: "https://github.com/maksim-101/dicticus/releases")!
}
