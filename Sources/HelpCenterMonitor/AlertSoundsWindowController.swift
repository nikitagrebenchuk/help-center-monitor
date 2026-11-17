import AppKit
import Foundation
import HelpCenterCore
import UniformTypeIdentifiers

/// The Alert Sounds window: pick, play or reset a custom file for each alert
/// sound (AlertSoundStore copies and plays them). Same layout and wording as
/// the help-center-agents extension's Alert sounds page.
@MainActor
final class AlertSoundsWindowController: NSWindowController, NSWindowDelegate {
    private let notifications: NotificationManager
    private let spokenMessage: String
    private let onChange: () -> Void
    private var errors: [AlertSoundSlot: String] = [:]
    private let slotsStack = NSStackView()

    init(notifications: NotificationManager, spokenMessage: String, onChange: @escaping () -> Void) {
        self.notifications = notifications
        self.spokenMessage = spokenMessage
        self.onChange = onChange

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Alert Sounds"
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.delegate = self
        buildContent()
        render()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func present() {
        render()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    private func buildContent() {
        guard let contentView = window?.contentView else { return }

        let intro = NSTextField(
            wrappingLabelWithString: "Replace either alert sound with your own MP3, WAV, M4A, AIFF or CAF file (2 MB and \(Int(AlertSoundRules.maxSeconds)) seconds at most). Without a file, the built-in sound plays."
        )
        intro.font = .systemFont(ofSize: 12)
        intro.textColor = .secondaryLabelColor

        slotsStack.orientation = .vertical
        slotsStack.alignment = .leading
        slotsStack.spacing = 14

        let root = NSStackView(views: [intro, slotsStack])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 16
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            root.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -18),
            intro.widthAnchor.constraint(equalTo: root.widthAnchor),
            slotsStack.widthAnchor.constraint(equalTo: root.widthAnchor),
        ])
    }

    private func render() {
        slotsStack.arrangedSubviews.forEach {
            slotsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        for (index, slot) in AlertSoundSlot.allCases.enumerated() {
            if index > 0 {
                let divider = NSBox()
                divider.boxType = .separator
                slotsStack.addArrangedSubview(divider)
                divider.widthAnchor.constraint(equalTo: slotsStack.widthAnchor).isActive = true
            }
            let row = makeRow(for: slot)
            slotsStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: slotsStack.widthAnchor).isActive = true
        }
        window?.layoutIfNeeded()
        if let window, let contentView = window.contentView {
            let fitting = contentView.fittingSize
            window.setContentSize(NSSize(width: 520, height: max(fitting.height, 200)))
        }
    }

    private func makeRow(for slot: AlertSoundSlot) -> NSView {
        let file = notifications.alertSounds.file(for: slot)

        let title = NSTextField(labelWithString: slot.title)
        title.font = .systemFont(ofSize: 13, weight: .semibold)

        let fileLabel = NSTextField(labelWithString: file?.name ?? "Built-in sound")
        fileLabel.font = .systemFont(ofSize: 12, weight: file == nil ? .regular : .medium)
        fileLabel.textColor = file == nil ? .secondaryLabelColor : .controlAccentColor
        fileLabel.lineBreakMode = .byTruncatingMiddle
        fileLabel.toolTip = file?.name

        let hint = NSTextField(wrappingLabelWithString: slot.hint)
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor

        var textViews: [NSView] = [title, fileLabel, hint]
        if let error = errors[slot] {
            let errorLabel = NSTextField(wrappingLabelWithString: error)
            errorLabel.font = .systemFont(ofSize: 11)
            errorLabel.textColor = .systemRed
            textViews.append(errorLabel)
        }
        let text = NSStackView(views: textViews)
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 3
        text.setContentHuggingPriority(.defaultLow, for: .horizontal)
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let play = makeButton("Play", slot: slot, action: #selector(playSlot(_:)))
        let choose = makeButton(file == nil ? "Choose File…" : "Change…", slot: slot, action: #selector(chooseFile(_:)))
        if file == nil {
            choose.bezelColor = .controlAccentColor
        }
        var buttons: [NSView] = [play, choose]
        if file != nil {
            buttons.append(makeButton("Use Built-in", slot: slot, action: #selector(resetSlot(_:))))
        }
        let actions = NSStackView(views: buttons)
        actions.orientation = .horizontal
        actions.spacing = 6
        actions.setContentHuggingPriority(.required, for: .horizontal)
        actions.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = NSStackView(views: [text, actions])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 12
        row.distribution = .fill
        return row
    }

    private func makeButton(_ title: String, slot: AlertSoundSlot, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.identifier = NSUserInterfaceItemIdentifier(slot.rawValue)
        return button
    }

    private func slot(of sender: NSButton) -> AlertSoundSlot? {
        sender.identifier.flatMap { AlertSoundSlot(rawValue: $0.rawValue) }
    }

    @objc private func playSlot(_ sender: NSButton) {
        guard let slot = slot(of: sender) else { return }
        notifications.previewSound(slot, spokenMessage: spokenMessage)
    }

    @objc private func chooseFile(_ sender: NSButton) {
        guard let slot = slot(of: sender), let window else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose a sound for \u{201C}\(slot.title)\u{201D}"
        panel.prompt = "Use Sound"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = AlertSoundRules.supportedExtensions
            .compactMap { UTType(filenameExtension: $0) }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated {
                self?.save(url, for: slot)
            }
        }
    }

    private func save(_ url: URL, for slot: AlertSoundSlot) {
        errors[slot] = nil
        switch notifications.alertSounds.pick(url, for: slot) {
        case .saved:
            // Play what was just saved so a wrong pick is obvious right away.
            notifications.previewSound(slot, spokenMessage: spokenMessage)
        case .rejected(let message):
            errors[slot] = message
        }
        render()
        onChange()
    }

    @objc private func resetSlot(_ sender: NSButton) {
        guard let slot = slot(of: sender) else { return }
        errors[slot] = nil
        notifications.alertSounds.reset(slot)
        render()
        onChange()
    }
}
