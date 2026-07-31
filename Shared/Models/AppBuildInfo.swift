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
        "New: media pauses while you dictate — Apple Music & Spotify pause, other audio mutes, all restored on release (macOS)",
        "New: spelled-out acronyms join up (\"N F S K\" → \"NFSK\")",
        "New: \"Zed\" is recognised (the Zed editor, not \"set\")",
        "Improved: AI cleanup handles half-finished sentences and repeated words better",
        "Fixed: the dictionary no longer alters correctly-spelled words",
        "New: more brand and tech names recognised",
    ]

    static let releasesURL = URL(string: "https://github.com/maksim-101/dicticus-macos/releases")!
}
