import Foundation

public enum SlackMessageParser {
    public static let ignoredSubtypes: Set<String> = [
        "channel_join", "channel_leave", "channel_topic", "channel_purpose",
        "channel_name", "channel_archive", "channel_unarchive",
        "bot_add", "bot_remove", "reminder_add", "tombstone",
        "message_changed", "message_deleted", "thread_broadcast",
        "huddle_thread", "channel_canvas_updated", "sh_room_created",
    ]

    private static let shortcode = try! NSRegularExpression(
        pattern: #":[a-z0-9_+\-']+:"#,
        options: []
    )
    private static let labelledLink = try! NSRegularExpression(
        pattern: #"<([^>|]+)\|([^>]+)>"#,
        options: []
    )
    private static let bareLink = try! NSRegularExpression(
        pattern: #"<(https?://[^>]+)>"#,
        options: []
    )
    private static let mention = try! NSRegularExpression(
        pattern: #"<[@#!][^>]+>"#,
        options: []
    )
    private static let issue = try! NSRegularExpression(
        pattern: #"Issue #(\d+)"#,
        options: [.caseInsensitive]
    )
    private static let whitespace = try! NSRegularExpression(
        pattern: #"\s+"#,
        options: []
    )
    private static let placeholder = "no preview available"

    public static func plainText(_ value: Any?) -> String {
        guard var text = value as? String else { return "" }
        text = replace(labelledLink, in: text, with: "$2")
        text = replace(bareLink, in: text, with: "$1")
        text = replace(mention, in: text, with: "")
        text = replace(shortcode, in: text, with: "")
        text = text
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "_", with: " ")
        text = replace(whitespace, in: text, with: " ")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func messageText(_ message: [String: Any]) -> String {
        let topLevel = plainText(message["text"])
        if !topLevel.isEmpty {
            return topLevel
        }

        for attachment in dictionaries(message["attachments"]) {
            for key in ["title", "text", "fallback"] {
                guard let value = attachment[key] as? String else { continue }
                let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !candidate.isEmpty && !candidate.lowercased().contains(placeholder) {
                    return plainText(candidate)
                }
            }
        }

        if let blocks = message["blocks"] {
            var harvested: [String] = []
            collectText(from: blocks, into: &harvested)
            let candidate = plainText(harvested.joined(separator: " "))
            if !candidate.isEmpty {
                return candidate
            }
        }

        return "(no text)"
    }

    public static func sender(_ message: [String: Any]) -> String {
        if let username = nonEmptyString(message["username"]) {
            return username
        }
        if let profile = message["bot_profile"] as? [String: Any],
           let name = nonEmptyString(profile["name"]) {
            return name
        }
        return nonEmptyString(message["user"]) ?? "unknown"
    }

    public static func issueNumber(_ message: [String: Any]) -> String? {
        guard let text = message["text"] as? String else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = issue.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let numberRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[numberRange])
    }

    public static func isTopLevelTicket(_ message: [String: Any]) -> Bool {
        guard let timestamp = nonEmptyString(message["ts"]) else { return false }
        if let subtype = message["subtype"] as? String, ignoredSubtypes.contains(subtype) {
            return false
        }
        if message["hidden"] as? Bool == true {
            return false
        }
        if let threadTimestamp = nonEmptyString(message["thread_ts"]),
           threadTimestamp != timestamp {
            return false
        }
        return true
    }

    public static func bestLink(
        _ message: [String: Any],
        channel: String,
        workspaceURL: String
    ) -> String {
        var urls: [String] = []
        harvestURLs(from: message["attachments"], into: &urls)
        harvestURLs(from: message["blocks"], into: &urls)

        if let slackURL = urls.first(where: { $0.contains("slack.com/archives") }) {
            return slackURL
        }
        if let pylonURL = urls.first(where: {
            $0.localizedCaseInsensitiveContains("pylon") || $0.contains("usepylon.com")
        }) {
            return pylonURL
        }
        let timestamp = nonEmptyString(message["ts"]) ?? ""
        return permalink(channel: channel, timestamp: timestamp, workspaceURL: workspaceURL)
    }

    public static func permalink(
        channel: String,
        timestamp: String,
        workspaceURL: String
    ) -> String {
        let base = workspaceURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return "\(base)/archives/\(channel)/p\(timestamp.replacingOccurrences(of: ".", with: ""))"
    }

    private static func replace(
        _ expression: NSRegularExpression,
        in text: String,
        with template: String
    ) -> String {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.stringByReplacingMatches(
            in: text,
            options: [],
            range: range,
            withTemplate: template
        )
    }

    private static func dictionaries(_ value: Any?) -> [[String: Any]] {
        if let dictionaries = value as? [[String: Any]] {
            return dictionaries
        }
        return (value as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func collectText(from node: Any, into output: inout [String]) {
        if let dictionary = node as? [String: Any] {
            if let text = nonEmptyString(dictionary["text"]) {
                output.append(text)
            }
            for (key, value) in dictionary where key != "text" {
                collectText(from: value, into: &output)
            }
        } else if let array = node as? [Any] {
            for item in array {
                collectText(from: item, into: &output)
            }
        }
    }

    private static func harvestURLs(from node: Any?, into output: inout [String]) {
        guard let node else { return }
        if let dictionary = node as? [String: Any] {
            if let url = dictionary["url"] as? String, url.hasPrefix("http") {
                output.append(url)
            }
            for (key, value) in dictionary {
                if key == "text", let text = value as? String {
                    appendMatches(labelledLink, group: 1, in: text, to: &output)
                    appendMatches(bareLink, group: 1, in: text, to: &output)
                } else {
                    harvestURLs(from: value, into: &output)
                }
            }
        } else if let array = node as? [Any] {
            for item in array {
                harvestURLs(from: item, into: &output)
            }
        }
    }

    private static func appendMatches(
        _ expression: NSRegularExpression,
        group: Int,
        in text: String,
        to output: inout [String]
    ) {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for match in expression.matches(in: text, options: [], range: range) {
            guard match.numberOfRanges > group,
                  let matchRange = Range(match.range(at: group), in: text) else {
                continue
            }
            output.append(String(text[matchRange]))
        }
    }
}
