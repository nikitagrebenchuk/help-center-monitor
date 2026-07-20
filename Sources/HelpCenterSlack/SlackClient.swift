import Foundation
import HelpCenterCore

public enum SlackClientError: LocalizedError {
    case invalidResponse
    case rateLimited(seconds: TimeInterval)
    case api(code: String, explanation: String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Slack returned an unreadable response."
        case .rateLimited(let seconds):
            return "Slack rate-limited requests for \(Int(seconds)) seconds."
        case .api(let code, let explanation):
            return "Slack error \(code): \(explanation)"
        }
    }
}

public struct SlackIdentity {
    public let user: String
    public let team: String
}

public struct SlackFetchResult {
    public let messages: [[String: Any]]
    public let highestTimestamp: String?
}

public struct SlackClient {
    private static let fatalErrors: [String: String] = [
        "invalid_auth": "The Slack token is invalid. Replace it from the menu.",
        "account_inactive": "The Slack app or account is inactive.",
        "token_revoked": "The Slack token was revoked. Replace it from the menu.",
        "not_in_channel": "The monitoring bot is not a member of the configured channel.",
        "channel_not_found": "The configured channel cannot be found by the bot.",
        "missing_scope": "The bot token needs the channels:history scope.",
    ]

    private let apiBase: String
    private let session: URLSession

    public init(apiBase: String, session: URLSession = .shared) {
        self.apiBase = apiBase
        self.session = session
    }

    public func authenticate(token: String) async throws -> SlackIdentity {
        let payload = try await apiCall(method: "auth.test", token: token, parameters: [:])
        return SlackIdentity(
            user: payload["user"] as? String ?? "unknown",
            team: payload["team"] as? String ?? "unknown"
        )
    }

    public func fetchNewMessages(
        token: String,
        channel: String,
        oldest: String,
        maximumPages: Int
    ) async throws -> SlackFetchResult {
        var messages: [[String: Any]] = []
        var cursor: String?
        var pages = 0

        while true {
            var parameters = [
                "channel": channel,
                "oldest": oldest,
                "limit": "15",
            ]
            if let cursor, !cursor.isEmpty {
                parameters["cursor"] = cursor
            }

            let payload: [String: Any]
            do {
                payload = try await apiCall(
                    method: "conversations.history",
                    token: token,
                    parameters: parameters
                )
            } catch SlackClientError.rateLimited(let seconds) where !messages.isEmpty {
                // Preserve the cursor and pages already collected. Propagating
                // here would restart at page one after every 429 and could
                // permanently starve a backlog larger than Slack's page size.
                let nanoseconds = UInt64(max(seconds, 1) * 1_000_000_000)
                try await Task<Never, Never>.sleep(nanoseconds: nanoseconds)
                continue
            }
            if let pageMessages = payload["messages"] as? [[String: Any]] {
                messages.append(contentsOf: pageMessages)
            }

            let nextCursor = ((payload["response_metadata"] as? [String: Any])?["next_cursor"] as? String) ?? ""
            let hasMore = payload["has_more"] as? Bool == true
            pages += 1
            if !hasMore || nextCursor.isEmpty {
                break
            }
            if nextCursor == cursor || pages >= maximumPages {
                throw SlackClientError.api(
                    code: "pagination_failed",
                    explanation: "Slack history pagination did not converge."
                )
            }
            cursor = nextCursor
        }

        var highestTimestamp: String?
        let ticketMessages = messages.filter { message in
            if let timestamp = message["ts"] as? String,
               timestampIsLater(timestamp, than: highestTimestamp) {
                highestTimestamp = timestamp
            }
            return SlackMessageParser.isTopLevelTicket(message)
        }.sorted { left, right in
            timestampValue(left["ts"] as? String) < timestampValue(right["ts"] as? String)
        }

        return SlackFetchResult(
            messages: ticketMessages,
            highestTimestamp: highestTimestamp
        )
    }

    public func fetchRecentMessages(
        token: String,
        channel: String,
        limit: Int = 15
    ) async throws -> [[String: Any]] {
        let boundedLimit = min(max(limit, 1), 15)
        let payload = try await apiCall(
            method: "conversations.history",
            token: token,
            parameters: [
                "channel": channel,
                "limit": String(boundedLimit),
            ]
        )
        return (payload["messages"] as? [[String: Any]] ?? []).filter {
            SlackMessageParser.isTopLevelTicket($0)
        }
    }

    private func apiCall(
        method: String,
        token: String,
        parameters: [String: String]
    ) async throws -> [String: Any] {
        guard let url = URL(string: "\(apiBase)/\(method)") else {
            throw SlackClientError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(
            "application/x-www-form-urlencoded; charset=utf-8",
            forHTTPHeaderField: "Content-Type"
        )
        var components = URLComponents()
        components.queryItems = parameters
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SlackClientError.invalidResponse
        }
        if httpResponse.statusCode == 429 {
            let retryAfter = TimeInterval(
                httpResponse.value(forHTTPHeaderField: "Retry-After") ?? "60"
            ) ?? 60
            throw SlackClientError.rateLimited(seconds: min(max(retryAfter, 1), 300))
        }
        guard (200..<300).contains(httpResponse.statusCode),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SlackClientError.invalidResponse
        }
        guard json["ok"] as? Bool == true else {
            let code = json["error"] as? String ?? "unknown"
            let explanation = Self.fatalErrors[code] ?? "The request will be retried automatically."
            throw SlackClientError.api(code: code, explanation: explanation)
        }
        return json
    }

    private func timestampIsLater(_ candidate: String, than current: String?) -> Bool {
        guard let current else { return true }
        return timestampValue(candidate) > timestampValue(current)
    }

    private func timestampValue(_ timestamp: String?) -> Double {
        Double(timestamp ?? "") ?? 0
    }
}
