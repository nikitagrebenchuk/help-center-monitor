import AppKit
import Foundation
import HelpCenterAWS
import HelpCenterCore
import HelpCenterSlack
import HelpCenterUI
import OSLog
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(
        subsystem: "io.upwind.help-center-monitor",
        category: "monitor"
    )
    private let state = MonitorState()
    private let keychain = KeychainStore(service: AppConfiguration.keychainService)
    private let awsTokenProvider = AWSSecretsManagerTokenProvider(
        secretID: AppConfiguration.awsSecretID,
        region: AppConfiguration.awsRegion,
        profile: AppConfiguration.awsProfile
    )
    private let slack = SlackClient(apiBase: AppConfiguration.slackAPIBase)
    private let notifications = NotificationManager()

    private var statusBarItem: NSStatusItem!
    private var enabledMenuItem: NSMenuItem!
    private var teamVoicesMenuItem: NSMenuItem!
    private var statusMenuItem: NSMenuItem!
    private var lastCheckMenuItem: NSMenuItem!
    private var notificationMenuItem: NSMenuItem!
    private var automaticStartMenuItem: NSMenuItem!
    private var monitorTask: Task<Void, Never>?
    private var cachedSlackToken: String?
    private var controlWindowController: ControlWindowController?
    private var currentStatus = "Starting…"
    private var lastCheckedText: String?
    private var notificationStatusText = "Checking notification permission…"
    private var notificationsReady = false
    private var slackCredentialStatusText = "Checking Keychain…"
    private var slackCredentialReady = false
    private var automaticStartStatusText = "Checking automatic start…"
    private var automaticStartReady = false
    private var notificationReopenCoordinator = NotificationReopenCoordinator()

    private let fatalSlackCodes: Set<String> = [
        "invalid_auth", "account_inactive", "token_revoked", "not_in_channel",
        "channel_not_found", "missing_scope",
    ]
    private static let credentialFatalSlackCodes: Set<String> = [
        "invalid_auth", "account_inactive", "token_revoked", "missing_scope",
    ]

    override init() {
        super.init()
        notifications.onNotificationSelected = { [weak self] url in
            DispatchQueue.main.async {
                self?.handleNotificationSelection(url)
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = HelpCenterApplicationMenu.make()
        configureMenu()
        configureWakeObservers()
        configureAutomaticStartStatus()

        let defaults = UserDefaults.standard
        let shouldShowControlPanel = !defaults.bool(forKey: "completedFirstLaunch")
            || defaults.bool(forKey: "previousRunDidNotExitCleanly")
        defaults.set(true, forKey: "completedFirstLaunch")
        defaults.set(true, forKey: "previousRunDidNotExitCleanly")
        if shouldShowControlPanel {
            showControlWindow()
        }

        notifications.onStatusChange = { [weak self] status in
            DispatchQueue.main.async {
                self?.handleNotificationStatus(status)
            }
        }
        notifications.onDeliveryError = { [weak self] message in
            DispatchQueue.main.async {
                self?.logger.error("\(message, privacy: .public)")
            }
        }
        notifications.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard let self else { return }
                self.handleNotificationStatus(status)
                if !status.canPresentAlerts {
                    self.showControlWindow()
                }
                self.finishStartup()
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        configureAutomaticStartStatus()
        notifications.refreshStatus { [weak self] status in
            DispatchQueue.main.async {
                self?.handleNotificationStatus(status)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitorTask?.cancel()
        UserDefaults.standard.set(false, forKey: "previousRunDidNotExitCleanly")
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        guard let generation = notificationReopenCoordinator.requestReopen(
            hasVisibleWindows: flag
        ) else {
            return false
        }

        // A notification click and an explicit Spotlight/Finder reopen both
        // activate this accessory app. Delay ordinary reopen very briefly so
        // the notification callback can cancel it before the panel appears.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self,
                  self.notificationReopenCoordinator.shouldShowReopen(
                    generation: generation
                  ) else {
                return
            }
            self.showControlWindow()
            self.notificationReopenCoordinator.markReopenShown(generation: generation)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.notificationReopenCoordinator.clearReopenShown(
                    generation: generation
                )
            }
        }
        return false
    }

    private func configureMenu() {
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusBarItem.button?.toolTip = "Help Center Monitor"

        let menu = NSMenu()
        menu.autoenablesItems = false

        enabledMenuItem = NSMenuItem(
            title: "Monitoring Enabled",
            action: #selector(toggleMonitoring),
            keyEquivalent: ""
        )
        enabledMenuItem.target = self
        enabledMenuItem.isEnabled = true
        menu.addItem(enabledMenuItem)

        teamVoicesMenuItem = NSMenuItem(
            title: "Team Voice Alerts Disabled",
            action: #selector(toggleTeamVoiceAlerts),
            keyEquivalent: ""
        )
        teamVoicesMenuItem.target = self
        teamVoicesMenuItem.isEnabled = true
        menu.addItem(teamVoicesMenuItem)

        let sourceMenuItem = NSMenuItem(
            title: "Sources: \(AppConfiguration.monitoredChannelSummary)",
            action: nil,
            keyEquivalent: ""
        )
        sourceMenuItem.isEnabled = false
        menu.addItem(sourceMenuItem)

        statusMenuItem = NSMenuItem(title: "Status: Starting…", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        lastCheckMenuItem = NSMenuItem(title: "Last checked: —", action: nil, keyEquivalent: "")
        lastCheckMenuItem.isEnabled = false
        menu.addItem(lastCheckMenuItem)

        notificationMenuItem = NSMenuItem(
            title: "Notifications: Checking…",
            action: #selector(openNotificationSettings),
            keyEquivalent: ""
        )
        notificationMenuItem.target = self
        notificationMenuItem.isEnabled = false
        menu.addItem(notificationMenuItem)

        menu.addItem(.separator())

        let testItem = NSMenuItem(
            title: "Send Test Alert",
            action: #selector(sendTestNotification),
            keyEquivalent: ""
        )
        testItem.target = self
        testItem.isEnabled = true
        menu.addItem(testItem)

        let tokenItem = NSMenuItem(
            title: "Replace Slack Token…",
            action: #selector(replaceSlackToken),
            keyEquivalent: ""
        )
        tokenItem.target = self
        tokenItem.isEnabled = true
        menu.addItem(tokenItem)

        automaticStartMenuItem = NSMenuItem(
            title: "Checking Automatic Start…",
            action: #selector(openLoginItemsSettings),
            keyEquivalent: ""
        )
        automaticStartMenuItem.target = self
        menu.addItem(automaticStartMenuItem)

        statusBarItem.menu = menu
        updateEnabledAppearance()
    }

    private func configureWakeObservers() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )
    }

    private func finishStartup() {
        migrateLegacyTimestampIfNeeded()
        guard state.isMonitoringEnabled else {
            setStatus("Disabled")
            return
        }
        setStatus("Loading Slack access…")
        Task { [weak self] in
            guard let self else { return }
            guard await self.token(promptIfMissing: true) != nil else {
                self.state.isMonitoringEnabled = false
                self.updateEnabledAppearance()
                self.setStatus("Disabled — Slack token required")
                self.showControlWindow()
                return
            }
            self.startMonitoring()
        }
    }

    private func migrateLegacyTimestampIfNeeded() {
        let legacyURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".help-center-monitor-state.json")
        guard let data = try? Data(contentsOf: legacyURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        for channel in AppConfiguration.monitoredChannels {
            guard state.lastTimestamp(for: channel.id) == nil,
                  let channelState = json[channel.id] as? [String: Any],
                  let timestamp = channelState["last_ts"] as? String,
                  Double(timestamp) != nil else {
                continue
            }
            state.setLastTimestamp(timestamp, for: channel.id)
            logger.info(
                "Imported the legacy last-seen timestamp for \(channel.displayName, privacy: .public)"
            )
        }
    }

    @objc private func toggleMonitoring() {
        setMonitoringEnabled(!state.isMonitoringEnabled)
    }

    @objc private func toggleTeamVoiceAlerts() {
        setTeamVoiceAlertsEnabled(!state.areTeamVoiceAlertsEnabled)
    }

    @objc private func openControlWindowFromMenu() {
        showControlWindow()
    }

    private func setMonitoringEnabled(_ enabled: Bool) {
        guard enabled != state.isMonitoringEnabled else {
            updateEnabledAppearance()
            return
        }
        if !enabled {
            state.isMonitoringEnabled = false
            monitorTask?.cancel()
            monitorTask = nil
            setStatus("Disabled")
        } else {
            setStatus("Loading Slack access…")
            Task { [weak self] in
                guard let self else { return }
                guard await self.token(promptIfMissing: true) != nil else {
                    self.updateEnabledAppearance()
                    return
                }
                // Disabling means "do not alert me." Start from now when the user
                // re-enables monitoring instead of flooding them with tickets that
                // arrived while the app was deliberately paused.
                for channel in AppConfiguration.monitoredChannels {
                    self.state.clearLastTimestamp(for: channel.id)
                }
                self.state.isMonitoringEnabled = true
                self.startMonitoring()
                self.updateEnabledAppearance()
            }
            return
        }
        updateEnabledAppearance()
    }

    private func setTeamVoiceAlertsEnabled(_ enabled: Bool) {
        guard enabled != state.areTeamVoiceAlertsEnabled else {
            updateEnabledAppearance()
            return
        }
        guard !enabled || notifications.availableTeamVoiceCount > 0 else {
            updateEnabledAppearance()
            showError(
                title: "No Team Voices Available",
                message: "Add processed recordings to the app before enabling team voice-over alerts."
            )
            return
        }
        state.areTeamVoiceAlertsEnabled = enabled
        logger.info("Team voice alerts \(enabled ? "enabled" : "disabled", privacy: .public)")
        updateEnabledAppearance()
    }

    @objc private func sendTestNotification() {
        notifications.sendTest(
            mode: currentAlertMode,
            usesTeamVoice: state.areTeamVoiceAlertsEnabled
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success:
                    self.notificationsReady = true
                    self.notificationStatusText = "Notifications enabled — test sent just now"
                    self.logger.info("Test notification sent")
                    self.updateNotificationAppearance()
                case .failure(let error):
                    self.notificationsReady = false
                    self.notificationStatusText = error.localizedDescription
                    self.logger.error("Test notification blocked: \(error.localizedDescription, privacy: .public)")
                    self.updateNotificationAppearance()
                    self.showNotificationSetupAlert()
                }
            }
        }
    }

    @objc private func replaceSlackToken() {
        let wasMissingCredential = !slackCredentialReady
        guard let newToken = promptForToken(replacingExisting: slackCredentialReady) else { return }
        do {
            try keychain.saveToken(newToken)
            cachedSlackToken = newToken
            setSlackCredentialStatus(
                "Stored manually in this Mac’s Keychain",
                ready: true
            )
            logger.info("Slack token replaced in Keychain")
            if wasMissingCredential && !state.isMonitoringEnabled {
                for channel in AppConfiguration.monitoredChannels {
                    state.clearLastTimestamp(for: channel.id)
                }
                state.isMonitoringEnabled = true
            }
            updateEnabledAppearance()
            startMonitoring()
        } catch {
            setSlackCredentialStatus("Could not save the token to Keychain", ready: false)
            showError(title: "Could Not Save Token", message: error.localizedDescription)
        }
    }

    @objc private func systemDidWake() {
        guard state.isMonitoringEnabled else { return }
        logger.info("System became active; checking Slack immediately")
        startMonitoring()
    }

    @objc private func openLoginItemsSettings() {
        if let service = Self.automaticStartService,
           service.status == .notRegistered {
            try? service.register()
            configureAutomaticStartStatus()
            if service.status == .enabled {
                return
            }
        }
        SMAppService.openSystemSettingsLoginItems()
    }

    @objc private func openNotificationSettings() {
        let settingsURLs = [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension?io.upwind.help-center-monitor",
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
        ]
        for value in settingsURLs {
            if let url = URL(string: value), NSWorkspace.shared.open(url) {
                return
            }
        }
        showError(
            title: "Open Notification Settings",
            message: "Open System Settings → Notifications → Help Center Monitor, then enable Allow Notifications and Banners."
        )
    }

    private func showControlWindow() {
        if controlWindowController == nil {
            controlWindowController = ControlWindowController(
                monitoredChannels: AppConfiguration.monitoredChannelSummary,
                onSetEnabled: { [weak self] enabled in
                    self?.setMonitoringEnabled(enabled)
                },
                onSetTeamVoicesEnabled: { [weak self] enabled in
                    self?.setTeamVoiceAlertsEnabled(enabled)
                },
                onSendTest: { [weak self] in
                    self?.sendTestNotification()
                },
                onOpenNotificationSettings: { [weak self] in
                    self?.openNotificationSettings()
                },
                onConfigureSlack: { [weak self] in
                    self?.replaceSlackToken()
                }
            )
        }
        updateControlWindow()
        controlWindowController?.present()
    }

    private func handleNotificationSelection(_ url: URL?) {
        let shouldHideReopenWindow = notificationReopenCoordinator.notificationSelected()
        if shouldHideReopenWindow {
            controlWindowController?.window?.orderOut(nil)
        }
        if let url {
            NSWorkspace.shared.open(url)
        }
    }

    private func startMonitoring() {
        monitorTask?.cancel()
        guard state.isMonitoringEnabled,
              let token = cachedSlackToken else {
            return
        }
        setStatus("Connecting to Slack…")
        monitorTask = Task { [weak self] in
            await self?.monitorLoop(token: token)
        }
    }

    private func monitorLoop(token: String) async {
        var authenticated = false
        var networkBackoff: TimeInterval = 5
        let channels = AppConfiguration.monitoredChannels
        var lastTimestamps = Dictionary(uniqueKeysWithValues: channels.compactMap { channel in
            state.lastTimestamp(for: channel.id).map { (channel.id, $0) }
        })
        let firstRunBaseline = String(format: "%.6f", Date().timeIntervalSince1970)

        while state.isMonitoringEnabled && !Task.isCancelled {
            if !authenticated {
                do {
                    let identity = try await slack.authenticate(token: token)
                    authenticated = true
                    networkBackoff = 5
                    setSlackCredentialStatus(slackCredentialStatusText, ready: true)
                    setStatus("Monitoring as \(identity.user) in \(identity.team)")
                    logger.info(
                        "Authenticated as \(identity.user, privacy: .public) in \(identity.team, privacy: .public)"
                    )
                    for channel in channels where lastTimestamps[channel.id] == nil {
                        // Capture the baseline before authentication so a slow
                        // auth request cannot create a blind window.
                        lastTimestamps[channel.id] = firstRunBaseline
                        state.setLastTimestamp(firstRunBaseline, for: channel.id)
                        logger.info(
                            "First run for \(channel.displayName, privacy: .public): monitoring new messages from now"
                        )
                    }
                } catch {
                    guard state.isMonitoringEnabled && !Task.isCancelled else { return }
                    let delay = authenticationRetryDelay(for: error)
                    guard await pause(seconds: delay) else { return }
                    continue
                }
            }

            var allPollsSucceeded = true
            var completedPollCount = 0
            var nextPollDelay = state.pollInterval
            var sawNetworkFailure = false

            for channel in channels {
                guard let oldest = lastTimestamps[channel.id] else { continue }
                do {
                    let result = try await slack.fetchNewMessages(
                        token: token,
                        channel: channel.id,
                        oldest: oldest,
                        maximumPages: AppConfiguration.maximumPages
                    )
                    guard state.isMonitoringEnabled && !Task.isCancelled else { return }

                    var lastTimestamp = oldest
                    for message in result.messages {
                        guard state.isMonitoringEnabled && !Task.isCancelled,
                              let timestamp = message["ts"] as? String else {
                            return
                        }
                        let sender = SlackMessageParser.sender(message)
                        let body = SlackMessageParser.messageText(message)
                        let issue = SlackMessageParser.pylonIssueNumber(message)
                        let link = SlackMessageParser.bestLink(
                            message,
                            channel: channel.id,
                            workspaceURL: AppConfiguration.workspaceURL
                        )
                        await deliverTicketNotification(
                            sender: sender,
                            body: body,
                            issue: issue,
                            link: link,
                            identifier: "\(channel.id)-\(timestamp)",
                            source: channel.displayName,
                            mode: .channelMessage
                        )
                        logger.info(
                            "New message in \(channel.displayName, privacy: .public) from \(sender, privacy: .public)"
                        )
                        lastTimestamp = timestamp
                        lastTimestamps[channel.id] = timestamp
                        state.setLastTimestamp(timestamp, for: channel.id)
                    }

                    if let floor = result.highestTimestamp,
                       timestampValue(floor) > timestampValue(lastTimestamp) {
                        lastTimestamps[channel.id] = floor
                        state.setLastTimestamp(floor, for: channel.id)
                    }
                    completedPollCount += 1
                } catch SlackClientError.rateLimited(let seconds) {
                    allPollsSucceeded = false
                    nextPollDelay = seconds
                    setStatus("Rate limited — retrying in \(Int(seconds))s")
                    logger.warning("Slack rate limit; retrying in \(seconds)s")
                    break
                } catch SlackClientError.api(let code, let explanation) {
                    allPollsSucceeded = false
                    setStatus("Error in \(channel.displayName): \(explanation)")
                    logger.error(
                        "Slack API error for \(channel.displayName, privacy: .public) (\(code, privacy: .public)): \(explanation, privacy: .public)"
                    )
                    if Self.credentialFatalSlackCodes.contains(code) {
                        setSlackCredentialStatus(
                            "Slack access needs to be replaced or corrected",
                            ready: false
                        )
                        showControlWindow()
                    } else if fatalSlackCodes.contains(code) {
                        showControlWindow()
                    }
                    if Self.credentialFatalSlackCodes.contains(code) {
                        authenticated = false
                        nextPollDelay = 300
                        break
                    }
                } catch {
                    allPollsSucceeded = false
                    sawNetworkFailure = true
                    nextPollDelay = networkBackoff
                    setStatus("Offline — retrying in \(Int(networkBackoff))s")
                    logger.warning(
                        "Slack network error for \(channel.displayName, privacy: .public): \(error.localizedDescription, privacy: .public)"
                    )
                }
            }

            if completedPollCount > 0 {
                updateLastChecked()
            }
            if allPollsSucceeded {
                networkBackoff = 5
                setStatus("Monitoring — \(channels.count) Slack channels")
                logger.info(
                    "Slack polls completed; next check in \(Int(self.state.pollInterval)) seconds"
                )
            } else if sawNetworkFailure {
                networkBackoff = min(networkBackoff * 2, 60)
            }
            guard await pause(seconds: nextPollDelay) else { return }
        }
    }

    private func deliverTicketNotification(
        sender: String,
        body: String,
        issue: String?,
        link: String,
        identifier: String,
        source: String,
        mode: TicketAlertMode
    ) async {
        var title = "\(source) — Needs response — \(sender)"
        if let issue {
            title += " (#\(issue))"
        }
        let deliveryResult = await withCheckedContinuation { continuation in
            notifications.send(
                title: title,
                body: body,
                link: link,
                identifier: "help-center-ticket-\(identifier)",
                mode: mode,
                usesTeamVoice: state.areTeamVoiceAlertsEnabled
            ) { result in
                continuation.resume(returning: result)
            }
        }
        switch deliveryResult {
        case .success:
            logger.info("Notification delivered to macOS for \(sender, privacy: .public)")
        case .failure(let error):
            notificationsReady = false
            notificationStatusText = error.localizedDescription
            updateNotificationAppearance()
            logger.error(
                "System notification blocked; showing fallback: \(error.localizedDescription, privacy: .public)"
            )
            showFallbackTicketAlert(title: title, body: body, link: link)
        }
    }

    private func authenticationRetryDelay(for error: Error) -> TimeInterval {
        switch error {
        case SlackClientError.rateLimited(let seconds):
            setStatus("Rate limited — retrying in \(Int(seconds))s")
            return seconds
        case SlackClientError.api(let code, let explanation):
            setStatus("Error: \(explanation)")
            logger.error("Slack authentication error \(code, privacy: .public)")
            if fatalSlackCodes.contains(code) {
                setSlackCredentialStatus(
                    "Slack access needs to be replaced or corrected",
                    ready: false
                )
                showControlWindow()
            }
            return fatalSlackCodes.contains(code) ? 300 : 60
        default:
            setStatus("Offline — retrying in 15s")
            logger.warning("Slack authentication network error: \(error.localizedDescription, privacy: .public)")
            return 15
        }
    }

    private func pause(seconds: TimeInterval) async -> Bool {
        let nanoseconds = UInt64(max(seconds, 0.1) * 1_000_000_000)
        do {
            try await Task<Never, Never>.sleep(nanoseconds: nanoseconds)
            return !Task.isCancelled
        } catch {
            return false
        }
    }

    private func token(promptIfMissing: Bool) async -> String? {
        if let cachedSlackToken {
            return cachedSlackToken
        }

        setSlackCredentialStatus("Loading automatically from AWS Secrets Manager…", ready: false)
        let provider = awsTokenProvider
        do {
            let fetched = try await Task.detached(priority: .userInitiated) {
                try provider.fetchToken()
            }.value
            cachedSlackToken = fetched
            do {
                try keychain.saveToken(fetched)
                setSlackCredentialStatus(
                    "Loaded automatically from AWS Secrets Manager and cached in Keychain",
                    ready: true
                )
            } catch {
                setSlackCredentialStatus(
                    "Loaded automatically from AWS Secrets Manager; Keychain cache unavailable",
                    ready: true
                )
                logger.warning(
                    "AWS token loaded, but Keychain caching failed: \(error.localizedDescription, privacy: .public)"
                )
            }
            logger.info("Slack token loaded automatically from AWS Secrets Manager")
            return fetched
        } catch {
            logger.warning(
                "Automatic AWS Secrets Manager retrieval failed: \(error.localizedDescription, privacy: .public)"
            )
        }

        do {
            if let existing = try keychain.readToken() {
                cachedSlackToken = existing
                setSlackCredentialStatus(
                    "AWS unavailable; using the token saved in this Mac’s Keychain",
                    ready: true
                )
                return existing
            }
        } catch {
            setSlackCredentialStatus(
                "AWS retrieval and Keychain access both failed",
                ready: false
            )
            logger.warning("Keychain fallback failed: \(error.localizedDescription, privacy: .public)")
        }
        guard promptIfMissing,
              let entered = promptForToken(
                replacingExisting: false,
                automaticRetrievalFailed: true
              ) else {
            setSlackCredentialStatus(
                "AWS retrieval failed — manual Slack setup is required",
                ready: false
            )
            return nil
        }
        do {
            try keychain.saveToken(entered)
            cachedSlackToken = entered
            setSlackCredentialStatus(
                "AWS unavailable; manual token stored in this Mac’s Keychain",
                ready: true
            )
            return entered
        } catch {
            setSlackCredentialStatus("Could not save the token to Keychain", ready: false)
            showError(title: "Could Not Save Slack Token", message: error.localizedDescription)
            return nil
        }
    }

    private func promptForToken(
        replacingExisting: Bool,
        automaticRetrievalFailed: Bool = false
    ) -> String? {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = replacingExisting ? "Replace Slack Bot Token" : "Slack Bot Token Required"
        alert.informativeText = automaticRetrievalFailed
            ? "The token could not be loaded automatically from AWS Secrets Manager. Paste the xoxb- bot token as a fallback; it will be stored only in your macOS Keychain."
            : "Paste the xoxb- bot token. It will be stored only in your macOS Keychain."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 24))
        field.placeholderString = "xoxb-…"
        alert.accessoryView = field
        alert.layout()
        alert.window.initialFirstResponder = field
        alert.window.makeFirstResponder(field)

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.hasPrefix("xoxb-"), value.count > 10 else {
            showError(
                title: "Invalid Slack Token",
                message: "A bot token should begin with xoxb-. Nothing was saved."
            )
            return nil
        }
        return value
    }

    private func showError(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func setStatus(_ status: String) {
        currentStatus = status
        statusMenuItem.title = "Status: \(status)"
        updateEnabledAppearance()
    }

    private func updateLastChecked() {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        lastCheckedText = formatter.string(from: Date())
        lastCheckMenuItem.title = "Last checked: \(lastCheckedText!)"
        updateControlWindow()
    }

    private func updateEnabledAppearance() {
        let enabled = state.isMonitoringEnabled
        enabledMenuItem.state = enabled ? .on : .off
        enabledMenuItem.title = enabled ? "Monitoring Enabled" : "Monitoring Disabled"
        let teamVoicesEnabled = state.areTeamVoiceAlertsEnabled
        teamVoicesMenuItem.state = teamVoicesEnabled ? .on : .off
        teamVoicesMenuItem.title = teamVoicesEnabled
            ? "Team Voice Alerts Enabled"
            : "Team Voice Alerts Disabled"
        let symbolName: String
        if !enabled {
            symbolName = "bell.slash"
        } else if notificationsReady && slackCredentialReady {
            symbolName = "bell.badge.fill"
        } else {
            symbolName = "exclamationmark.triangle.fill"
        }
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Help Center Monitor")
        image?.isTemplate = true
        statusBarItem.button?.image = image
        updateControlWindow()
    }

    private func handleNotificationStatus(_ status: NotificationPermissionStatus) {
        notificationsReady = status.canPresentAlerts
        notificationStatusText = status.message
        if status.canPresentAlerts {
            logger.info("Notification permission is enabled")
        } else {
            logger.warning("Notification permission is blocked: \(status.message, privacy: .public)")
        }
        updateNotificationAppearance()
    }

    private func updateNotificationAppearance() {
        if notificationMenuItem != nil {
            notificationMenuItem.title = notificationsReady
                ? "Notifications Enabled"
                : "Fix Notifications…"
            notificationMenuItem.state = notificationsReady ? .on : .off
            notificationMenuItem.isEnabled = !notificationsReady
        }
        updateEnabledAppearance()
    }

    private func setSlackCredentialStatus(_ message: String, ready: Bool) {
        slackCredentialStatusText = message
        slackCredentialReady = ready
        updateControlWindow()
    }

    private func updateControlWindow() {
        controlWindowController?.update(
            enabled: state.isMonitoringEnabled,
            teamVoicesEnabled: state.areTeamVoiceAlertsEnabled,
            availableTeamVoiceCount: notifications.availableTeamVoiceCount,
            status: currentStatus,
            lastChecked: lastCheckedText,
            slackCredentialStatus: slackCredentialStatusText,
            slackCredentialReady: slackCredentialReady,
            notificationStatus: notificationStatusText,
            notificationsReady: notificationsReady,
            automaticStartStatus: automaticStartStatusText,
            automaticStartReady: automaticStartReady
        )
    }

    private var currentAlertMode: TicketAlertMode {
        .channelMessage
    }

    private func showNotificationSetupAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Notifications Are Blocked"
        alert.informativeText = "Slack monitoring is working, but macOS is hiding its alerts. Enable Help Center Monitor in System Settings → Notifications."
        alert.addButton(withTitle: "Open Notification Settings")
        alert.addButton(withTitle: "Not Now")
        if alert.runModal() == .alertFirstButtonReturn {
            openNotificationSettings()
        }
    }

    private func showFallbackTicketAlert(title: String, body: String, link: String?) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = title
        alert.informativeText = "macOS notifications are blocked, so Help Center Monitor is showing this alert directly.\n\n\(String(body.prefix(500)))"
        alert.addButton(withTitle: "Open Message")
        alert.addButton(withTitle: "Dismiss")
        guard alert.runModal() == .alertFirstButtonReturn,
              let link,
              let url = URL(string: link) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func configureAutomaticStartStatus() {
        guard let service = Self.automaticStartService else {
            automaticStartMenuItem.title = "Automatic Start Available After Installation"
            automaticStartMenuItem.isEnabled = false
            automaticStartStatusText = "Install in Applications to enable automatic start"
            automaticStartReady = false
            updateControlWindow()
            return
        }
        switch service.status {
        case .enabled:
            automaticStartMenuItem.title = "Runs Automatically at Login"
            automaticStartMenuItem.isEnabled = false
            automaticStartStatusText = "Runs automatically at login"
            automaticStartReady = true
        case .requiresApproval:
            automaticStartMenuItem.title = "Allow Automatic Start…"
            automaticStartMenuItem.isEnabled = true
            automaticStartStatusText = "Automatic start needs approval in Login Items"
            automaticStartReady = false
        case .notRegistered:
            automaticStartMenuItem.title = "Automatic Start Not Registered"
            automaticStartMenuItem.isEnabled = true
            automaticStartStatusText = "Automatic start could not be registered"
            automaticStartReady = false
        case .notFound:
            automaticStartMenuItem.title = "Automatic Start Unavailable"
            automaticStartMenuItem.isEnabled = false
            automaticStartStatusText = "Automatic start is unavailable"
            automaticStartReady = false
        @unknown default:
            automaticStartMenuItem.title = "Check Automatic Start Settings…"
            automaticStartMenuItem.isEnabled = true
            automaticStartStatusText = "Automatic start could not be verified"
            automaticStartReady = false
        }
        updateControlWindow()
    }

    private func timestampValue(_ timestamp: String?) -> Double {
        Double(timestamp ?? "") ?? 0
    }

    private static var automaticStartService: SMAppService? {
        guard Bundle.main.bundleURL.pathExtension == "app",
              AppConfiguration.isInstalledBundle(Bundle.main.bundleURL) else {
            return nil
        }
        return SMAppService.mainApp
    }

}
