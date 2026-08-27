import Darwin
import Foundation

public enum AWSSecretsManagerTokenError: LocalizedError {
    case cliUnavailable
    case commandTimedOut
    case commandFailed(Int32)
    case secretDoesNotContainBotToken

    public var errorDescription: String? {
        switch self {
        case .cliUnavailable:
            return "The AWS CLI is not installed in a standard location."
        case .commandTimedOut:
            return "AWS Secrets Manager did not respond in time."
        case .commandFailed(let status):
            return "AWS Secrets Manager access failed (AWS CLI exit status \(status))."
        case .secretDoesNotContainBotToken:
            return "The AWS secret does not contain a valid xoxb- bot token."
        }
    }
}

/// Loads the Slack bot token through the locally configured AWS CLI. Using the
/// CLI lets the app reuse the company's existing AWS SSO session without
/// embedding AWS credentials or an AWS SDK in the application bundle.
public struct AWSSecretsManagerTokenProvider: Sendable {
    public let secretID: String
    public let region: String
    public let profile: String
    public let timeout: TimeInterval
    public let executableCandidates: [URL]

    public init(
        secretID: String,
        region: String,
        profile: String,
        timeout: TimeInterval = 15,
        executableCandidates: [URL] = Self.defaultExecutableCandidates
    ) {
        self.secretID = secretID
        self.region = region
        self.profile = profile
        self.timeout = timeout
        self.executableCandidates = executableCandidates
    }

    public func fetchToken() throws -> String {
        guard let executable = executableCandidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }) else {
            throw AWSSecretsManagerTokenError.cliUnavailable
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = [
            "secretsmanager", "get-secret-value",
            "--secret-id", secretID,
            "--region", region,
            "--profile", profile,
            "--query", "SecretString",
            "--output", "text",
            "--no-cli-pager",
            "--cli-connect-timeout", "5",
            "--cli-read-timeout", String(Int(max(timeout, 1))),
        ]
        var environment = ProcessInfo.processInfo.environment
        environment["AWS_PAGER"] = ""
        process.environment = environment

        let standardOutput = Pipe()
        let standardError = Pipe()
        process.standardOutput = standardOutput
        process.standardError = standardError

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do {
            try process.run()
        } catch {
            throw AWSSecretsManagerTokenError.cliUnavailable
        }

        let output = LockedData()
        let readers = DispatchGroup()
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            output.value = standardOutput.fileHandleForReading.readDataToEndOfFile()
            readers.leave()
        }
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            // Drain diagnostics so the subprocess cannot block on a full pipe,
            // but never retain or surface them.
            _ = standardError.fileHandleForReading.readDataToEndOfFile()
            readers.leave()
        }

        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if finished.wait(timeout: .now() + 2) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 2)
            }
            readers.wait()
            throw AWSSecretsManagerTokenError.commandTimedOut
        }
        readers.wait()

        guard process.terminationStatus == 0 else {
            // Intentionally do not include stdout or stderr. Authentication
            // diagnostics must never risk echoing secret material into UI/logs.
            throw AWSSecretsManagerTokenError.commandFailed(process.terminationStatus)
        }
        guard let secretString = String(data: output.value, encoding: .utf8),
              let token = Self.token(fromSecretString: secretString) else {
            throw AWSSecretsManagerTokenError.secretDoesNotContainBotToken
        }
        return token
    }

    /// Supports either a plain SecretString (`xoxb-...`) or JSON containing the
    /// token under any field, including common names such as SLACK_BOT_TOKEN.
    public static func token(fromSecretString secretString: String) -> String? {
        let trimmed = secretString.trimmingCharacters(in: .whitespacesAndNewlines)
        if isValidBotToken(trimmed) {
            return trimmed
        }
        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        return token(in: json)
    }

    public static let defaultExecutableCandidates = [
        URL(fileURLWithPath: "/usr/local/bin/aws"),
        URL(fileURLWithPath: "/opt/homebrew/bin/aws"),
        URL(fileURLWithPath: "/usr/local/aws-cli/v2/current/bin/aws"),
        URL(fileURLWithPath: "/usr/bin/aws"),
    ]

    private static let preferredJSONKeys = [
        "SLACK_BOT_TOKEN", "slack_bot_token", "SLACK_TOKEN", "slack_token",
        "token", "xoxb",
    ]

    private static func token(in value: Any) -> String? {
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return isValidBotToken(trimmed) ? trimmed : nil
        }
        if let dictionary = value as? [String: Any] {
            for key in preferredJSONKeys {
                if let candidate = dictionary[key], let found = token(in: candidate) {
                    return found
                }
            }
            for key in dictionary.keys.sorted() where !preferredJSONKeys.contains(key) {
                if let candidate = dictionary[key], let found = token(in: candidate) {
                    return found
                }
            }
        }
        if let array = value as? [Any] {
            for candidate in array {
                if let found = token(in: candidate) {
                    return found
                }
            }
        }
        return nil
    }

    private static func isValidBotToken(_ value: String) -> Bool {
        value.hasPrefix("xoxb-")
            && value.count > 10
            && value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
    }
}

private final class LockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    var value: Data {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock()
            storage = newValue
            lock.unlock()
        }
    }
}
