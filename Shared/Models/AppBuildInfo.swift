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
        "Fixed: push-to-talk media pause could launch Apple Music instead of just pausing what was already playing",
        "Fixed: the brand dictionary's fuzzy matching could rewrite short acronyms and nearby words into an unrelated brand name",
        "Fixed: several AI-cleanup punctuation glitches (stray or misplaced commas, dashes, and periods)",
        "Added: a safety net that stops AI cleanup from silently dropping a number, URL, email, or file path from your dictation",
    ]

    static let releasesURL = URL(string: "https://github.com/maksim-101/dicticus/releases")!
}
