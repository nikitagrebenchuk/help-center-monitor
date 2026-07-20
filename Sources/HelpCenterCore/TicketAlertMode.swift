public enum TicketAlertMode {
    case immediate
    case pylonVerifiedTwoMinutes

    public var spokenAnnouncement: String {
        switch self {
        case .immediate:
            return "New ticket in help-center"
        case .pylonVerifiedTwoMinutes:
            return "Help Center message unanswered for 2 minutes"
        }
    }

    public var testTitle: String {
        switch self {
        case .immediate:
            return "Help Center Monitor"
        case .pylonVerifiedTwoMinutes:
            return "Pylon-Verified Help Center Test"
        }
    }

    public var testBody: String {
        switch self {
        case .immediate:
            return "Test notification — default alerts are working."
        case .pylonVerifiedTwoMinutes:
            return "Test notification — this is how a Pylon-verified two-minute SLA breach sounds."
        }
    }
}
