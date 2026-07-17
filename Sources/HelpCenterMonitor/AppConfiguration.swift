import Foundation

enum AppConfiguration {
    static let channel = "C0BHCB96XM5"
    static let workspaceURL = "https://upwindsecurity.slack.com"
    static let slackAPIBase = "https://slack.com/api"
    static let keychainService = "help-center-monitor"
    static let maximumPages = 500
    static let legacyAgentPlistName = "io.upwind.help-center-monitor.agent.plist"

    static var installedAppURLs: [URL] {
        [
            URL(fileURLWithPath: "/Applications/Help Center Monitor.app", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications/Help Center Monitor.app", isDirectory: true),
        ]
    }

    static func isInstalledBundle(_ bundleURL: URL) -> Bool {
        let candidate = bundleURL.standardizedFileURL.resolvingSymlinksInPath().path
        return installedAppURLs.contains {
            $0.standardizedFileURL.resolvingSymlinksInPath().path == candidate
        }
    }
}
