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
        "Fixed: quitting Dicticus no longer produces a crash report (the AI-cleanup model is now unloaded on quit)",
        "Fixed: dictation was refused as \"Couldn't paste\" whenever any app held secure keyboard input, even in the background",
        "Fixed: your previous clipboard (screenshot, link) is restored after a dictation again, also with a clipboard manager running",
        "Added: Settings → General → \"Copy transcript to clipboard when it can't be pasted\" — switch it off to keep your clipboard untouched",
    ]

    static let releasesURL = URL(string: "https://github.com/maksim-101/dicticus/releases")!
}
