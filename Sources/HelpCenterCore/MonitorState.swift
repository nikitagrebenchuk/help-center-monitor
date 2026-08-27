import Foundation

public struct MonitorState {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.monitoringEnabled: true,
            Keys.teamVoiceAlertsEnabled: false,
            Keys.pollInterval: 30.0,
        ])
        // The app now has a fixed source list. Remove state from the retired
        // Immediate/Pylon mode selector so it cannot affect later versions.
        defaults.removeObject(forKey: Keys.legacyResponseDelayMinutes)
        defaults.removeObject(forKey: Keys.legacyPendingFirstTouchTickets)
    }

    public var isMonitoringEnabled: Bool {
        get { defaults.bool(forKey: Keys.monitoringEnabled) }
        nonmutating set { defaults.set(newValue, forKey: Keys.monitoringEnabled) }
    }

    public var areTeamVoiceAlertsEnabled: Bool {
        get { defaults.bool(forKey: Keys.teamVoiceAlertsEnabled) }
        nonmutating set { defaults.set(newValue, forKey: Keys.teamVoiceAlertsEnabled) }
    }

    public var pollInterval: TimeInterval {
        get { max(defaults.double(forKey: Keys.pollInterval), 30) }
        nonmutating set { defaults.set(max(newValue, 30), forKey: Keys.pollInterval) }
    }

    public func lastTimestamp(for channel: String) -> String? {
        defaults.string(forKey: Keys.lastTimestampPrefix + channel)
    }

    public func setLastTimestamp(_ timestamp: String, for channel: String) {
        defaults.set(timestamp, forKey: Keys.lastTimestampPrefix + channel)
    }

    public func clearLastTimestamp(for channel: String) {
        defaults.removeObject(forKey: Keys.lastTimestampPrefix + channel)
    }

    private enum Keys {
        static let monitoringEnabled = "monitoringEnabled"
        static let teamVoiceAlertsEnabled = "teamVoiceAlertsEnabled"
        static let pollInterval = "pollInterval"
        static let lastTimestampPrefix = "lastTimestamp."
        static let legacyResponseDelayMinutes = "responseDelayMinutes"
        static let legacyPendingFirstTouchTickets = "pendingFirstTouchTickets"
    }
}
