import AppKit
import Foundation

@MainActor
private final class GreenSwitch: NSControl {
    var state: NSControl.StateValue = .off {
        didSet {
            needsDisplay = true
            setAccessibilityValue(state == .on)
        }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 42, height: 24)
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityRole(.checkBox)
        setAccessibilityLabel("Enable monitoring")
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let trackRect = bounds.insetBy(dx: 0, dy: 1)
        let track = NSBezierPath(
            roundedRect: trackRect,
            xRadius: trackRect.height / 2,
            yRadius: trackRect.height / 2
        )
        let isOn = state == .on
        (isOn ? NSColor.systemGreen : NSColor.systemGray).setFill()
        track.fill()

        let knobDiameter = trackRect.height - 4
        let knobX = isOn
            ? trackRect.maxX - knobDiameter - 2
            : trackRect.minX + 2
        let knobRect = NSRect(
            x: knobX,
            y: trackRect.midY - knobDiameter / 2,
            width: knobDiameter,
            height: knobDiameter
        )

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
        shadow.shadowBlurRadius = 1.5
        shadow.shadowOffset = NSSize(width: 0, height: -0.5)
        shadow.set()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: knobRect).fill()
        NSGraphicsContext.restoreGraphicsState()

        if window?.firstResponder === self {
            NSColor.keyboardFocusIndicatorColor.setStroke()
            let focus = NSBezierPath(
                roundedRect: trackRect.insetBy(dx: -2, dy: -2),
                xRadius: trackRect.height / 2 + 2,
                yRadius: trackRect.height / 2 + 2
            )
            focus.lineWidth = 2
            focus.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        toggle()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 {
            toggle()
        } else {
            super.keyDown(with: event)
        }
    }

    private func toggle() {
        state = state == .on ? .off : .on
        sendAction(action, to: target)
    }
}

private final class StatusCardView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)
        NSColor.controlBackgroundColor.setFill()
        path.fill()
        NSColor.separatorColor.withAlphaComponent(0.55).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

@MainActor
final class ControlWindowController: NSWindowController, NSWindowDelegate {
    private let monitoredChannels: String
    private let onSetEnabled: (Bool) -> Void
    private let onSetTeamVoicesEnabled: (Bool) -> Void
    private let onSendTest: () -> Void
    private let onOpenNotificationSettings: () -> Void
    private let onConfigureSlack: () -> Void

    private let monitoringSwitch = GreenSwitch()
    private let monitoringDetailLabel = NSTextField(labelWithString: "")
    private let teamVoicesSwitch = GreenSwitch()
    private let teamVoicesDetailLabel = NSTextField(labelWithString: "")
    private let monitoringDot = NSTextField(labelWithString: "●")
    private let slackValueLabel = NSTextField(labelWithString: "")
    private let lastCheckedLabel = NSTextField(labelWithString: "")
    private let credentialsDot = NSTextField(labelWithString: "●")
    private let credentialsValueLabel = NSTextField(labelWithString: "")
    private let credentialsDetailLabel = NSTextField(wrappingLabelWithString: "")
    private let configureSlackButton = NSButton()
    private let alertsDot = NSTextField(labelWithString: "●")
    private let alertsValueLabel = NSTextField(labelWithString: "")
    private let notificationDetailLabel = NSTextField(wrappingLabelWithString: "")
    private let notificationSettingsButton = NSButton()
    private let testButton = NSButton()
    private let automaticStartIcon = NSImageView()
    private let automaticStartLabel = NSTextField(labelWithString: "")

    init(
        monitoredChannels: String,
        onSetEnabled: @escaping (Bool) -> Void,
        onSetTeamVoicesEnabled: @escaping (Bool) -> Void,
        onSendTest: @escaping () -> Void,
        onOpenNotificationSettings: @escaping () -> Void,
        onConfigureSlack: @escaping () -> Void
    ) {
        self.monitoredChannels = monitoredChannels
        self.onSetEnabled = onSetEnabled
        self.onSetTeamVoicesEnabled = onSetTeamVoicesEnabled
        self.onSendTest = onSendTest
        self.onOpenNotificationSettings = onOpenNotificationSettings
        self.onConfigureSlack = onConfigureSlack

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Help Center Monitor"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.center()

        let background = NSVisualEffectView(frame: window.contentView?.bounds ?? .zero)
        background.material = .underWindowBackground
        background.blendingMode = .behindWindow
        background.state = .active
        background.autoresizingMask = [.width, .height]
        window.contentView = background

        super.init(window: window)
        window.delegate = self
        buildContent(in: background)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(
        enabled: Bool,
        teamVoicesEnabled: Bool,
        availableTeamVoiceCount: Int,
        status: String,
        lastChecked: String?,
        slackCredentialStatus: String,
        slackCredentialReady: Bool,
        notificationStatus: String,
        notificationsReady: Bool,
        automaticStartStatus: String,
        automaticStartReady: Bool
    ) {
        monitoringSwitch.state = enabled ? .on : .off
        teamVoicesSwitch.state = teamVoicesEnabled ? .on : .off
        if !enabled {
            monitoringDetailLabel.stringValue = "Paused — no Slack checks are being made"
        } else {
            monitoringDetailLabel.stringValue = "Watches Slack channels \(monitoredChannels)"
        }
        if availableTeamVoiceCount == 0 {
            teamVoicesDetailLabel.stringValue = "No teammate recordings are bundled; the default voice will be used"
        } else {
            let recordingLabel = availableTeamVoiceCount == 1 ? "recording" : "recordings"
            teamVoicesDetailLabel.stringValue = "Randomly plays one of \(availableTeamVoiceCount) teammate \(recordingLabel)"
        }
        testButton.title = teamVoicesEnabled ? "Test Team Voice Alert" : "Send Test Alert"

        let normalizedStatus = status.lowercased()
        let slackHealthy = enabled && normalizedStatus.contains("monitoring")
        let slackProblem = normalizedStatus.contains("error")
            || normalizedStatus.contains("offline")
            || normalizedStatus.contains("rate limited")
        monitoringDot.textColor = !enabled
            ? .tertiaryLabelColor
            : (slackHealthy ? .systemGreen : (slackProblem ? .systemRed : .systemOrange))
        slackValueLabel.stringValue = enabled ? status : "Paused"
        slackValueLabel.textColor = slackProblem ? .systemRed : .secondaryLabelColor
        lastCheckedLabel.stringValue = "Last checked \(lastChecked ?? "—")"

        credentialsDot.textColor = slackCredentialReady ? .systemGreen : .systemRed
        credentialsValueLabel.stringValue = slackCredentialReady ? "Secured" : "Setup required"
        credentialsValueLabel.textColor = slackCredentialReady ? .secondaryLabelColor : .systemRed
        credentialsDetailLabel.stringValue = slackCredentialStatus
        credentialsDetailLabel.textColor = slackCredentialReady ? .tertiaryLabelColor : .systemRed
        configureSlackButton.isHidden = slackCredentialReady

        alertsDot.textColor = notificationsReady ? .systemGreen : .systemRed
        alertsValueLabel.stringValue = notificationsReady ? "Enabled" : "Needs attention"
        alertsValueLabel.textColor = notificationsReady ? .secondaryLabelColor : .systemRed
        notificationDetailLabel.stringValue = notificationStatus
        notificationDetailLabel.isHidden = notificationsReady
        notificationSettingsButton.isHidden = notificationsReady

        automaticStartIcon.image = NSImage(
            systemSymbolName: automaticStartReady
                ? "checkmark.circle.fill"
                : "exclamationmark.triangle.fill",
            accessibilityDescription: automaticStartStatus
        )
        automaticStartIcon.contentTintColor = automaticStartReady ? .systemGreen : .systemOrange
        automaticStartLabel.stringValue = "\(automaticStartStatus) — closing this window does not stop monitoring"
    }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    private func buildContent(in contentView: NSView) {
        let iconView = NSImageView()
        iconView.image = NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: "Help Center Monitor")
        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)

        let descriptionLabel = NSTextField(
            wrappingLabelWithString: "Never miss a customer message waiting for our response."
        )
        descriptionLabel.font = .systemFont(ofSize: 13)
        descriptionLabel.textColor = .secondaryLabelColor

        let titleStack = NSStackView(views: [titleLabel, descriptionLabel])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 3

        let header = NSStackView(views: [iconView, titleStack])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 14

        let card = StatusCardView()
        card.translatesAutoresizingMaskIntoConstraints = false

        let monitoringTitle = NSTextField(labelWithString: "Monitoring")
        monitoringTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        monitoringDetailLabel.font = .systemFont(ofSize: 12)
        monitoringDetailLabel.textColor = .secondaryLabelColor

        let monitoringText = NSStackView(views: [monitoringTitle, monitoringDetailLabel])
        monitoringText.orientation = .vertical
        monitoringText.alignment = .leading
        monitoringText.spacing = 3

        monitoringSwitch.target = self
        monitoringSwitch.action = #selector(monitoringSwitchChanged)
        monitoringSwitch.isEnabled = true
        monitoringSwitch.translatesAutoresizingMaskIntoConstraints = false

        let monitoringRow = NSStackView(views: [monitoringText, monitoringSwitch])
        monitoringRow.orientation = .horizontal
        monitoringRow.alignment = .centerY
        monitoringRow.distribution = .fill

        let teamVoicesTitle = NSTextField(labelWithString: "Team voice-overs")
        teamVoicesTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        teamVoicesDetailLabel.font = .systemFont(ofSize: 12)
        teamVoicesDetailLabel.textColor = .secondaryLabelColor
        teamVoicesDetailLabel.lineBreakMode = .byTruncatingTail

        let teamVoicesText = NSStackView(views: [teamVoicesTitle, teamVoicesDetailLabel])
        teamVoicesText.orientation = .vertical
        teamVoicesText.alignment = .leading
        teamVoicesText.spacing = 3

        teamVoicesSwitch.target = self
        teamVoicesSwitch.action = #selector(teamVoicesSwitchChanged)
        teamVoicesSwitch.isEnabled = true
        teamVoicesSwitch.setAccessibilityLabel("Enable team voice-over alerts")
        teamVoicesSwitch.translatesAutoresizingMaskIntoConstraints = false

        let teamVoicesRow = NSStackView(views: [teamVoicesText, teamVoicesSwitch])
        teamVoicesRow.orientation = .horizontal
        teamVoicesRow.alignment = .centerY
        teamVoicesRow.distribution = .fill

        monitoringDot.font = .systemFont(ofSize: 10)
        credentialsDot.font = .systemFont(ofSize: 10)
        alertsDot.font = .systemFont(ofSize: 10)

        let slackTitle = NSTextField(labelWithString: "Slack connection")
        slackTitle.font = .systemFont(ofSize: 13, weight: .medium)
        let slackLeft = NSStackView(views: [monitoringDot, slackTitle])
        slackLeft.orientation = .horizontal
        slackLeft.alignment = .centerY
        slackLeft.spacing = 8
        slackValueLabel.font = .systemFont(ofSize: 13, weight: .medium)
        slackValueLabel.alignment = .right

        let slackRow = NSStackView(views: [slackLeft, slackValueLabel])
        slackRow.orientation = .horizontal
        slackRow.alignment = .centerY
        slackRow.distribution = .fill

        lastCheckedLabel.font = .systemFont(ofSize: 11)
        lastCheckedLabel.textColor = .tertiaryLabelColor

        let credentialsTitle = NSTextField(labelWithString: "Slack credentials")
        credentialsTitle.font = .systemFont(ofSize: 13, weight: .medium)
        let credentialsLeft = NSStackView(views: [credentialsDot, credentialsTitle])
        credentialsLeft.orientation = .horizontal
        credentialsLeft.alignment = .centerY
        credentialsLeft.spacing = 8
        credentialsValueLabel.font = .systemFont(ofSize: 13, weight: .medium)
        credentialsValueLabel.alignment = .right

        let credentialsRow = NSStackView(views: [credentialsLeft, credentialsValueLabel])
        credentialsRow.orientation = .horizontal
        credentialsRow.alignment = .centerY
        credentialsRow.distribution = .fill

        credentialsDetailLabel.font = .systemFont(ofSize: 11)
        credentialsDetailLabel.maximumNumberOfLines = 2

        configureSlackButton.title = "Set Up Slack Access"
        configureSlackButton.target = self
        configureSlackButton.action = #selector(configureSlack)
        configureSlackButton.bezelStyle = .rounded

        let alertsTitle = NSTextField(labelWithString: "Audible alerts")
        alertsTitle.font = .systemFont(ofSize: 13, weight: .medium)
        let alertsLeft = NSStackView(views: [alertsDot, alertsTitle])
        alertsLeft.orientation = .horizontal
        alertsLeft.alignment = .centerY
        alertsLeft.spacing = 8
        alertsValueLabel.font = .systemFont(ofSize: 13, weight: .medium)
        alertsValueLabel.alignment = .right

        let alertsRow = NSStackView(views: [alertsLeft, alertsValueLabel])
        alertsRow.orientation = .horizontal
        alertsRow.alignment = .centerY
        alertsRow.distribution = .fill

        notificationDetailLabel.font = .systemFont(ofSize: 11)
        notificationDetailLabel.textColor = .systemRed
        notificationDetailLabel.maximumNumberOfLines = 2

        let firstDivider = makeDivider()
        let secondDivider = makeDivider()
        let thirdDivider = makeDivider()
        let cardStack = NSStackView(views: [
            monitoringRow,
            teamVoicesRow,
            firstDivider,
            slackRow,
            lastCheckedLabel,
            secondDivider,
            credentialsRow,
            credentialsDetailLabel,
            configureSlackButton,
            thirdDivider,
            alertsRow,
            notificationDetailLabel,
        ])
        cardStack.orientation = .vertical
        cardStack.alignment = .leading
        cardStack.spacing = 9
        cardStack.setCustomSpacing(13, after: monitoringRow)
        cardStack.setCustomSpacing(13, after: teamVoicesRow)
        cardStack.setCustomSpacing(13, after: firstDivider)
        cardStack.setCustomSpacing(13, after: secondDivider)
        cardStack.setCustomSpacing(13, after: thirdDivider)
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(cardStack)

        testButton.title = "Send Test Alert"
        testButton.target = self
        testButton.action = #selector(sendTest)
        testButton.bezelStyle = .rounded
        testButton.controlSize = .large
        testButton.image = NSImage(
            systemSymbolName: "speaker.wave.2.fill",
            accessibilityDescription: "Test alert"
        )
        testButton.imagePosition = .imageLeading

        notificationSettingsButton.title = "Fix Notification Settings"
        notificationSettingsButton.target = self
        notificationSettingsButton.action = #selector(openNotificationSettings)
        notificationSettingsButton.bezelStyle = .rounded
        notificationSettingsButton.controlSize = .large

        let actions = NSStackView(views: [testButton, notificationSettingsButton])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 10

        automaticStartLabel.font = .systemFont(ofSize: 11)
        automaticStartLabel.textColor = .tertiaryLabelColor
        automaticStartLabel.lineBreakMode = .byTruncatingTail
        let footer = NSStackView(views: [automaticStartIcon, automaticStartLabel])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 6

        let root = NSStackView(views: [header, card, actions, footer])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 16
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 50),
            root.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20),

            iconView.widthAnchor.constraint(equalToConstant: 54),
            iconView.heightAnchor.constraint(equalToConstant: 54),
            header.widthAnchor.constraint(equalTo: root.widthAnchor),

            card.widthAnchor.constraint(equalTo: root.widthAnchor),
            cardStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            cardStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            cardStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 15),
            cardStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -15),
            monitoringRow.widthAnchor.constraint(equalTo: cardStack.widthAnchor),
            teamVoicesRow.widthAnchor.constraint(equalTo: cardStack.widthAnchor),
            slackRow.widthAnchor.constraint(equalTo: cardStack.widthAnchor),
            credentialsRow.widthAnchor.constraint(equalTo: cardStack.widthAnchor),
            alertsRow.widthAnchor.constraint(equalTo: cardStack.widthAnchor),
            firstDivider.widthAnchor.constraint(equalTo: cardStack.widthAnchor),
            secondDivider.widthAnchor.constraint(equalTo: cardStack.widthAnchor),
            thirdDivider.widthAnchor.constraint(equalTo: cardStack.widthAnchor),
            credentialsDetailLabel.widthAnchor.constraint(equalTo: cardStack.widthAnchor),
            notificationDetailLabel.widthAnchor.constraint(equalTo: cardStack.widthAnchor),

            monitoringSwitch.widthAnchor.constraint(equalToConstant: 42),
            monitoringSwitch.heightAnchor.constraint(equalToConstant: 24),
            teamVoicesSwitch.widthAnchor.constraint(equalToConstant: 42),
            teamVoicesSwitch.heightAnchor.constraint(equalToConstant: 24),
            actions.widthAnchor.constraint(lessThanOrEqualTo: root.widthAnchor),
        ])
    }

    private func makeDivider() -> NSBox {
        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return divider
    }

    @objc private func monitoringSwitchChanged() {
        onSetEnabled(monitoringSwitch.state == .on)
    }

    @objc private func teamVoicesSwitchChanged() {
        onSetTeamVoicesEnabled(teamVoicesSwitch.state == .on)
    }

    @objc private func sendTest() {
        onSendTest()
    }

    @objc private func openNotificationSettings() {
        onOpenNotificationSettings()
    }

    @objc private func configureSlack() {
        onConfigureSlack()
    }
}
