import AVFoundation
import CoreVideo
import Darwin
import Foundation

enum MediaPreparationKind: String, Sendable {
    case original
    case remuxed
    case transcoded
}

struct FFmpegMediaInfo: Equatable, Sendable {
    let duration: Double
    let width: Int
    let height: Int
    let frameRate: Double
    let fileSize: Int64
    let totalBitRate: Double
    let videoCodec: String
    let videoCodecIdentifier: String
    let videoBitRate: Double
    let audioCodec: String?
    let audioCodecIdentifier: String?
    let audioSampleRate: Double
    let audioChannelCount: Int
    let audioBitRate: Double

    var hasAudio: Bool {
        audioCodecIdentifier != nil
    }
}

struct PreparedMediaSource: Sendable {
    let url: URL
    let temporaryDirectoryURL: URL?
    let preparationKind: MediaPreparationKind
    let sourceInfo: FFmpegMediaInfo?

    static func original(_ url: URL) -> PreparedMediaSource {
        PreparedMediaSource(
            url: url,
            temporaryDirectoryURL: nil,
            preparationKind: .original,
            sourceInfo: nil
        )
    }

    func discardTemporaryFiles() {
        guard let temporaryDirectoryURL else { return }
        try? FileManager.default.removeItem(at: temporaryDirectoryURL)
    }
}

enum MediaPreparationStage: Equatable, Sendable {
    case checking
    case remuxing
    case transcodingHardware
    case transcodingSoftware

    var statusText: String {
        switch self {
        case .checking:
            return "正在检查容器和编解码器…"
        case .remuxing:
            return "正在无损重封装兼容预览…"
        case .transcodingHardware:
            return "系统解码器不支持，正在硬件生成兼容预览…"
        case .transcodingSoftware:
            return "硬件路径不可用，正在软件生成兼容预览…"
        }
    }
}

struct MediaPreparationUpdate: Equatable, Sendable {
    let stage: MediaPreparationStage
    let progress: Double?
}

enum FFmpegToolError: LocalizedError {
    case executableNotFound
    case probeExecutableNotFound
    case probeFailed(String)
    case processFailed(String)
    case invalidOutput
    case unsupportedMedia

    var errorDescription: String? {
        switch self {
        case .executableNotFound, .probeExecutableNotFound:
            return "打开该媒体需要 FFmpeg。请先通过 Homebrew 安装：brew install ffmpeg"
        case let .probeFailed(message):
            let detail = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty
                ? "无法识别该媒体的容器或编解码信息。"
                : "无法识别该媒体：\(detail)"
        case let .processFailed(message):
            let detail = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty
                ? "FFmpeg 无法处理这个媒体文件。"
                : "FFmpeg 无法处理这个媒体文件：\(detail)"
        case .invalidOutput:
            return "兼容预览文件生成失败。"
        case .unsupportedMedia:
            return "文件中没有可解码的视频轨道。"
        }
    }
}

enum FFmpegTool {
    static var executableURL: URL? {
        executable(named: "ffmpeg")
    }

    static var probeExecutableURL: URL? {
        executable(named: "ffprobe")
    }

    static func makeProcess(arguments: [String]) throws -> Process {
        guard let executableURL else { throw FFmpegToolError.executableNotFound }
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        return process
    }

    static func secondsArgument(_ seconds: Double) -> String {
        String(
            format: "%.9f",
            locale: Locale(identifier: "en_US_POSIX"),
            seconds
        )
    }

    static func run(arguments: [String]) async throws {
        let processBox = RunningProcessBox()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                do {
                    let process = try makeProcess(arguments: arguments)
                    let errorPipe = Pipe()
                    process.standardOutput = FileHandle.nullDevice
                    process.standardError = errorPipe
                    process.terminationHandler = { completedProcess in
                        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        let errorText = String(decoding: errorData, as: UTF8.self)
                        if processBox.wasCancellationRequested {
                            continuation.resume(throwing: CancellationError())
                        } else if completedProcess.terminationStatus == 0 {
                            continuation.resume()
                        } else {
                            continuation.resume(
                                throwing: FFmpegToolError.processFailed(errorText)
                            )
                        }
                    }
                    try process.run()
                    processBox.install(process)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            processBox.cancel()
        }
    }

    static func run(
        arguments: [String],
        duration: Double,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let processBox = RunningProcessBox()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                do {
                    var progressArguments = arguments
                    let outputURL = progressArguments.removeLast()
                    progressArguments.append(contentsOf: [
                        "-progress", "pipe:1",
                        "-stats_period", "0.5",
                        "-nostats"
                    ])
                    progressArguments.append(outputURL)
                    let process = try makeProcess(arguments: progressArguments)
                    let progressPipe = Pipe()
                    let errorPipe = Pipe()
                    let progressParser = FFmpegProgressParser(
                        duration: duration,
                        onProgress: onProgress
                    )

                    progressPipe.fileHandleForReading.readabilityHandler = { handle in
                        let data = handle.availableData
                        if data.isEmpty {
                            handle.readabilityHandler = nil
                        } else {
                            progressParser.consumeProgress(data)
                        }
                    }
                    errorPipe.fileHandleForReading.readabilityHandler = { handle in
                        let data = handle.availableData
                        if data.isEmpty {
                            handle.readabilityHandler = nil
                        } else {
                            progressParser.consumeError(data)
                        }
                    }
                    process.standardOutput = progressPipe
                    process.standardError = errorPipe
                    process.terminationHandler = { completedProcess in
                        progressPipe.fileHandleForReading.readabilityHandler = nil
                        errorPipe.fileHandleForReading.readabilityHandler = nil
                        progressParser.consumeProgress(
                            progressPipe.fileHandleForReading.readDataToEndOfFile()
                        )
                        progressParser.consumeError(
                            errorPipe.fileHandleForReading.readDataToEndOfFile()
                        )
                        if processBox.wasCancellationRequested {
                            continuation.resume(throwing: CancellationError())
                        } else if completedProcess.terminationStatus == 0 {
                            continuation.resume()
                        } else {
                            continuation.resume(
                                throwing: FFmpegToolError.processFailed(
                                    progressParser.errorMessage
                                )
                            )
                        }
                    }
                    try process.run()
                    processBox.install(process)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            processBox.cancel()
        }
    }

    static func probe(url: URL) async throws -> FFmpegMediaInfo {
        guard let probeExecutableURL else {
            throw FFmpegToolError.probeExecutableNotFound
        }
        let data = try await capture(
            executableURL: probeExecutableURL,
            arguments: [
                "-v", "error",
                "-show_entries",
                "format=duration,size,bit_rate:stream=codec_name,codec_long_name,codec_tag_string,codec_type,width,height,avg_frame_rate,r_frame_rate,bit_rate,sample_rate,channels",
                "-of", "json",
                url.path
            ]
        )
        return try decodeProbeOutput(data)
    }

    static func decodeProbeOutput(_ data: Data) throws -> FFmpegMediaInfo {
        let payload: ProbePayload
        do {
            payload = try JSONDecoder().decode(ProbePayload.self, from: data)
        } catch {
            throw FFmpegToolError.probeFailed(error.localizedDescription)
        }

        guard let video = payload.streams.first(where: { $0.codecType == "video" }) else {
            throw FFmpegToolError.unsupportedMedia
        }
        let audio = payload.streams.first(where: { $0.codecType == "audio" })
        let videoIdentifier = video.codecName ?? "unknown"
        let audioIdentifier = audio?.codecName
        let totalBitRate = number(payload.format?.bitRate)
        let audioBitRate = number(audio?.bitRate)
        var videoBitRate = number(video.bitRate)
        if videoBitRate <= 0, totalBitRate > audioBitRate {
            videoBitRate = totalBitRate - audioBitRate
        }

        return FFmpegMediaInfo(
            duration: number(payload.format?.duration),
            width: video.width ?? 0,
            height: video.height ?? 0,
            frameRate: frameRate(video.averageFrameRate ?? video.realFrameRate),
            fileSize: Int64(number(payload.format?.size).rounded()),
            totalBitRate: totalBitRate,
            videoCodec: videoCodecName(
                identifier: videoIdentifier,
                longName: video.codecLongName,
                tag: video.codecTag
            ),
            videoCodecIdentifier: videoIdentifier,
            videoBitRate: videoBitRate,
            audioCodec: audioIdentifier.map {
                audioCodecName(identifier: $0, longName: audio?.codecLongName)
            },
            audioCodecIdentifier: audioIdentifier,
            audioSampleRate: number(audio?.sampleRate),
            audioChannelCount: audio?.channels ?? 0,
            audioBitRate: audioBitRate
        )
    }

    private static func executable(named name: String) -> URL? {
        let fileManager = FileManager.default
        let bundledCandidates = [
            Bundle.main.url(forAuxiliaryExecutable: name),
            Bundle.main.resourceURL?.appendingPathComponent(name)
        ].compactMap { $0 }
        let commonCandidates = [
            URL(fileURLWithPath: "/opt/homebrew/bin/\(name)"),
            URL(fileURLWithPath: "/usr/local/bin/\(name)"),
            URL(fileURLWithPath: "/usr/bin/\(name)")
        ]

        return (bundledCandidates + commonCandidates).first {
            fileManager.isExecutableFile(atPath: $0.path)
        }
    }

    static func capture(
        executableURL: URL,
        arguments: [String]
    ) async throws -> Data {
        let processBox = RunningProcessBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Data, Error>) in
                do {
                    let process = Process()
                    let outputPipe = Pipe()
                    let errorPipe = Pipe()
                    process.executableURL = executableURL
                    process.arguments = arguments
                    process.standardOutput = outputPipe
                    process.standardError = errorPipe
                    process.terminationHandler = { completedProcess in
                        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
                        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        let errorText = String(decoding: errorData, as: UTF8.self)
                        if processBox.wasCancellationRequested {
                            continuation.resume(throwing: CancellationError())
                        } else if completedProcess.terminationStatus == 0 {
                            continuation.resume(returning: output)
                        } else {
                            continuation.resume(
                                throwing: FFmpegToolError.probeFailed(errorText)
                            )
                        }
                    }
                    try process.run()
                    processBox.install(process)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            processBox.cancel()
        }
    }

    private static func number(_ value: String?) -> Double {
        guard let value else { return 0 }
        return Double(value) ?? 0
    }

    private static func frameRate(_ value: String?) -> Double {
        guard let value, !value.isEmpty else { return 0 }
        let components = value.split(separator: "/", maxSplits: 1)
        if components.count == 2,
           let numerator = Double(components[0]),
           let denominator = Double(components[1]),
           denominator != 0 {
            return numerator / denominator
        }
        return Double(value) ?? 0
    }

    private static func videoCodecName(
        identifier: String,
        longName: String?,
        tag: String?
    ) -> String {
        let normalized = identifier.lowercased()
        let normalizedTag = tag?.uppercased() ?? ""
        switch normalized {
        case "h264": return "H.264 / AVC"
        case "hevc": return "H.265 / HEVC"
        case "av1": return "AV1"
        case "vp9": return "VP9"
        case "vp8": return "VP8"
        case "mpeg4":
            if normalizedTag.contains("XVID") { return "Xvid / MPEG-4 Part 2" }
            if normalizedTag.contains("DIVX") || normalizedTag.contains("DX50") {
                return "DivX / MPEG-4 Part 2"
            }
            return "MPEG-4 Part 2"
        case "mpeg2video": return "MPEG-2 Video"
        case "mpeg1video": return "MPEG-1 Video"
        case "prores": return "Apple ProRes"
        case "dnxhd": return "Avid DNxHD / DNxHR"
        case "mjpeg": return "Motion JPEG"
        case "wmv3": return "Windows Media Video 9"
        case "wmv2": return "Windows Media Video 8"
        case "vc1": return "VC-1"
        case "theora": return "Theora"
        case "cfhd": return "GoPro CineForm"
        default:
            return longName?.trimmingCharacters(in: .whitespacesAndNewlines)
                .nonEmpty ?? identifier.uppercased()
        }
    }

    private static func audioCodecName(identifier: String, longName: String?) -> String {
        switch identifier.lowercased() {
        case "aac": return "AAC"
        case "mp3": return "MP3"
        case "ac3": return "Dolby Digital"
        case "eac3": return "Dolby Digital Plus"
        case "opus": return "Opus"
        case "vorbis": return "Vorbis"
        case "flac": return "FLAC"
        case "alac": return "Apple Lossless"
        case "pcm_s16le", "pcm_s24le", "pcm_s32le", "pcm_f32le": return "Linear PCM"
        case "wmav1": return "Windows Media Audio 1"
        case "wmav2": return "Windows Media Audio 2"
        case "dts": return "DTS"
        default:
            return longName?.trimmingCharacters(in: .whitespacesAndNewlines)
                .nonEmpty ?? identifier.uppercased()
        }
    }
}

enum MediaCompatibilityPreparer {
    static let supportedFileExtensions = [
        "mov", "mp4", "m4v", "avi", "mkv", "webm", "wmv", "asf",
        "mpg", "mpeg", "mpe", "vob", "ts", "m2ts", "mts", "mxf",
        "flv", "f4v", "3gp", "3g2", "ogv", "rm", "rmvb", "divx",
        "dv", "mod", "tod", "m4ts", "m2v", "h264", "264", "h265",
        "265", "hevc", "av1"
    ]

    private static let nativeCandidateExtensions: Set<String> = [
        "mov", "mp4", "m4v", "3gp", "3g2"
    ]
    private static let temporaryDirectoryRootNames = ["FrameCut-Media", "FrameCut-AVI"]

    static func requiresPreparation(for url: URL) -> Bool {
        let fileExtension = url.pathExtension.lowercased()
        return supportedFileExtensions.contains(fileExtension)
            && !nativeCandidateExtensions.contains(fileExtension)
    }

    static func prepare(
        url: URL,
        onUpdate: @escaping @Sendable (MediaPreparationUpdate) -> Void = { _ in }
    ) async throws -> PreparedMediaSource {
        onUpdate(MediaPreparationUpdate(stage: .checking, progress: nil))
        if !requiresPreparation(for: url), await isAVFoundationDecodable(url) {
            return .original(url)
        }

        let sourceInfo = try await FFmpegTool.probe(url: url)
        guard sourceInfo.width > 0, sourceInfo.height > 0 else {
            throw FFmpegToolError.unsupportedMedia
        }

        let fileManager = FileManager.default
        let temporaryDirectoryURL = fileManager.temporaryDirectory
            .appendingPathComponent(
                "FrameCut-Media-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString)",
                isDirectory: true
            )
        let remuxedURL = temporaryDirectoryURL.appendingPathComponent("remuxed.mov")
        let transcodedURL = temporaryDirectoryURL.appendingPathComponent("preview.mov")

        do {
            try fileManager.createDirectory(
                at: temporaryDirectoryURL,
                withIntermediateDirectories: true
            )

            onUpdate(MediaPreparationUpdate(stage: .remuxing, progress: nil))
            do {
                try await FFmpegTool.run(arguments: [
                    "-nostdin", "-y", "-hide_banner", "-loglevel", "error",
                    "-fflags", "+genpts",
                    "-i", url.path,
                    "-map", "0:v:0", "-map", "0:a:0?",
                    "-sn", "-dn", "-c", "copy",
                    "-avoid_negative_ts", "make_zero", "-f", "mov",
                    remuxedURL.path
                ])
                if await isAVFoundationDecodable(remuxedURL) {
                    return PreparedMediaSource(
                        url: remuxedURL,
                        temporaryDirectoryURL: temporaryDirectoryURL,
                        preparationKind: .remuxed,
                        sourceInfo: sourceInfo
                    )
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Some containers/codecs cannot be represented in MOV without transcoding.
            }
            try? fileManager.removeItem(at: remuxedURL)

            let targetVideoBitRate = proxyVideoBitRate(for: sourceInfo)
            let keyframeInterval = max(24, min(240, Int((sourceInfo.frameRate * 2).rounded())))
            let commonArguments = [
                "-nostdin", "-y", "-hide_banner", "-loglevel", "error",
                "-fflags", "+genpts",
                "-i", url.path,
                "-map", "0:v:0", "-map", "0:a:0?", "-map_metadata", "0",
                "-sn", "-dn",
                "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2",
                "-fps_mode", "passthrough",
                "-b:v", "\(targetVideoBitRate)",
                "-maxrate", "\(targetVideoBitRate * 2)",
                "-bufsize", "\(targetVideoBitRate * 4)",
                "-g", "\(keyframeInterval)",
                "-pix_fmt", "yuv420p", "-tag:v", "avc1",
                "-c:a", "aac", "-b:a", "128k", "-ac", "2",
                "-avoid_negative_ts", "make_zero", "-movflags", "+faststart",
                transcodedURL.path
            ]

            onUpdate(MediaPreparationUpdate(stage: .transcodingHardware, progress: 0))
            do {
                try await FFmpegTool.run(
                    arguments: insertingVideoEncoder(
                        ["-c:v", "h264_videotoolbox", "-allow_sw", "1"],
                        into: commonArguments
                    ),
                    duration: sourceInfo.duration,
                    onProgress: { progress in
                        onUpdate(MediaPreparationUpdate(
                            stage: .transcodingHardware,
                            progress: progress
                        ))
                    }
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try? fileManager.removeItem(at: transcodedURL)
                onUpdate(MediaPreparationUpdate(stage: .transcodingSoftware, progress: 0))
                try await FFmpegTool.run(
                    arguments: insertingVideoEncoder(
                        ["-c:v", "libx264", "-preset", "veryfast"],
                        into: commonArguments
                    ),
                    duration: sourceInfo.duration,
                    onProgress: { progress in
                        onUpdate(MediaPreparationUpdate(
                            stage: .transcodingSoftware,
                            progress: progress
                        ))
                    }
                )
            }

            let attributes = try fileManager.attributesOfItem(atPath: transcodedURL.path)
            let byteCount = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            guard byteCount > 0, await isAVFoundationDecodable(transcodedURL) else {
                throw FFmpegToolError.invalidOutput
            }
            return PreparedMediaSource(
                url: transcodedURL,
                temporaryDirectoryURL: temporaryDirectoryURL,
                preparationKind: .transcoded,
                sourceInfo: sourceInfo
            )
        } catch {
            try? fileManager.removeItem(at: temporaryDirectoryURL)
            throw error
        }
    }

    static func discardStaleTemporaryDirectories() {
        discardTemporaryDirectories { rootName, directoryName in
            guard let ownerProcessIdentifier = ownerProcessIdentifier(
                from: directoryName,
                rootName: rootName
            ) else {
                return true
            }
            return !isProcessRunning(ownerProcessIdentifier)
        }
    }

    static func discardOwnedTemporaryDirectories() {
        let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        discardTemporaryDirectories { rootName, directoryName in
            ownerProcessIdentifier(from: directoryName, rootName: rootName)
                == currentProcessIdentifier
        }
    }

    private static func isAVFoundationDecodable(_ url: URL) async -> Bool {
        do {
            let asset = AVURLAsset(url: url)
            guard try await asset.load(.isPlayable),
                  let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
                return false
            }
            let audioTrack = try await asset.loadTracks(withMediaType: .audio).first
            let reader = try AVAssetReader(asset: asset)
            let videoOutput = AVAssetReaderTrackOutput(
                track: videoTrack,
                outputSettings: [
                    kCVPixelBufferPixelFormatTypeKey as String:
                        NSNumber(value: kCVPixelFormatType_32BGRA)
                ]
            )
            guard reader.canAdd(videoOutput) else { return false }
            reader.add(videoOutput)

            var audioOutput: AVAssetReaderTrackOutput?
            if let audioTrack {
                let output = AVAssetReaderTrackOutput(
                    track: audioTrack,
                    outputSettings: [
                        AVFormatIDKey: NSNumber(value: kAudioFormatLinearPCM),
                        AVLinearPCMBitDepthKey: 16,
                        AVLinearPCMIsFloatKey: false,
                        AVLinearPCMIsNonInterleaved: false
                    ]
                )
                guard reader.canAdd(output) else { return false }
                reader.add(output)
                audioOutput = output
            }

            guard reader.startReading() else { return false }
            let videoSample = videoOutput.copyNextSampleBuffer()
            let audioSample = audioOutput?.copyNextSampleBuffer()
            reader.cancelReading()
            return videoSample != nil && (audioOutput == nil || audioSample != nil)
        } catch {
            return false
        }
    }

    private static func proxyVideoBitRate(for info: FFmpegMediaInfo) -> Int {
        let pixels = Double(max(1, info.width)) * Double(max(1, info.height))
        let framesPerSecond = min(60, max(1, info.frameRate))
        let bitsPerPixel: Double
        if pixels > 4_000_000 {
            bitsPerPixel = 0.055
        } else if pixels > 1_000_000 {
            bitsPerPixel = 0.08
        } else {
            bitsPerPixel = 0.10
        }
        return Int(min(20_000_000, max(800_000, pixels * framesPerSecond * bitsPerPixel)).rounded())
    }

    private static func insertingVideoEncoder(
        _ encoderArguments: [String],
        into commonArguments: [String]
    ) -> [String] {
        guard let insertionIndex = commonArguments.firstIndex(of: "-b:v") else {
            return commonArguments + encoderArguments
        }
        var arguments = commonArguments
        arguments.insert(contentsOf: encoderArguments, at: insertionIndex)
        return arguments
    }

    private static func discardTemporaryDirectories(
        matching predicate: (String, String) -> Bool
    ) {
        let fileManager = FileManager.default
        let temporaryRootURL = fileManager.temporaryDirectory
        guard let entries = try? fileManager.contentsOfDirectory(
            at: temporaryRootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for entry in entries {
            let name = entry.lastPathComponent
            guard let rootName = temporaryDirectoryRootNames.first(where: {
                name.hasPrefix("\($0)-")
            }), predicate(rootName, name) else { continue }
            try? fileManager.removeItem(at: entry)
        }
    }

    private static func ownerProcessIdentifier(
        from directoryName: String,
        rootName: String
    ) -> Int32? {
        let prefix = "\(rootName)-"
        guard directoryName.hasPrefix(prefix) else { return nil }
        let suffix = directoryName.dropFirst(prefix.count)
        guard let separatorIndex = suffix.firstIndex(of: "-") else { return nil }
        return Int32(suffix[..<separatorIndex])
    }

    private static func isProcessRunning(_ processIdentifier: Int32) -> Bool {
        guard processIdentifier > 0 else { return false }
        if kill(pid_t(processIdentifier), 0) == 0 { return true }
        return errno == EPERM
    }
}

typealias AVICompatibilityPreparer = MediaCompatibilityPreparer

final class FFmpegProgressParser: @unchecked Sendable {
    private let lock = NSLock()
    private let duration: Double
    private let onProgress: @Sendable (Double) -> Void
    private var progressBuffer = ""
    private var errorData = Data()

    init(duration: Double, onProgress: @escaping @Sendable (Double) -> Void) {
        self.duration = max(0.001, duration)
        self.onProgress = onProgress
    }

    func consumeProgress(_ data: Data) {
        guard !data.isEmpty else { return }
        var progressValues: [Double] = []

        lock.lock()
        progressBuffer += String(decoding: data, as: UTF8.self)
        let lines = progressBuffer.split(separator: "\n", omittingEmptySubsequences: false)
        progressBuffer = String(lines.last ?? "")
        for line in lines.dropLast() where line.hasPrefix("out_time_us=") {
            let value = line.dropFirst("out_time_us=".count)
            if let microseconds = Double(value) {
                progressValues.append(min(0.995, max(0, microseconds / 1_000_000 / duration)))
            }
        }
        lock.unlock()

        for progress in progressValues {
            onProgress(progress)
        }
    }

    func consumeError(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        errorData.append(data)
        if errorData.count > 16_000 {
            errorData.removeFirst(errorData.count - 16_000)
        }
        lock.unlock()
    }

    var errorMessage: String {
        lock.lock()
        let data = errorData
        lock.unlock()
        return String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private final class RunningProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancellationRequested = false

    var wasCancellationRequested: Bool {
        lock.lock()
        let value = cancellationRequested
        lock.unlock()
        return value
    }

    func install(_ process: Process) {
        lock.lock()
        self.process = process
        let shouldCancel = cancellationRequested
        lock.unlock()
        if shouldCancel, process.isRunning {
            process.terminate()
        }
    }

    func cancel() {
        lock.lock()
        cancellationRequested = true
        let process = process
        lock.unlock()
        if let process, process.isRunning {
            process.terminate()
        }
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}

private struct ProbePayload: Decodable {
    let streams: [ProbeStream]
    let format: ProbeFormat?
}

private struct ProbeStream: Decodable {
    let codecName: String?
    let codecLongName: String?
    let codecTag: String?
    let codecType: String?
    let width: Int?
    let height: Int?
    let averageFrameRate: String?
    let realFrameRate: String?
    let bitRate: String?
    let sampleRate: String?
    let channels: Int?

    enum CodingKeys: String, CodingKey {
        case codecName = "codec_name"
        case codecLongName = "codec_long_name"
        case codecTag = "codec_tag_string"
        case codecType = "codec_type"
        case width
        case height
        case averageFrameRate = "avg_frame_rate"
        case realFrameRate = "r_frame_rate"
        case bitRate = "bit_rate"
        case sampleRate = "sample_rate"
        case channels
    }
}

private struct ProbeFormat: Decodable {
    let duration: String?
    let size: String?
    let bitRate: String?

    enum CodingKeys: String, CodingKey {
        case duration
        case size
        case bitRate = "bit_rate"
    }
}
