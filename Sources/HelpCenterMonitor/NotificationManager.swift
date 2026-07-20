import AppKit
import Foundation
import HelpCenterCore
import UserNotifications

struct NotificationPermissionStatus {
    enum Kind {
        case ready
        case notDetermined
        case blocked
    }

    let kind: Kind
    let message: String

    var canPresentAlerts: Bool {
        kind == .ready
    }
}

enum NotificationDeliveryError: LocalizedError {
    case blocked(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .blocked(let message), .failed(let message):
            return message
        }
    }
}

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate, NSSpeechSynthesizerDelegate {
    private static let glassSoundPath = "/System/Library/Sounds/Glass.aiff"

    private let center = UNUserNotificationCenter.current()
    private var attentionSound: NSSound?
    private var speechSynthesizer: NSSpeechSynthesizer?
    private var queuedAttentionAlerts: [String] = []
    private var isSpeakingAttentionAlert = false
    var onStatusChange: ((NotificationPermissionStatus) -> Void)?
    var onDeliveryError: ((String) -> Void)?
    var onNotificationSelected: ((URL?) -> Void)?

    override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorization(completion: @escaping (NotificationPermissionStatus) -> Void) {
        currentStatus { [weak self] status in
            guard status.kind == .notDetermined else {
                self?.report(status)
                completion(status)
                return
            }

            self?.center.requestAuthorization(options: [.alert, .sound, .badge]) { _, error in
                if let error {
                    let blocked = NotificationPermissionStatus(
                        kind: .blocked,
                        message: "Notifications are blocked by macOS"
                    )
                    self?.onDeliveryError?("Notification permission error: \(error.localizedDescription)")
                    self?.report(blocked)
                    completion(blocked)
                    return
                }
                self?.currentStatus { refreshed in
                    self?.report(refreshed)
                    completion(refreshed)
                }
            }
        }
    }

    func refreshStatus(completion: ((NotificationPermissionStatus) -> Void)? = nil) {
        currentStatus { [weak self] status in
            self?.report(status)
            completion?(status)
        }
    }

    func send(
        title: String,
        body: String,
        link: String?,
        identifier: String,
        mode: TicketAlertMode,
        completion: @escaping (Result<Void, NotificationDeliveryError>) -> Void
    ) {
        playAttentionAlert(spokenMessage: mode.spokenAnnouncement)
        currentStatus { [weak self] status in
            guard let self else { return }
            self.report(status)
            guard status.canPresentAlerts else {
                completion(.failure(.blocked(status.message)))
                return
            }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = String(body.prefix(500))
            // Glass and the spoken announcement are played directly so the
            // alert matches the original Python monitor instead of using the
            // generic notification sound.
            content.sound = nil
            if let link {
                content.userInfo["link"] = link
            }

            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: nil
            )
            self.center.add(request) { [weak self] error in
                if let error {
                    let message = "Notification failed: \(error.localizedDescription)"
                    self?.onDeliveryError?(message)
                    completion(.failure(.failed(message)))
                } else {
                    completion(.success(()))
                }
            }
        }
    }

    func sendTest(
        mode: TicketAlertMode,
        completion: @escaping (Result<Void, NotificationDeliveryError>) -> Void
    ) {
        send(
            title: mode.testTitle,
            body: mode.testBody,
            link: nil,
            identifier: "help-center-monitor-test-\(UUID().uuidString)",
            mode: mode,
            completion: completion
        )
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let url = (response.notification.request.content.userInfo["link"] as? String)
            .flatMap(URL.init(string:))
        let selectionHandler = onNotificationSelected
        DispatchQueue.main.async {
            selectionHandler?(url)
            completionHandler()
        }
    }

    private func currentStatus(completion: @escaping (NotificationPermissionStatus) -> Void) {
        center.getNotificationSettings { settings in
            let status: NotificationPermissionStatus
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                if settings.alertSetting == .enabled {
                    status = NotificationPermissionStatus(
                        kind: .ready,
                        message: "Notifications are enabled"
                    )
                } else {
                    status = NotificationPermissionStatus(
                        kind: .blocked,
                        message: "Notification alerts are disabled in macOS Settings"
                    )
                }
            case .notDetermined:
                status = NotificationPermissionStatus(
                    kind: .notDetermined,
                    message: "Waiting for notification permission"
                )
            case .denied:
                status = NotificationPermissionStatus(
                    kind: .blocked,
                    message: "Notifications are blocked by macOS"
                )
            case .ephemeral:
                status = NotificationPermissionStatus(
                    kind: .ready,
                    message: "Notifications are enabled"
                )
            @unknown default:
                status = NotificationPermissionStatus(
                    kind: .blocked,
                    message: "Notification permission could not be verified"
                )
            }
            completion(status)
        }
    }

    private func report(_ status: NotificationPermissionStatus) {
        onStatusChange?(status)
    }

    private func playAttentionAlert(spokenMessage: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.queuedAttentionAlerts.append(spokenMessage)
            self.playNextAttentionAlertIfNeeded()
        }
    }

    private func playNextAttentionAlertIfNeeded() {
        guard !isSpeakingAttentionAlert, !queuedAttentionAlerts.isEmpty else { return }
        let spokenMessage = queuedAttentionAlerts.removeFirst()

        if attentionSound == nil {
            attentionSound = NSSound(
                contentsOfFile: Self.glassSoundPath,
                byReference: true
            )
            attentionSound?.volume = 1.0
        }
        attentionSound?.stop()
        attentionSound?.play()

        if speechSynthesizer == nil {
            speechSynthesizer = NSSpeechSynthesizer(voice: nil)
            speechSynthesizer?.volume = 1.0
            speechSynthesizer?.delegate = self
        }
        isSpeakingAttentionAlert = speechSynthesizer?.startSpeaking(spokenMessage) == true
        if !isSpeakingAttentionAlert {
            DispatchQueue.main.async { [weak self] in
                self?.playNextAttentionAlertIfNeeded()
            }
        }
    }

    func speechSynthesizer(
        _ sender: NSSpeechSynthesizer,
        didFinishSpeaking finishedSpeaking: Bool
    ) {
        isSpeakingAttentionAlert = false
        playNextAttentionAlertIfNeeded()
    }
}
