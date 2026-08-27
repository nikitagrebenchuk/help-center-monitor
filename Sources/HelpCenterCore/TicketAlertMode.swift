public enum TicketAlertMode {
    case channelMessage

    public var spokenAnnouncement: String {
        "New message in the alert channel"
    }

    public var testTitle: String {
        "Help Center Monitor"
    }

    public var testBody: String {
        "Test notification — Slack channel alerts are working."
    }
}
