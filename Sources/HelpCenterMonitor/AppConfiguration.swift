import Foundation

struct MonitoredSlackChannel {
    let id: String
    let name: String

    var displayName: String { "#\(name)" }
}

enum AppConfiguration {
    static let monitoredChannels = [
        MonitoredSlackChannel(id: "C07ES26GU2D", name: "help-center"),
        MonitoredSlackChannel(id: "C0BJLB6NYQ7", name: "dispatcher"),
    ]
    static let monitoredChannelSummary = monitoredChannels
        .map(\.displayName)
        .joined(separator: " and ")
    static let workspaceURL = "https://upwindsecurity.slack.com"
    static let slackAPIBase = "https://slack.com/api"
    static let keychainService = "help-center-monitor"
    static let awsSecretID = "/production/monitoring/help-center-monitor"
    static let awsRegion = "us-east-1"
    static let awsProfile = "prod-read-only"
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
