import Foundation

public struct NotificationReopenCoordinator {
    private var generation = 0
    private var suppressedUntil = Date.distantPast
    private var reopenShownGeneration: Int?

    public init() {}

    public mutating func requestReopen(
        hasVisibleWindows: Bool,
        at now: Date = Date()
    ) -> Int? {
        guard !hasVisibleWindows, now >= suppressedUntil else { return nil }
        generation += 1
        return generation
    }

    public func shouldShowReopen(generation candidate: Int, at now: Date = Date()) -> Bool {
        candidate == generation && now >= suppressedUntil
    }

    public mutating func markReopenShown(generation candidate: Int) {
        guard candidate == generation else { return }
        reopenShownGeneration = candidate
    }

    public mutating func notificationSelected(
        at now: Date = Date(),
        suppressionDuration: TimeInterval = 2
    ) -> Bool {
        generation += 1
        suppressedUntil = now.addingTimeInterval(max(suppressionDuration, 0))
        let shouldHideReopenWindow = reopenShownGeneration != nil
        reopenShownGeneration = nil
        return shouldHideReopenWindow
    }

    public mutating func clearReopenShown(generation candidate: Int) {
        guard reopenShownGeneration == candidate else { return }
        reopenShownGeneration = nil
    }
}
