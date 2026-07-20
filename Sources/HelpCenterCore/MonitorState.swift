import Foundation

public struct MonitorState {
    public static let supportedResponseDelayMinutes = [0, 2]
    public static let defaultResponseDelayMinutes = 0
    public static let pylonVerifiedResponseDelayMinutes = 2

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let delayMigrationCompleted = (
            defaults.object(forKey: Keys.responseDelayMigrationCompleted) as? NSNumber
        )?.boolValue ?? false
        let legacyAdvancedEnabled = defaults.object(
            forKey: Keys.legacyAdvancedMonitoringEnabled
        ) as? NSNumber
        let legacyAdvancedMinutes = defaults.object(
            forKey: Keys.legacyAdvancedResponseMinutes
        ) as? NSNumber
        defaults.register(defaults: [
            Keys.monitoringEnabled: true,
            Keys.responseDelayMinutes: Self.defaultResponseDelayMinutes,
            Keys.pollInterval: 30.0,
        ])
        if !delayMigrationCompleted {
            if let legacyAdvancedEnabled {
                let migratedMinutes = legacyAdvancedEnabled.boolValue
                    ? max(legacyAdvancedMinutes?.intValue ?? 1, 1)
                    : 0
                defaults.set(
                    Self.clampedResponseDelayMinutes(migratedMinutes),
                    forKey: Keys.responseDelayMinutes
                )
            }
            defaults.set(true, forKey: Keys.responseDelayMigrationCompleted)
        }

        let pylonModeMigrationCompleted = (
            defaults.object(forKey: Keys.pylonModeMigrationCompleted) as? NSNumber
        )?.boolValue ?? false
        if !pylonModeMigrationCompleted {
            let savedMinutes = defaults.integer(forKey: Keys.responseDelayMinutes)
            defaults.set(
                Self.clampedResponseDelayMinutes(savedMinutes),
                forKey: Keys.responseDelayMinutes
            )
            // Pending tickets belonged to the retired Assignee-based delayed
            // checker. A Pylon SLA breach is now the complete alert event, so
            // those local timers must never be replayed after this migration.
            defaults.removeObject(forKey: Keys.legacyPendingFirstTouchTickets)
            defaults.set(true, forKey: Keys.pylonModeMigrationCompleted)
        }
    }

    public var isMonitoringEnabled: Bool {
        get { defaults.bool(forKey: Keys.monitoringEnabled) }
        nonmutating set { defaults.set(newValue, forKey: Keys.monitoringEnabled) }
    }

    public var responseDelayMinutes: Int {
        get { Self.clampedResponseDelayMinutes(defaults.integer(forKey: Keys.responseDelayMinutes)) }
        nonmutating set {
            defaults.set(
                Self.clampedResponseDelayMinutes(newValue),
                forKey: Keys.responseDelayMinutes
            )
        }
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

    public static func clampedResponseDelayMinutes(_ value: Int) -> Int {
        value <= 0 ? 0 : pylonVerifiedResponseDelayMinutes
    }

    private enum Keys {
        static let monitoringEnabled = "monitoringEnabled"
        static let responseDelayMinutes = "responseDelayMinutes"
        static let responseDelayMigrationCompleted = "responseDelayMigrationCompleted"
        static let pylonModeMigrationCompleted = "pylonModeMigrationCompleted"
        static let legacyAdvancedMonitoringEnabled = "advancedMonitoringEnabled"
        static let legacyAdvancedResponseMinutes = "advancedResponseMinutes"
        static let pollInterval = "pollInterval"
        static let lastTimestampPrefix = "lastTimestamp."
        static let legacyPendingFirstTouchTickets = "pendingFirstTouchTickets"
    }
}
