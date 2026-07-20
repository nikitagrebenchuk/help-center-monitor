import AppKit
import Foundation
import HelpCenterCore
import HelpCenterSlack
import HelpCenterUI

private var failures = 0

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        failures += 1
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    }
}

let markdown = ":rotating_light: *Issue #11459* <https://example.com|View in Slack> <@U123> customer_name"
expect(
    SlackMessageParser.plainText(markdown) == "Issue #11459 View in Slack customer name",
    "Slack markdown is converted to plain text"
)

let attachmentMessage: [String: Any] = [
    "text": "",
    "attachments": [
        ["text": "No preview available"],
        ["title": "Customer needs a first touch"],
    ],
]
expect(
    SlackMessageParser.messageText(attachmentMessage) == "Customer needs a first touch",
    "attachment text is used when top-level text is empty"
)

let ticket: [String: Any] = [
    "ts": "100.200",
    "username": "Hardrockdigital",
    "text": "Issue #11459 Need to give first touch!",
    "attachments": [[
        "blocks": [[
            "text": "<https://usepylon.com/issues/1|Pylon> <https://example.slack.com/archives/C1/p100200|View in Slack>",
        ]],
    ]],
]
expect(SlackMessageParser.sender(ticket) == "Hardrockdigital", "sender is extracted")
expect(SlackMessageParser.issueNumber(ticket) == "11459", "issue number is extracted")
expect(SlackMessageParser.isTopLevelTicket(ticket), "top-level message is accepted")
expect(
    SlackMessageParser.bestLink(
        ticket,
        channel: "C1",
        workspaceURL: "https://example.slack.com"
    ) == "https://example.slack.com/archives/C1/p100200",
    "Slack deep link is preferred"
)
expect(
    !SlackMessageParser.isTopLevelTicket(["ts": "100.2", "thread_ts": "100.1"]),
    "thread reply is rejected"
)
expect(
    !SlackMessageParser.isTopLevelTicket(["ts": "100.3", "subtype": "channel_join"]),
    "ignored subtype is rejected"
)
expect(
    TicketAlertMode.immediate.spokenAnnouncement == "New ticket in help-center",
    "default monitoring keeps its original spoken announcement"
)
expect(
    TicketAlertMode.pylonVerifiedTwoMinutes.spokenAnnouncement
        == "Help Center message unanswered for 2 minutes",
    "Pylon-verified monitoring has a distinct SLA-breach announcement"
)

let teamsLink = "https://teams.microsoft.com/l/message/19:ticket@thread.tacv2/1784313124?groupId=group-id&tenantId=tenant-id"
let pylonBreach: [String: Any] = [
    "ts": "1784313124.547789",
    "username": "BetterHelp",
    "text": "Issue #11540 first response SLA breached after 2 minutes",
    "attachments": [[
        "blocks": [[
            "text": "<https://app.usepylon.com/issues?issueNumber=11540|View in Pylon> | <\(teamsLink.replacingOccurrences(of: "&", with: "&amp;"))|View in Microsoft Teams>",
        ]],
    ]],
]
expect(
    SlackMessageParser.pylonIssueNumber(pylonBreach) == "11540",
    "Pylon issue number is extracted from a verified SLA breach"
)
expect(
    SlackMessageParser.isPylonSLABreach(pylonBreach),
    "a Pylon issue with SLA-breached text is accepted"
)
expect(
    !SlackMessageParser.isPylonSLABreach([
        "ts": "1784313125.000000",
        "text": "Issue #11540 customer added more information",
    ]),
    "an ordinary issue update in the Pylon channel is rejected"
)
expect(
    !SlackMessageParser.isPylonSLABreach([
        "ts": "1784313126.000000",
        "text": "SLA breached after 2 minutes",
    ]),
    "an SLA phrase without a Pylon issue number is rejected"
)
expect(
    SlackMessageParser.bestLink(
        pylonBreach,
        channel: "C0BD2LDGYSZ",
        workspaceURL: "https://upwindsecurity.slack.com"
    ) == teamsLink,
    "a customer Teams link is preferred over the internal Pylon issue link"
)

let suite = "HelpCenterCoreSelfTest.\(UUID().uuidString)"
if let defaults = UserDefaults(suiteName: suite) {
    defer { defaults.removePersistentDomain(forName: suite) }
    let state = MonitorState(defaults: defaults)
    expect(state.isMonitoringEnabled, "monitoring defaults to enabled")
    expect(state.responseDelayMinutes == 0, "response delay defaults to immediate alerts")
    state.responseDelayMinutes = -1
    expect(state.responseDelayMinutes == 0, "response delay is clamped to zero minutes")
    state.responseDelayMinutes = 1
    expect(state.responseDelayMinutes == 2, "a positive legacy delay selects Pylon's two-minute mode")
    state.responseDelayMinutes = 11
    expect(state.responseDelayMinutes == 2, "only immediate and two-minute modes are supported")
    expect(state.pollInterval == 30, "poll interval defaults to 30 seconds")
    state.pollInterval = 1
    expect(state.pollInterval == 30, "poll interval is clamped to 30 seconds")
    state.pollInterval = 45
    expect(state.pollInterval == 45, "poll interval accepts values above 30 seconds")
    state.isMonitoringEnabled = false
    state.setLastTimestamp("123.456", for: "C1")
    let restored = MonitorState(defaults: defaults)
    expect(!restored.isMonitoringEnabled, "enablement is persisted")
    expect(restored.responseDelayMinutes == 2, "Pylon's two-minute mode is persisted")
    expect(restored.lastTimestamp(for: "C1") == "123.456", "timestamp is persisted")
    expect(restored.lastTimestamp(for: "C2") == nil, "timestamps are scoped per channel")
} else {
    expect(false, "isolated UserDefaults suite can be created")
}

let legacySuite = "HelpCenterCoreSelfTest.Legacy.\(UUID().uuidString)"
if let legacyDefaults = UserDefaults(suiteName: legacySuite) {
    defer { legacyDefaults.removePersistentDomain(forName: legacySuite) }
    legacyDefaults.set(true, forKey: "advancedMonitoringEnabled")
    legacyDefaults.set(7, forKey: "advancedResponseMinutes")
    let migrated = MonitorState(defaults: legacyDefaults)
    expect(
        migrated.responseDelayMinutes == 2,
        "the previous enabled advanced mode migrates to Pylon's verified two-minute mode"
    )
} else {
    expect(false, "legacy UserDefaults suite can be created")
}

let unsafeDelaySuite = "HelpCenterCoreSelfTest.UnsafeDelay.\(UUID().uuidString)"
if let unsafeDelayDefaults = UserDefaults(suiteName: unsafeDelaySuite) {
    defer { unsafeDelayDefaults.removePersistentDomain(forName: unsafeDelaySuite) }
    unsafeDelayDefaults.set(5, forKey: "responseDelayMinutes")
    unsafeDelayDefaults.set(true, forKey: "responseDelayMigrationCompleted")
    unsafeDelayDefaults.set(Data("retired pending state".utf8), forKey: "pendingFirstTouchTickets")
    let migrated = MonitorState(defaults: unsafeDelayDefaults)
    expect(migrated.responseDelayMinutes == 2, "a saved arbitrary delay migrates to two minutes")
    expect(
        unsafeDelayDefaults.object(forKey: "pendingFirstTouchTickets") == nil,
        "migration removes pending tickets created by the retired assignee heuristic"
    )
} else {
    expect(false, "unsafe-delay UserDefaults suite can be created")
}

final class MockSlackURLProtocol: URLProtocol {
    static var requestCount = 0

    private func bodyString() -> String {
        if let data = request.httpBody {
            return String(data: data, encoding: .utf8) ?? ""
        }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requestCount += 1
        let count = Self.requestCount
        let body = bodyString()
        let response: HTTPURLResponse
        let data: Data

        if count == 1 {
            expect(!body.contains("cursor="), "first Slack page has no cursor")
            response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            data = try! JSONSerialization.data(withJSONObject: [
                "ok": true,
                "messages": [
                    ["ts": "103.0", "text": "Issue #3"],
                    ["ts": "102.0", "text": "Issue #2"],
                ],
                "has_more": true,
                "response_metadata": ["next_cursor": "next-page"],
            ])
        } else if count == 2 {
            expect(body.contains("cursor=next-page"), "second Slack page uses its cursor")
            response = HTTPURLResponse(
                url: request.url!,
                statusCode: 429,
                httpVersion: nil,
                headerFields: ["Retry-After": "1"]
            )!
            data = Data()
        } else {
            expect(body.contains("cursor=next-page"), "rate-limited page retries the same cursor")
            response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            data = try! JSONSerialization.data(withJSONObject: [
                "ok": true,
                "messages": [["ts": "101.0", "text": "Issue #1"]],
                "has_more": false,
                "response_metadata": ["next_cursor": ""],
            ])
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

let networkCheck = DispatchGroup()
networkCheck.enter()
let configuration = URLSessionConfiguration.ephemeral
configuration.protocolClasses = [MockSlackURLProtocol.self]
let slack = SlackClient(
    apiBase: "https://mock.slack.test",
    session: URLSession(configuration: configuration)
)
Task {
    defer { networkCheck.leave() }
    do {
        let result = try await slack.fetchNewMessages(
            token: "xoxb-test",
            channel: "C1",
            oldest: "100.0",
            maximumPages: 5
        )
        expect(MockSlackURLProtocol.requestCount == 3, "rate-limited pagination resumes without restarting")
        expect(
            result.messages.compactMap { $0["ts"] as? String } == ["101.0", "102.0", "103.0"],
            "paginated Slack messages are returned oldest first"
        )
        expect(result.highestTimestamp == "103.0", "highest Slack timestamp spans every page")
    } catch {
        expect(false, "rate-limited pagination succeeds: \(error)")
    }
}
networkCheck.wait()

final class MockPylonFeedURLProtocol: URLProtocol {
    private func bodyString() -> String {
        if let data = request.httpBody {
            return String(data: data, encoding: .utf8) ?? ""
        }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = bodyString()
        expect(
            request.url?.path == "/conversations.history",
            "Pylon verification only reads the verified feed's history"
        )
        expect(
            body.contains("channel=C0BD2LDGYSZ"),
            "Pylon verification stays in the two-minute feed"
        )
        expect(body.contains("limit=15"), "Pylon verification inspects a bounded recent sample")

        var threadReply = pylonBreach
        threadReply["ts"] = "1784313125.000000"
        threadReply["thread_ts"] = "1784313124.547789"
        let ordinaryUpdate: [String: Any] = [
            "ts": "1784313126.000000",
            "text": "Issue #11541 customer added more information",
        ]
        let payload: [String: Any] = [
            "ok": true,
            "messages": [ordinaryUpdate, threadReply, pylonBreach],
        ]

        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
        )!
        let data = try! JSONSerialization.data(withJSONObject: payload)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

let pylonFeedCheck = DispatchGroup()
pylonFeedCheck.enter()
let pylonFeedConfiguration = URLSessionConfiguration.ephemeral
pylonFeedConfiguration.protocolClasses = [MockPylonFeedURLProtocol.self]
let pylonFeedSlack = SlackClient(
    apiBase: "https://mock.slack.test",
    session: URLSession(configuration: pylonFeedConfiguration)
)
Task {
    defer { pylonFeedCheck.leave() }
    do {
        let recent = try await pylonFeedSlack.fetchRecentMessages(
            token: "xoxb-test",
            channel: "C0BD2LDGYSZ"
        )
        expect(recent.count == 2, "Pylon verification ignores thread replies")
        expect(
            recent.contains(where: SlackMessageParser.isPylonSLABreach),
            "Pylon verification finds a recent verified SLA breach"
        )
    } catch {
        expect(false, "Pylon feed verification succeeds: \(error)")
    }
}
pylonFeedCheck.wait()

let applicationMenu = HelpCenterApplicationMenu.make()
let editMenu = applicationMenu.items
    .first(where: { $0.title == "Edit" })?
    .submenu
let pasteItem = editMenu?.items.first(where: { $0.title == "Paste" })
expect(pasteItem != nil, "application Edit menu contains Paste")
expect(pasteItem?.keyEquivalent == "v", "Paste uses the V key equivalent")
expect(
    pasteItem?.keyEquivalentModifierMask == [.command],
    "Paste uses the Command modifier"
)
expect(pasteItem?.action == #selector(NSText.paste(_:)), "Paste routes through the responder chain")
expect(pasteItem?.target == nil, "Paste targets the active secure field editor")

let activationTime = Date(timeIntervalSince1970: 1_000)
var reopenCoordinator = NotificationReopenCoordinator()
let ordinaryGeneration = reopenCoordinator.requestReopen(
    hasVisibleWindows: false,
    at: activationTime
)
expect(ordinaryGeneration != nil, "ordinary app reopen is scheduled")
if let ordinaryGeneration {
    expect(
        reopenCoordinator.shouldShowReopen(
            generation: ordinaryGeneration,
            at: activationTime.addingTimeInterval(0.25)
        ),
        "ordinary app reopen still shows the control panel"
    )
    reopenCoordinator.markReopenShown(generation: ordinaryGeneration)
    expect(
        reopenCoordinator.notificationSelected(
            at: activationTime.addingTimeInterval(0.3)
        ),
        "a notification hides a panel created by the same reopen race"
    )
    expect(
        !reopenCoordinator.shouldShowReopen(
            generation: ordinaryGeneration,
            at: activationTime.addingTimeInterval(0.31)
        ),
        "a notification invalidates a pending ordinary reopen"
    )
}
expect(
    reopenCoordinator.requestReopen(
        hasVisibleWindows: false,
        at: activationTime.addingTimeInterval(1)
    ) == nil,
    "notification activation suppresses the immediate macOS reopen callback"
)
expect(
    reopenCoordinator.requestReopen(
        hasVisibleWindows: false,
        at: activationTime.addingTimeInterval(3)
    ) != nil,
    "Spotlight reopen works again after notification suppression expires"
)

var preexistingPanelCoordinator = NotificationReopenCoordinator()
expect(
    preexistingPanelCoordinator.requestReopen(
        hasVisibleWindows: true,
        at: activationTime
    ) == nil,
    "an already-visible panel is not reopened"
)
expect(
    !preexistingPanelCoordinator.notificationSelected(at: activationTime),
    "notification activation does not hide a panel that was already open"
)

if failures > 0 {
    exit(1)
}
print("HelpCenterCoreSelfTest: all checks passed")
