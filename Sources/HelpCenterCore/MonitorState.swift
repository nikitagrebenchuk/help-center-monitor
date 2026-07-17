import Foundation

public struct MonitorState {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.monitoringEnabled: true,
            Keys.pollInterval: 30.0,
        ])
    }

    public var isMonitoringEnabled: Bool {
        get { defaults.bool(forKey: Keys.monitoringEnabled) }
        nonmutating set { defaults.set(newValue, forKey: Keys.monitoringEnabled) }
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
        static let pollInterval = "pollInterval"
        static let lastTimestampPrefix = "lastTimestamp."
    }
}
