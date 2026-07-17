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

let suite = "HelpCenterCoreSelfTest.\(UUID().uuidString)"
if let defaults = UserDefaults(suiteName: suite) {
    defer { defaults.removePersistentDomain(forName: suite) }
    let state = MonitorState(defaults: defaults)
    expect(state.isMonitoringEnabled, "monitoring defaults to enabled")
    expect(state.pollInterval == 30, "poll interval defaults to 30 seconds")
    state.pollInterval = 1
    expect(state.pollInterval == 30, "poll interval is clamped to 30 seconds")
    state.pollInterval = 45
    expect(state.pollInterval == 45, "poll interval accepts values above 30 seconds")
    state.isMonitoringEnabled = false
    state.setLastTimestamp("123.456", for: "C1")
    let restored = MonitorState(defaults: defaults)
    expect(!restored.isMonitoringEnabled, "enablement is persisted")
    expect(restored.lastTimestamp(for: "C1") == "123.456", "timestamp is persisted")
    expect(restored.lastTimestamp(for: "C2") == nil, "timestamps are scoped per channel")
} else {
    expect(false, "isolated UserDefaults suite can be created")
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
