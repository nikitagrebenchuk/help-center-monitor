import AppKit
import Foundation
import HelpCenterAWS
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

expect(
    AWSSecretsManagerTokenProvider.token(fromSecretString: "  xoxb-plain-test-token  ")
        == "xoxb-plain-test-token",
    "AWS plain-text secret yields the Slack bot token"
)
expect(
    AWSSecretsManagerTokenProvider.token(
        fromSecretString: #"{"SLACK_BOT_TOKEN":"xoxb-json-test-token"}"#
    ) == "xoxb-json-test-token",
    "AWS JSON secret yields the Slack bot token"
)
expect(
    AWSSecretsManagerTokenProvider.token(
        fromSecretString: #"{"monitoring":{"credential":"xoxb-nested-test-token"}}"#
    ) == "xoxb-nested-test-token",
    "AWS nested JSON secret yields the Slack bot token"
)
expect(
    AWSSecretsManagerTokenProvider.token(fromSecretString: "xoxp-not-a-bot-token") == nil,
    "AWS secret rejects non-bot Slack tokens"
)

let awsFixtureDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("HelpCenterAWSFixture-\(UUID().uuidString)", isDirectory: true)
defer { try? FileManager.default.removeItem(at: awsFixtureDirectory) }
do {
    try FileManager.default.createDirectory(
        at: awsFixtureDirectory,
        withIntermediateDirectories: true
    )
    let executable = awsFixtureDirectory.appendingPathComponent("aws")
    try Data(
        "#!/bin/zsh\nprint -r -- '{\"SLACK_BOT_TOKEN\":\"xoxb-process-test-token\"}'\n".utf8
    ).write(to: executable)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o700],
        ofItemAtPath: executable.path
    )
    let provider = AWSSecretsManagerTokenProvider(
        secretID: "/test/secret",
        region: "us-east-1",
        profile: "test-profile",
        executableCandidates: [executable]
    )
    let fetchedToken = try provider.fetchToken()
    expect(
        fetchedToken == "xoxb-process-test-token",
        "AWS CLI subprocess output is loaded without exposing the token"
    )
} catch {
    expect(false, "AWS CLI subprocess fixture succeeds: \(error)")
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
    TicketAlertMode.channelMessage.spokenAnnouncement == "New message in the alert channel",
    "single-channel monitoring uses the alert-channel announcement"
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
    expect(!state.areTeamVoiceAlertsEnabled, "team voice alerts default to disabled")
    expect(state.pollInterval == 30, "poll interval defaults to 30 seconds")
    state.pollInterval = 1
    expect(state.pollInterval == 30, "poll interval is clamped to 30 seconds")
    state.pollInterval = 45
    expect(state.pollInterval == 45, "poll interval accepts values above 30 seconds")
    state.isMonitoringEnabled = false
    state.areTeamVoiceAlertsEnabled = true
    state.setLastTimestamp("123.456", for: "C1")
    let restored = MonitorState(defaults: defaults)
    expect(!restored.isMonitoringEnabled, "enablement is persisted")
    expect(restored.areTeamVoiceAlertsEnabled, "team voice preference is persisted")
    expect(restored.lastTimestamp(for: "C1") == "123.456", "timestamp is persisted")
    expect(restored.lastTimestamp(for: "C2") == nil, "timestamps are scoped per channel")
} else {
    expect(false, "isolated UserDefaults suite can be created")
}

let unsafeDelaySuite = "HelpCenterCoreSelfTest.UnsafeDelay.\(UUID().uuidString)"
if let unsafeDelayDefaults = UserDefaults(suiteName: unsafeDelaySuite) {
    defer { unsafeDelayDefaults.removePersistentDomain(forName: unsafeDelaySuite) }
    unsafeDelayDefaults.set(5, forKey: "responseDelayMinutes")
    unsafeDelayDefaults.set(Data("retired pending state".utf8), forKey: "pendingFirstTouchTickets")
    _ = MonitorState(defaults: unsafeDelayDefaults)
    expect(
        unsafeDelayDefaults.object(forKey: "responseDelayMinutes") == nil,
        "migration removes the retired alert-mode selection"
    )
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

// Custom alert sound files
expect(
    AlertSoundRules.preflightProblem(fileName: "ding.mp3", byteCount: 500_000) == nil,
    "a small MP3 passes the alert-sound preflight"
)
expect(
    AlertSoundRules.preflightProblem(fileName: "ding.WAV", byteCount: 1_000) == nil,
    "alert-sound extensions are matched case-insensitively"
)
expect(
    AlertSoundRules.preflightProblem(fileName: "ding.ogg", byteCount: 1_000) != nil,
    "unsupported alert-sound formats are refused"
)
expect(
    AlertSoundRules.preflightProblem(fileName: "big.wav", byteCount: 3 * 1_048_576)?
        .contains("3.0 MB") == true,
    "alert-sound files over 2 MB are refused with their size"
)
expect(
    AlertSoundRules.durationProblem(fileName: "x.mp3", duration: nil) != nil,
    "undecodable alert-sound files are refused"
)
expect(
    AlertSoundRules.durationProblem(fileName: "x.mp3", duration: 10.0) == nil,
    "a 10-second alert sound is accepted"
)
expect(
    AlertSoundRules.durationProblem(fileName: "x.mp3", duration: 12.4)?
        .contains("12 seconds") == true,
    "alert sounds longer than 10 seconds are refused with their length"
)
expect(
    AlertSoundRules.voiceDelay(customChimeDuration: nil) == 0,
    "the voice starts with the built-in Glass chime, as before"
)
expect(
    abs(AlertSoundRules.voiceDelay(customChimeDuration: 2.0) - 2.3) < 0.0001,
    "the voice waits for a custom chime plus a short beat"
)

let soundSuite = "HelpCenterCoreSelfTest.AlertSounds.\(UUID().uuidString)"
if let soundDefaults = UserDefaults(suiteName: soundSuite) {
    defer { soundDefaults.removePersistentDomain(forName: soundSuite) }
    let sounds = AlertSoundSettings(defaults: soundDefaults)
    expect(sounds.customCount == 0, "alert sounds default to built-in")
    expect(sounds.summary == "All sounds are built-in", "built-in alert-sound summary")
    let chime = AlertSoundFile(name: "my chime.mp3", storedFileName: "chime-1.mp3", duration: 1.5)
    sounds.setFile(chime, for: .chime)
    let restoredSounds = AlertSoundSettings(defaults: soundDefaults)
    expect(restoredSounds.file(for: .chime) == chime, "a custom chime is persisted")
    expect(restoredSounds.file(for: .voice) == nil, "alert-sound slots are independent")
    expect(restoredSounds.summary == "1 of 2 sounds use your own file", "custom alert-sound summary")
    expect(
        AlertSoundSettings.summary(customCount: 0) == "All sounds are built-in",
        "a slot whose stored file is missing is summarised as built-in"
    )
    restoredSounds.setFile(nil, for: .chime)
    expect(sounds.customCount == 0, "resetting a slot returns it to the built-in sound")
    expect(soundDefaults.object(forKey: "alertSoundFiles") == nil, "an empty alert-sound index is removed")
    soundDefaults.set(Data("not json".utf8), forKey: "alertSoundFiles")
    expect(sounds.customCount == 0, "a corrupt alert-sound index falls back to built-in sounds")
} else {
    expect(false, "isolated alert-sound UserDefaults suite can be created")
}

if failures > 0 {
    exit(1)
}
print("HelpCenterCoreSelfTest: all checks passed")
