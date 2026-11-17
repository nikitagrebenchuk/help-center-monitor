import AppKit
import Foundation
import ServiceManagement
import UserNotifications

@main
enum HelpCenterMonitorMain {
    static func main() {
        if CommandLine.arguments.contains("--bundle-check") {
            runBundleCheck()
            return
        }
        if CommandLine.arguments.contains("--prepare-uninstall") {
            prepareUninstall()
            return
        }
        if shouldHandOffToInstalledCopy() {
            return
        }

        prepareAutomaticStart()

        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
    }

    private static func runBundleCheck() {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent
        let identifier = Bundle.main.bundleIdentifier ?? "missing"
        let isAppBundle = Bundle.main.bundleURL.pathExtension == "app"
        print("bundle=\(identifier) executable=\(executable) appBundle=\(isAppBundle)")
    }

    private static func prepareUninstall() {
        guard Bundle.main.bundleURL.pathExtension == "app",
              AppConfiguration.isInstalledBundle(Bundle.main.bundleURL) else {
            FileHandle.standardError.write(
                Data("Run --prepare-uninstall from the installed application.\n".utf8)
            )
            exit(2)
        }

        var failures: [String] = []
        let mainService = SMAppService.mainApp
        if mainService.status != .notRegistered && mainService.status != .notFound {
            do {
                try mainService.unregister()
            } catch {
                failures.append("automatic start: \(error.localizedDescription)")
            }
        }

        let legacyService = SMAppService.agent(plistName: AppConfiguration.legacyAgentPlistName)
        if legacyService.status != .notRegistered && legacyService.status != .notFound {
            try? legacyService.unregister()
        }

        let center = UNUserNotificationCenter.current()
        center.removeAllDeliveredNotifications()
        center.removeAllPendingNotificationRequests()

        do {
            try KeychainStore(service: AppConfiguration.keychainService).deleteToken()
        } catch {
            failures.append("Keychain token: \(error.localizedDescription)")
        }

        if let identifier = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: identifier)
        }
        AlertSoundStore.removeAllStoredFiles()
        let legacyState = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".help-center-monitor-state.json")
        try? FileManager.default.removeItem(at: legacyState)

        if failures.isEmpty {
            print("Prepared Help Center Monitor for removal.")
        } else {
            FileHandle.standardError.write(
                Data("Uninstall preparation failed: \(failures.joined(separator: "; "))\n".utf8)
            )
            exit(1)
        }
    }

    private static func shouldHandOffToInstalledCopy() -> Bool {
        guard Bundle.main.bundleURL.pathExtension == "app",
              !AppConfiguration.isInstalledBundle(Bundle.main.bundleURL) else {
            return false
        }

        let currentPath = Bundle.main.bundleURL.standardizedFileURL.path
        for appURL in AppConfiguration.installedAppURLs
        where appURL.standardizedFileURL.path != currentPath
            && FileManager.default.fileExists(atPath: appURL.path) {
            if NSWorkspace.shared.open(appURL) {
                return true
            }
        }
        return false
    }

    private static func prepareAutomaticStart() {
        guard Bundle.main.bundleURL.pathExtension == "app",
              AppConfiguration.isInstalledBundle(Bundle.main.bundleURL) else {
            return
        }

        migrateLegacyLaunchAgent()

        let service = SMAppService.mainApp
        guard service.status == .notRegistered else { return }
        do {
            try service.register()
        } catch {
            // The running app remains fully functional. AppDelegate surfaces
            // approval state and links to Login Items settings when required.
        }
    }

    private static func migrateLegacyLaunchAgent() {
        let legacy = SMAppService.agent(plistName: AppConfiguration.legacyAgentPlistName)
        if legacy.status == .enabled || legacy.status == .requiresApproval {
            try? legacy.unregister()
        }
        UserDefaults.standard.removeObject(forKey: "registeredAgentBundleVersion")
        UserDefaults.standard.removeObject(forKey: "registeredAgentBundlePath")
    }
}
