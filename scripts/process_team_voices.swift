#!/usr/bin/env swift

import AVFoundation
import AudioToolbox
import Darwin
import Foundation

private struct Options {
    var outputDirectory = URL(fileURLWithPath: "Resources/TeamVoices", isDirectory: true)
    var targetActiveRMSDB = -19.0
    var inputs: [URL] = []
}

private struct ProcessingReport {
    let sourceDuration: Double
    let outputDuration: Double
    let trimStart: Double
    let trimEnd: Double
    let gainDB: Double
    let activeRMSDB: Double
    let peakDB: Double
}

private struct PreparedInput {
    let url: URL
    let temporaryURL: URL?
}

private enum VoiceProcessingError: LocalizedError {
    case usage(String)
    case unreadableAudio(String)
    case emptyAudio(String)

    var errorDescription: String? {
        switch self {
        case .usage(let message), .unreadableAudio(let message), .emptyAudio(let message):
            return message
        }
    }
}

private let supportedExtensions = Set(["aac", "aif", "aiff", "caf", "m4a", "mp3", "wav"])

private func parseOptions() throws -> Options {
    var options = Options()
    var arguments = Array(CommandLine.arguments.dropFirst())
    while !arguments.isEmpty {
        let argument = arguments.removeFirst()
        switch argument {
        case "--output", "-o":
            guard !arguments.isEmpty else {
                throw VoiceProcessingError.usage("--output requires a directory path")
            }
            options.outputDirectory = URL(
                fileURLWithPath: arguments.removeFirst(),
                isDirectory: true
            )
        case "--target-rms":
            guard !arguments.isEmpty,
                  let value = Double(arguments.removeFirst()),
                  (-30 ... -10).contains(value) else {
                throw VoiceProcessingError.usage("--target-rms must be between -30 and -10 dBFS")
            }
            options.targetActiveRMSDB = value
        case "--help", "-h":
            printUsage()
            exit(0)
        default:
            options.inputs.append(URL(fileURLWithPath: argument))
        }
    }
    guard !options.inputs.isEmpty else {
        throw VoiceProcessingError.usage("Provide one or more audio files or directories")
    }
    return options
}

private func printUsage() {
    print("""
    Usage:
      swift scripts/process_team_voices.swift [options] <audio files or directories...>

    Options:
      -o, --output <directory>  Output directory (default: Resources/TeamVoices)
      --target-rms <dBFS>       Active speech target (default: -19)

    The processor converts every clip to mono Core Audio, trims leading/trailing silence,
    applies light speech compression, normalizes active speech power, caps peaks at
    -1 dBFS, and adds short fades at both cut points. It uses ffmpeg when found;
    set HCM_FFMPEG_PATH if ffmpeg is installed in a nonstandard location.
    """)
}

private func expandedInputs(_ inputs: [URL]) -> [URL] {
    let fileManager = FileManager.default
    var files: [URL] = []
    for input in inputs {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: input.path, isDirectory: &isDirectory) else {
            FileHandle.standardError.write(Data("Skipping missing input: \(input.path)\n".utf8))
            continue
        }
        if isDirectory.boolValue {
            let directoryFiles = (try? fileManager.contentsOfDirectory(
                at: input,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            files.append(contentsOf: directoryFiles.filter {
                supportedExtensions.contains($0.pathExtension.lowercased())
            })
        } else if supportedExtensions.contains(input.pathExtension.lowercased()) {
            files.append(input)
        }
    }
    return files.sorted {
        $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
    }
}

private func decibels(_ amplitude: Double) -> Double {
    20 * log10(max(amplitude, 0.000_000_1))
}

private func amplitude(fromDecibels value: Double) -> Double {
    pow(10, value / 20)
}

private func windowRMS(_ samples: [Float], windowFrames: Int) -> [Double] {
    guard !samples.isEmpty else { return [] }
    var result: [Double] = []
    result.reserveCapacity((samples.count + windowFrames - 1) / windowFrames)
    var start = 0
    while start < samples.count {
        let end = min(start + windowFrames, samples.count)
        var sumSquares = 0.0
        for index in start ..< end {
            let value = Double(samples[index])
            sumSquares += value * value
        }
        result.append(sqrt(sumSquares / Double(end - start)))
        start = end
    }
    return result
}

private func activeRMS(_ samples: [Float], sampleRate: Double) -> Double {
    let windowFrames = max(Int(sampleRate * 0.02), 1)
    let windows = windowRMS(samples, windowFrames: windowFrames)
    let activeThreshold = amplitude(fromDecibels: -38)
    let activeIndexes = windows.indices.filter { windows[$0] >= activeThreshold }
    let selectedIndexes = activeIndexes.isEmpty ? Array(windows.indices) : activeIndexes
    var sumSquares = 0.0
    var sampleCount = 0
    for windowIndex in selectedIndexes {
        let start = windowIndex * windowFrames
        let end = min(start + windowFrames, samples.count)
        for index in start ..< end {
            let value = Double(samples[index])
            sumSquares += value * value
            sampleCount += 1
        }
    }
    guard sampleCount > 0 else { return 0 }
    return sqrt(sumSquares / Double(sampleCount))
}

private func speechBounds(_ samples: [Float], sampleRate: Double) -> (start: Int, end: Int) {
    let windowFrames = max(Int(sampleRate * 0.01), 1)
    let windows = windowRMS(samples, windowFrames: windowFrames)
    guard !windows.isEmpty else { return (0, samples.count) }
    let sorted = windows.sorted()
    let noiseIndex = min(Int(Double(sorted.count - 1) * 0.2), sorted.count - 1)
    let noiseFloorDB = decibels(sorted[noiseIndex])
    let peakDB = decibels(windows.max() ?? 0)
    let thresholdDB = min(-28, max(-45, noiseFloorDB + 12, peakDB - 30))
    let threshold = amplitude(fromDecibels: thresholdDB)

    guard let firstWindow = windows.firstIndex(where: { $0 >= threshold }),
          let lastWindow = windows.lastIndex(where: { $0 >= threshold }) else {
        return (0, samples.count)
    }
    let leadingPadding = Int(sampleRate * 0.08)
    let trailingPadding = Int(sampleRate * 0.14)
    let start = max(firstWindow * windowFrames - leadingPadding, 0)
    let end = min((lastWindow + 1) * windowFrames + trailingPadding, samples.count)
    return (start, max(end, start + 1))
}

private func lightlyCompressed(_ samples: [Float]) -> [Float] {
    let threshold = amplitude(fromDecibels: -14)
    let ratio = 3.0
    return samples.map { sample in
        let value = Double(sample)
        let magnitude = abs(value)
        guard magnitude > threshold else { return sample }
        let compressedMagnitude = threshold * pow(magnitude / threshold, 1 / ratio)
        return Float(value < 0 ? -compressedMagnitude : compressedMagnitude)
    }
}

private func coreAudioCompatibleInput(_ inputURL: URL) throws -> PreparedInput {
    guard ["m4a", "mp4"].contains(inputURL.pathExtension.lowercased()) else {
        return PreparedInput(url: inputURL, temporaryURL: nil)
    }

    var data = try Data(contentsOf: inputURL)
    let marker = Data("mp4a".utf8)
    let esdsMarker = Data("esds".utf8)
    guard let markerRange = data.range(of: marker),
          let esdsRange = data.range(of: esdsMarker) else {
        return PreparedInput(url: inputURL, temporaryURL: nil)
    }
    // In an ISO audio sample entry, channelcount is 20 bytes after the
    // beginning of the `mp4a` type. Some phone/WhatsApp exports declare two
    // channels here while their AAC AudioSpecificConfig correctly declares
    // mono. Core Audio 26 rejects that mismatch with `fmt?`, so repair only
    // the temporary working copy using the channel configuration embedded in
    // the AAC AudioSpecificConfig.
    let channelOffset = markerRange.lowerBound + 20
    guard channelOffset + 1 < data.count else {
        return PreparedInput(url: inputURL, temporaryURL: nil)
    }
    var decodedChannels: UInt16?
    var descriptorIndex = esdsRange.upperBound + 4
    let descriptorLimit = min(descriptorIndex + 160, data.count)
    while descriptorIndex < descriptorLimit, decodedChannels == nil {
        guard data[descriptorIndex] == 0x05 else {
            descriptorIndex += 1
            continue
        }
        var lengthIndex = descriptorIndex + 1
        var descriptorLength = 0
        var lengthByteCount = 0
        while lengthIndex < descriptorLimit, lengthByteCount < 4 {
            let byte = data[lengthIndex]
            descriptorLength = (descriptorLength << 7) | Int(byte & 0x7f)
            lengthIndex += 1
            lengthByteCount += 1
            if byte & 0x80 == 0 { break }
        }
        if descriptorLength >= 2, lengthIndex + 1 < data.count {
            let first = data[lengthIndex]
            let second = data[lengthIndex + 1]
            let frequencyIndex = ((first & 0x07) << 1) | (second >> 7)
            if frequencyIndex != 0x0f {
                let channelConfiguration = UInt16((second >> 3) & 0x0f)
                if (1 ... 8).contains(channelConfiguration) {
                    decodedChannels = channelConfiguration
                }
            }
        }
        descriptorIndex += 1
    }
    guard let decodedChannels else {
        return PreparedInput(url: inputURL, temporaryURL: nil)
    }
    let declaredChannels = UInt16(data[channelOffset]) << 8 | UInt16(data[channelOffset + 1])
    guard declaredChannels != decodedChannels, (1 ... 8).contains(decodedChannels) else {
        return PreparedInput(url: inputURL, temporaryURL: nil)
    }

    data[channelOffset] = UInt8(decodedChannels >> 8)
    data[channelOffset + 1] = UInt8(decodedChannels & 0xff)
    let temporaryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("hcm-team-voice-\(UUID().uuidString).m4a")
    try data.write(to: temporaryURL, options: .atomic)
    return PreparedInput(url: temporaryURL, temporaryURL: temporaryURL)
}

private func ffmpegExecutable() -> URL? {
    let fileManager = FileManager.default
    if let configuredPath = ProcessInfo.processInfo.environment["HCM_FFMPEG_PATH"],
       fileManager.isExecutableFile(atPath: configuredPath) {
        return URL(fileURLWithPath: configuredPath)
    }
    let standardPaths = [
        "/opt/homebrew/bin/ffmpeg",
        "/usr/local/bin/ffmpeg",
        "/usr/bin/ffmpeg",
    ]
    if let path = standardPaths.first(where: fileManager.isExecutableFile(atPath:)) {
        return URL(fileURLWithPath: path)
    }
    let bundledBinaryDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        .appendingPathComponent(".build/audio-tools/imageio_ffmpeg/binaries", isDirectory: true)
    let bundledCandidates = (try? fileManager.contentsOfDirectory(
        at: bundledBinaryDirectory,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
    )) ?? []
    return bundledCandidates.first {
        $0.lastPathComponent.hasPrefix("ffmpeg-")
            && fileManager.isExecutableFile(atPath: $0.path)
    }
}

private func decodableInput(_ inputURL: URL) throws -> PreparedInput {
    guard let ffmpegURL = ffmpegExecutable() else {
        return try coreAudioCompatibleInput(inputURL)
    }
    let temporaryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("hcm-team-voice-\(UUID().uuidString).wav")
    let process = Process()
    let errorPipe = Pipe()
    process.executableURL = ffmpegURL
    process.arguments = [
        "-hide_banner", "-loglevel", "error", "-y",
        "-i", inputURL.path,
        "-vn", "-ac", "1", "-c:a", "pcm_f32le",
        temporaryURL.path,
    ]
    process.standardError = errorPipe
    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        throw VoiceProcessingError.unreadableAudio(
            "Could not start ffmpeg for \(inputURL.lastPathComponent): \(error.localizedDescription)"
        )
    }
    guard process.terminationStatus == 0 else {
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let details = String(data: errorData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown decoder error"
        throw VoiceProcessingError.unreadableAudio(
            "Could not decode \(inputURL.lastPathComponent): \(details)"
        )
    }
    return PreparedInput(url: temporaryURL, temporaryURL: temporaryURL)
}

private func process(_ inputURL: URL, outputURL: URL, targetRMSDB: Double) throws -> ProcessingReport {
    let preparedInput = try decodableInput(inputURL)
    defer {
        if let temporaryURL = preparedInput.temporaryURL {
            try? FileManager.default.removeItem(at: temporaryURL)
        }
    }
    let inputFile: AVAudioFile
    do {
        inputFile = try AVAudioFile(forReading: preparedInput.url)
    } catch {
        throw VoiceProcessingError.unreadableAudio(
            "Could not read \(inputURL.lastPathComponent): \(error.localizedDescription)"
        )
    }

    guard inputFile.length > 0,
          inputFile.length <= Int64(UInt32.max),
          let inputBuffer = AVAudioPCMBuffer(
            pcmFormat: inputFile.processingFormat,
            frameCapacity: AVAudioFrameCount(inputFile.length)
          ) else {
        throw VoiceProcessingError.emptyAudio("No usable audio in \(inputURL.lastPathComponent)")
    }
    do {
        try inputFile.read(into: inputBuffer)
    } catch {
        let decoderHint = ffmpegExecutable() == nil
            ? " Set HCM_FFMPEG_PATH to an ffmpeg executable for phone-exported AAC files."
            : ""
        throw VoiceProcessingError.unreadableAudio(
            "Could not decode \(inputURL.lastPathComponent): \(error.localizedDescription)\(decoderHint)"
        )
    }
    guard inputBuffer.frameLength > 0,
          let channels = inputBuffer.floatChannelData else {
        throw VoiceProcessingError.emptyAudio("No usable audio in \(inputURL.lastPathComponent)")
    }

    let frameCount = Int(inputBuffer.frameLength)
    let channelCount = Int(inputBuffer.format.channelCount)
    let sampleRate = inputBuffer.format.sampleRate
    var mono = [Float](repeating: 0, count: frameCount)
    for frame in 0 ..< frameCount {
        var sum = 0.0
        for channel in 0 ..< channelCount {
            sum += Double(channels[channel][frame])
        }
        mono[frame] = Float(sum / Double(channelCount))
    }

    let bounds = speechBounds(mono, sampleRate: sampleRate)
    var trimmed = Array(mono[bounds.start ..< bounds.end])
    let mean = trimmed.reduce(0.0) { $0 + Double($1) } / Double(trimmed.count)
    for index in trimmed.indices {
        trimmed[index] = Float(Double(trimmed[index]) - mean)
    }
    trimmed = lightlyCompressed(trimmed)

    let preGainRMS = activeRMS(trimmed, sampleRate: sampleRate)
    guard preGainRMS > 0 else {
        throw VoiceProcessingError.emptyAudio("No audible speech in \(inputURL.lastPathComponent)")
    }
    let desiredGain = amplitude(fromDecibels: targetRMSDB) / preGainRMS
    let peakBeforeGain = trimmed.map { abs(Double($0)) }.max() ?? 0
    let peakLimit = amplitude(fromDecibels: -1)
    let peakSafeGain = peakBeforeGain > 0 ? peakLimit / peakBeforeGain : desiredGain
    let gain = min(desiredGain, peakSafeGain)
    for index in trimmed.indices {
        trimmed[index] = Float(Double(trimmed[index]) * gain)
    }

    let fadeFrames = min(Int(sampleRate * 0.015), trimmed.count / 2)
    if fadeFrames > 0 {
        for index in 0 ..< fadeFrames {
            let scale = Float(index + 1) / Float(fadeFrames)
            trimmed[index] *= scale
            trimmed[trimmed.count - index - 1] *= scale
        }
    }

    let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: 1,
        interleaved: false
    )!
    guard let outputBuffer = AVAudioPCMBuffer(
        pcmFormat: outputFormat,
        frameCapacity: AVAudioFrameCount(trimmed.count)
    ), let outputChannel = outputBuffer.floatChannelData?[0] else {
        throw VoiceProcessingError.emptyAudio("Could not allocate output for \(inputURL.lastPathComponent)")
    }
    outputBuffer.frameLength = AVAudioFrameCount(trimmed.count)
    outputChannel.update(from: trimmed, count: trimmed.count)

    if FileManager.default.fileExists(atPath: outputURL.path) {
        try FileManager.default.removeItem(at: outputURL)
    }
    let outputFile: AVAudioFile
    do {
        outputFile = try AVAudioFile(
            forWriting: outputURL,
            settings: outputFormat.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        try outputFile.write(from: outputBuffer)
    } catch {
        throw VoiceProcessingError.unreadableAudio(
            "Could not encode \(outputURL.lastPathComponent): \(error.localizedDescription)"
        )
    }

    let postRMS = activeRMS(trimmed, sampleRate: sampleRate)
    let peak = trimmed.map { abs(Double($0)) }.max() ?? 0
    return ProcessingReport(
        sourceDuration: Double(frameCount) / sampleRate,
        outputDuration: Double(trimmed.count) / sampleRate,
        trimStart: Double(bounds.start) / sampleRate,
        trimEnd: Double(frameCount - bounds.end) / sampleRate,
        gainDB: decibels(gain),
        activeRMSDB: decibels(postRMS),
        peakDB: decibels(peak)
    )
}

private func outputName(for inputURL: URL) -> String {
    let base = inputURL.deletingPathExtension().lastPathComponent.lowercased()
    var slug = base.replacingOccurrences(
        of: "[^a-z0-9]+",
        with: "-",
        options: .regularExpression
    )
    slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    if slug.isEmpty {
        slug = UUID().uuidString.lowercased()
    }
    return "team-voice-\(slug.prefix(80)).caf"
}

do {
    let options = try parseOptions()
    let inputs = expandedInputs(options.inputs)
    guard !inputs.isEmpty else {
        throw VoiceProcessingError.usage("No supported audio files were found")
    }
    try FileManager.default.createDirectory(
        at: options.outputDirectory,
        withIntermediateDirectories: true
    )

    var failures = 0
    for input in inputs {
        let output = options.outputDirectory.appendingPathComponent(outputName(for: input))
        do {
            let report = try process(
                input,
                outputURL: output,
                targetRMSDB: options.targetActiveRMSDB
            )
            print(
                String(
                    format: "%@ -> %@ | %.2fs → %.2fs | trim %.2fs/%.2fs | gain %+.1f dB | active %.1f dBFS | peak %.1f dBFS",
                    input.lastPathComponent,
                    output.lastPathComponent,
                    report.sourceDuration,
                    report.outputDuration,
                    report.trimStart,
                    report.trimEnd,
                    report.gainDB,
                    report.activeRMSDB,
                    report.peakDB
                )
            )
        } catch {
            failures += 1
            FileHandle.standardError.write(
                Data("Failed \(input.lastPathComponent): \(error.localizedDescription)\n".utf8)
            )
        }
    }
    if failures > 0 {
        exit(1)
    }
} catch {
    FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
    printUsage()
    exit(2)
}
