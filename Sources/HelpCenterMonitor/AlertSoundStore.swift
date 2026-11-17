import AppKit
import Foundation
import HelpCenterCore

/// Stores the copies of user-picked alert sounds and loads them for playback.
/// Every failure falls back to the built-in sound: a broken custom file must
/// never silence an alert.
final class AlertSoundStore {
    enum PickResult {
        case saved(AlertSoundFile)
        case rejected(String)
    }

    private let settings: AlertSoundSettings
    private let directoryURL: URL

    init(settings: AlertSoundSettings = AlertSoundSettings(), directoryURL: URL = AlertSoundStore.defaultDirectoryURL) {
        self.settings = settings
        self.directoryURL = directoryURL
    }

    static var defaultDirectoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("Help Center Monitor", isDirectory: true)
            .appendingPathComponent("AlertSounds", isDirectory: true)
    }

    /// Counts only slots whose stored copy still exists, matching what plays.
    var summary: String {
        AlertSoundSettings.summary(
            customCount: AlertSoundSlot.allCases.filter { file(for: $0) != nil }.count
        )
    }

    func file(for slot: AlertSoundSlot) -> AlertSoundFile? {
        guard let file = settings.file(for: slot),
              FileManager.default.fileExists(atPath: storedURL(for: file).path) else {
            return nil
        }
        return file
    }

    /// A fresh NSSound for the slot's custom file, or nil to use the built-in sound.
    func makeSound(for slot: AlertSoundSlot) -> NSSound? {
        guard let file = file(for: slot) else { return nil }
        return NSSound(contentsOf: storedURL(for: file), byReference: false)
    }

    /// Validates the picked file and copies it into the app's folder. The
    /// length is checked before anything plays, so a too-long file is refused
    /// without being played in full.
    func pick(_ sourceURL: URL, for slot: AlertSoundSlot) -> PickResult {
        let name = sourceURL.lastPathComponent
        let byteCount = (try? sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if let problem = AlertSoundRules.preflightProblem(fileName: name, byteCount: byteCount) {
            return .rejected(problem)
        }
        let duration = NSSound(contentsOf: sourceURL, byReference: true)?.duration
        if let problem = AlertSoundRules.durationProblem(fileName: name, duration: duration) {
            return .rejected(problem)
        }

        let ext = sourceURL.pathExtension.lowercased()
        // A new name each time, so a replaced file can't be confused with one
        // still loaded by an alert that is playing.
        let storedFileName = "\(slot.rawValue)-\(UUID().uuidString).\(ext)"
        let destination = directoryURL.appendingPathComponent(storedFileName)
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: sourceURL, to: destination)
        } catch {
            return .rejected("Couldn\u{2019}t save \(name): \(error.localizedDescription)")
        }

        let previous = settings.file(for: slot)
        let file = AlertSoundFile(name: name, storedFileName: storedFileName, duration: duration ?? 0)
        settings.setFile(file, for: slot)
        if let previous {
            try? FileManager.default.removeItem(at: storedURL(for: previous))
        }
        return .saved(file)
    }

    func reset(_ slot: AlertSoundSlot) {
        if let previous = settings.file(for: slot) {
            try? FileManager.default.removeItem(at: storedURL(for: previous))
        }
        settings.setFile(nil, for: slot)
    }

    /// Used by --prepare-uninstall.
    static func removeAllStoredFiles() {
        try? FileManager.default.removeItem(at: defaultDirectoryURL)
    }

    private func storedURL(for file: AlertSoundFile) -> URL {
        // lastPathComponent keeps a tampered preference from pointing outside the folder.
        directoryURL.appendingPathComponent((file.storedFileName as NSString).lastPathComponent)
    }
}
