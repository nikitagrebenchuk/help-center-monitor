import Foundation

// Custom sound files: either alert sound can be replaced by an audio file picked
// in the Alert Sounds window. Without a file, the built-in sound plays. This
// mirrors the help-center-agents extension's "Custom sound files" option.
//
// The app copies the picked file into its own Application Support folder, so
// moving or deleting the original never silences an alert. Only the small
// index below (display name, stored file name, length) lives in UserDefaults.

public enum AlertSoundSlot: String, CaseIterable, Codable, Sendable {
    case chime
    case voice

    public var title: String {
        switch self {
        case .chime: return "New message chime"
        case .voice: return "New message voice"
        }
    }

    public var hint: String {
        switch self {
        case .chime:
            return "Plays when a new message alert opens, instead of the macOS Glass sound."
        case .voice:
            return "Plays after the chime, instead of the spoken \u{201C}New message in the alert channel.\u{201D} Team voice-overs take priority when switched on."
        }
    }
}

public struct AlertSoundFile: Codable, Equatable, Sendable {
    /// The name of the file the user picked, shown in the UI.
    public let name: String
    /// The copy's file name inside the app's AlertSounds folder.
    public let storedFileName: String
    /// Length in seconds, measured when the file was picked.
    public let duration: TimeInterval

    public init(name: String, storedFileName: String, duration: TimeInterval) {
        self.name = name
        self.storedFileName = storedFileName
        self.duration = duration
    }
}

public enum AlertSoundRules {
    public static let maxBytes = 2 * 1024 * 1024
    /// A longer file would be talked over by the voice or delay the next alert.
    public static let maxSeconds: TimeInterval = 10
    public static let supportedExtensions: Set<String> = [
        "aif", "aiff", "caf", "m4a", "mp3", "wav",
    ]
    /// Pause between a custom chime ending and the voice starting.
    public static let chimeToVoiceGap: TimeInterval = 0.3

    /// Checks that need no audio decoding. Returns a message for the user, or nil.
    public static func preflightProblem(fileName: String, byteCount: Int) -> String? {
        let ext = (fileName as NSString).pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else {
            return "\(fileName) isn\u{2019}t a supported sound. Pick an MP3, WAV, M4A, AIFF or CAF file."
        }
        if byteCount > maxBytes {
            let megabytes = Double(byteCount) / 1_048_576
            return "\(fileName) is \(String(format: "%.1f", megabytes)) MB. Pick a file of 2 MB or less."
        }
        return nil
    }

    /// Checks on the decoded file. `duration` is nil when macOS can't decode it.
    public static func durationProblem(fileName: String, duration: TimeInterval?) -> String? {
        guard let duration, duration > 0 else {
            return "macOS can\u{2019}t play \(fileName). Try an MP3 or WAV file."
        }
        if duration > maxSeconds {
            return "\(fileName) is \(Int(duration.rounded())) seconds long. Pick a sound of \(Int(maxSeconds)) seconds or less."
        }
        return nil
    }

    /// How long after the chime starts the voice should wait: right away for
    /// the short built-in Glass sound (as before), or a custom chime's length
    /// plus a beat so the two don't talk over each other.
    public static func voiceDelay(customChimeDuration: TimeInterval?) -> TimeInterval {
        guard let customChimeDuration, customChimeDuration > 0 else { return 0 }
        return customChimeDuration + chimeToVoiceGap
    }
}

public struct AlertSoundSettings {
    private let defaults: UserDefaults
    static let key = "alertSoundFiles"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func file(for slot: AlertSoundSlot) -> AlertSoundFile? {
        allFiles[slot]
    }

    public func setFile(_ file: AlertSoundFile?, for slot: AlertSoundSlot) {
        var files = allFiles
        files[slot] = file
        let encodable = Dictionary(uniqueKeysWithValues: files.map { ($0.key.rawValue, $0.value) })
        if encodable.isEmpty {
            defaults.removeObject(forKey: Self.key)
        } else if let data = try? JSONEncoder().encode(encodable) {
            defaults.set(data, forKey: Self.key)
        }
    }

    public var customCount: Int {
        allFiles.count
    }

    public var summary: String {
        Self.summary(customCount: customCount)
    }

    /// The control-window line for `customCount` slots that use a file. The app
    /// passes only slots whose stored copy still exists, so the line never
    /// claims a custom sound while the built-in one is what plays.
    public static func summary(customCount count: Int) -> String {
        let total = AlertSoundSlot.allCases.count
        return count <= 0
            ? "All sounds are built-in"
            : "\(count) of \(total) sounds use your own file"
    }

    private var allFiles: [AlertSoundSlot: AlertSoundFile] {
        guard let data = defaults.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode([String: AlertSoundFile].self, from: data) else {
            return [:]
        }
        var files: [AlertSoundSlot: AlertSoundFile] = [:]
        for (raw, file) in decoded {
            if let slot = AlertSoundSlot(rawValue: raw) {
                files[slot] = file
            }
        }
        return files
    }
}
