import AppKit
import AVFoundation
import Foundation

struct MediaMetadata: Equatable {
    let duration: Double
    let width: Int
    let height: Int
    let frameRate: Double
    let hasAudio: Bool
    let containerFormat: String
    let fileSize: Int64
    let videoCodec: String
    let videoBitRate: Double
    let audioCodec: String?
    let audioSampleRate: Double
    let audioChannelCount: Int
    let audioBitRate: Double

    init(
        duration: Double,
        width: Int,
        height: Int,
        frameRate: Double,
        hasAudio: Bool,
        containerFormat: String = "未知",
        fileSize: Int64 = 0,
        videoCodec: String = "未知",
        videoBitRate: Double = 0,
        audioCodec: String? = nil,
        audioSampleRate: Double = 0,
        audioChannelCount: Int = 0,
        audioBitRate: Double = 0
    ) {
        self.duration = duration
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.hasAudio = hasAudio
        self.containerFormat = containerFormat
        self.fileSize = fileSize
        self.videoCodec = videoCodec
        self.videoBitRate = videoBitRate
        self.audioCodec = audioCodec
        self.audioSampleRate = audioSampleRate
        self.audioChannelCount = audioChannelCount
        self.audioBitRate = audioBitRate
    }

    var resolutionText: String {
        guard width > 0, height > 0 else { return "未知分辨率" }
        return "\(width) × \(height)"
    }

    var frameRateText: String {
        let rounded = frameRate.rounded()
        if abs(frameRate - rounded) < 0.01 {
            return "\(Int(rounded)) fps"
        }
        return String(format: "%.2f fps", frameRate)
    }

    var aspectRatioText: String {
        guard width > 0, height > 0 else { return "未知" }
        let divisor = greatestCommonDivisor(width, height)
        return "\(width / divisor):\(height / divisor)"
    }

    var fileSizeText: String {
        guard fileSize > 0 else { return "未知" }
        return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    var videoBitRateText: String {
        MediaFormatInfo.bitRateText(videoBitRate)
    }

    var audioSampleRateText: String {
        guard audioSampleRate > 0 else { return "未知" }
        if audioSampleRate >= 1_000 {
            let kilohertz = audioSampleRate / 1_000
            if abs(kilohertz - kilohertz.rounded()) < 0.01 {
                return "\(Int(kilohertz.rounded())) kHz"
            }
            return String(format: "%.1f kHz", kilohertz)
        }
        return "\(Int(audioSampleRate.rounded())) Hz"
    }

    var audioChannelText: String {
        switch audioChannelCount {
        case 1: return "单声道"
        case 2: return "立体声"
        case let count where count > 0: return "\(count) 声道"
        default: return "未知"
        }
    }

    var audioBitRateText: String {
        MediaFormatInfo.bitRateText(audioBitRate)
    }

    private func greatestCommonDivisor(_ lhs: Int, _ rhs: Int) -> Int {
        var a = abs(lhs)
        var b = abs(rhs)
        while b != 0 {
            let remainder = a % b
            a = b
            b = remainder
        }
        return max(1, a)
    }
}

enum SourceCompressionAssessment: Equatable {
    case unknown
    case alreadyCompressed
    case efficient
    case highQuality
    case bitrateRich

    var title: String {
        switch self {
        case .unknown: return "质量待估"
        case .alreadyCompressed: return "已高度压缩"
        case .efficient: return "码率合理"
        case .highQuality: return "高质量源"
        case .bitrateRich: return "码率富余"
        }
    }

    var detail: String {
        switch self {
        case .unknown:
            return "未能读取完整码率，按分辨率和帧率给出保守建议"
        case .alreadyCompressed:
            return "源文件压缩程度较高，仅建议轻度缩小以避免明显损失"
        case .efficient:
            return "当前码率较合理，建议适度压缩并保留原始画面尺寸"
        case .highQuality:
            return "源画面质量较高，可在大致保持观感的同时降低码率"
        case .bitrateRich:
            return "单位像素码率较充足，转为 HEVC 可明显减小体积"
        }
    }
}

struct SmartCompressionRecommendation: Equatable {
    let assessment: SourceCompressionAssessment
    let sourceVideoBitRate: Double
    let targetVideoBitRate: Double
    let targetAudioBitRate: Double
    let sourceBitsPerPixelPerFrame: Double
    let estimatedReduction: Double?

    var targetTotalBitRate: Double {
        max(0, targetVideoBitRate) + max(0, targetAudioBitRate)
    }

    var sourceVideoBitRateText: String {
        MediaFormatInfo.bitRateText(sourceVideoBitRate)
    }

    var targetVideoBitRateText: String {
        MediaFormatInfo.bitRateText(targetVideoBitRate)
    }

    var reductionPercent: Int? {
        guard let estimatedReduction, estimatedReduction.isFinite else { return nil }
        return Int((min(0.95, max(0, estimatedReduction)) * 100).rounded())
    }

    func estimatedByteCount(duration: Double) -> Int64 {
        guard duration > 0, targetTotalBitRate > 0 else { return 0 }
        return max(1, Int64((targetTotalBitRate * duration / 8).rounded()))
    }
}

enum SmartCompressionAdvisor {
    static func recommendation(for metadata: MediaMetadata) -> SmartCompressionRecommendation {
        let pixels = Double(max(1, metadata.width)) * Double(max(1, metadata.height))
        let framesPerSecond = min(max(metadata.frameRate, 1), 120)
        let pixelRate = pixels * framesPerSecond
        let fileDerivedTotalBitRate: Double
        if metadata.fileSize > 0, metadata.duration > 0 {
            fileDerivedTotalBitRate = Double(metadata.fileSize) * 8 / metadata.duration
        } else {
            fileDerivedTotalBitRate = 0
        }

        let knownAudioBitRate = metadata.hasAudio
            ? max(0, metadata.audioBitRate)
            : 0
        let sourceVideoBitRate: Double
        if metadata.videoBitRate > 0 {
            sourceVideoBitRate = metadata.videoBitRate
        } else if fileDerivedTotalBitRate > knownAudioBitRate {
            sourceVideoBitRate = fileDerivedTotalBitRate - knownAudioBitRate
        } else {
            sourceVideoBitRate = 0
        }

        let targetAudioBitRate: Double
        if !metadata.hasAudio {
            targetAudioBitRate = 0
        } else if knownAudioBitRate > 0 {
            targetAudioBitRate = min(160_000, knownAudioBitRate)
        } else {
            targetAudioBitRate = 128_000
        }

        guard sourceVideoBitRate > 0 else {
            let fallbackBitsPerPixel = defaultTargetBitsPerPixel(for: pixels)
            return SmartCompressionRecommendation(
                assessment: .unknown,
                sourceVideoBitRate: 0,
                targetVideoBitRate: pixelRate * fallbackBitsPerPixel,
                targetAudioBitRate: targetAudioBitRate,
                sourceBitsPerPixelPerFrame: 0,
                estimatedReduction: nil
            )
        }

        let sourceBitsPerPixelPerFrame = sourceVideoBitRate / pixelRate
        let codecEfficiency = relativeCodecBitRate(for: metadata.videoCodec)
        let normalizedQualityDensity = sourceBitsPerPixelPerFrame / codecEfficiency
        let assessment: SourceCompressionAssessment
        var baseTargetRatio: Double

        switch normalizedQualityDensity {
        case ..<0.05:
            assessment = .alreadyCompressed
            baseTargetRatio = 0.90
        case ..<0.09:
            assessment = .efficient
            baseTargetRatio = 0.78
        case ..<0.16:
            assessment = .highQuality
            baseTargetRatio = 0.65
        default:
            assessment = .bitrateRich
            baseTargetRatio = 0.52
        }

        if isLegacyMPEG4Codec(metadata.videoCodec),
           assessment == .highQuality || assessment == .bitrateRich {
            baseTargetRatio = min(baseTargetRatio, 0.44)
        }

        let codecAwareRatio: Double
        switch codecEfficiency {
        case ..<0.65:
            codecAwareRatio = max(baseTargetRatio, 0.88)
        case ..<0.8:
            codecAwareRatio = max(baseTargetRatio, 0.82)
        default:
            codecAwareRatio = baseTargetRatio
        }

        let targetFloor = pixelRate * minimumTargetBitsPerPixel(for: pixels)
        let targetCeiling = pixelRate * maximumTargetBitsPerPixel(for: pixels)
        let reductionCandidate = min(sourceVideoBitRate * codecAwareRatio, targetCeiling)
        let qualityProtectedCandidate = max(min(sourceVideoBitRate, targetFloor), reductionCandidate)
        let targetVideoBitRate = min(sourceVideoBitRate * 0.92, qualityProtectedCandidate)

        let trackDerivedSourceTotal = sourceVideoBitRate + knownAudioBitRate
        let sourceTotalBitRate = fileDerivedTotalBitRate > 0
            ? fileDerivedTotalBitRate
            : trackDerivedSourceTotal
        let targetTotalBitRate = targetVideoBitRate + targetAudioBitRate
        let estimatedReduction = sourceTotalBitRate > 0
            ? min(0.95, max(0, 1 - targetTotalBitRate / sourceTotalBitRate))
            : nil

        return SmartCompressionRecommendation(
            assessment: assessment,
            sourceVideoBitRate: sourceVideoBitRate,
            targetVideoBitRate: targetVideoBitRate,
            targetAudioBitRate: targetAudioBitRate,
            sourceBitsPerPixelPerFrame: sourceBitsPerPixelPerFrame,
            estimatedReduction: estimatedReduction
        )
    }

    private static func relativeCodecBitRate(for codec: String) -> Double {
        let normalized = codec.lowercased()
        if normalized.contains("av1") { return 0.60 }
        if normalized.contains("h.265") || normalized.contains("hevc") { return 0.68 }
        if normalized.contains("vp9") { return 0.72 }
        return 1
    }

    private static func isLegacyMPEG4Codec(_ codec: String) -> Bool {
        let normalized = codec.lowercased()
        return normalized.contains("mpeg-4 video") || normalized.contains("mpeg-4 part 2")
    }

    private static func minimumTargetBitsPerPixel(for pixels: Double) -> Double {
        if pixels > 4_000_000 { return 0.045 }
        if pixels > 1_000_000 { return 0.05 }
        return 0.06
    }

    private static func maximumTargetBitsPerPixel(for pixels: Double) -> Double {
        if pixels > 4_000_000 { return 0.12 }
        if pixels > 1_000_000 { return 0.14 }
        return 0.16
    }

    private static func defaultTargetBitsPerPixel(for pixels: Double) -> Double {
        if pixels > 4_000_000 { return 0.055 }
        if pixels > 1_000_000 { return 0.065 }
        return 0.075
    }
}

enum MediaFormatInfo {
    static func containerName(for url: URL) -> String {
        let fileExtension = url.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        return fileExtension.isEmpty ? "未知" : fileExtension.uppercased()
    }

    static func codecName(from description: CMFormatDescription?) -> String {
        guard let description else { return "未知" }
        let code = fourCCString(CMFormatDescriptionGetMediaSubType(description))
        switch code.lowercased() {
        case "avc1", "avc3": return "H.264 / AVC"
        case "hvc1", "hev1": return "H.265 / HEVC"
        case "ap4h": return "Apple ProRes 4444"
        case "ap4x": return "Apple ProRes 4444 XQ"
        case "apch": return "Apple ProRes 422 HQ"
        case "apcn": return "Apple ProRes 422"
        case "apcs": return "Apple ProRes 422 LT"
        case "apco": return "Apple ProRes 422 Proxy"
        case "mp4v": return "MPEG-4 Video"
        case "jpeg", "mjpg": return "Motion JPEG"
        case "vp09": return "VP9"
        case "av01": return "AV1"
        case "mp4a": return "AAC"
        case "lpcm": return "Linear PCM"
        case ".mp3", "mp3 ": return "MP3"
        case "alac": return "Apple Lossless"
        case "ac-3": return "Dolby Digital"
        case "ec-3": return "Dolby Digital Plus"
        case "opus": return "Opus"
        default:
            let cleaned = code.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? "未知" : cleaned.uppercased()
        }
    }

    static func audioProperties(
        from description: CMFormatDescription?
    ) -> (sampleRate: Double, channelCount: Int) {
        guard let description,
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(description)
        else {
            return (0, 0)
        }
        return (
            streamDescription.pointee.mSampleRate,
            Int(streamDescription.pointee.mChannelsPerFrame)
        )
    }

    static func bitRateText(_ bitsPerSecond: Double) -> String {
        guard bitsPerSecond.isFinite, bitsPerSecond > 0 else { return "未知" }
        if bitsPerSecond >= 1_000_000 {
            return String(format: "%.2f Mbps", bitsPerSecond / 1_000_000)
        }
        return "\(Int((bitsPerSecond / 1_000).rounded())) kbps"
    }

    private static func fourCCString(_ value: FourCharCode) -> String {
        let bytes: [UInt8] = [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ]
        return String(bytes: bytes, encoding: .macOSRoman) ?? ""
    }
}

struct FrameIndexResult: Sendable {
    let frameTimes: [Double]
    let keyframeTimes: [Double]
}

struct GeneratedThumbnail: Sendable {
    let index: Int
    let time: Double
    let data: Data
}

struct TimelineThumbnail: Identifiable {
    let id: Int
    let time: Double
    let image: NSImage
}

enum MediaProcessingError: LocalizedError {
    case noVideoTrack
    case cannotStartReader
    case cannotGenerateThumbnails
    case cannotCreateExportSession
    case unsupportedExportFormat
    case invalidSelection

    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "这个文件中没有可读取的视频轨道。"
        case .cannotStartReader:
            return "无法建立视频帧索引。"
        case .cannotGenerateThumbnails:
            return "无法生成时间轴缩略图。"
        case .cannotCreateExportSession:
            return "无法为这个视频创建导出任务。"
        case .unsupportedExportFormat:
            return "当前视频不支持所选导出格式。"
        case .invalidSelection:
            return "入点和出点没有形成有效的视频区间。"
        }
    }
}

enum FrameMath {
    static func nearestIndex(in values: [Double], to target: Double) -> Int? {
        guard !values.isEmpty else { return nil }

        var lower = 0
        var upper = values.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if values[middle] < target {
                lower = middle + 1
            } else {
                upper = middle
            }
        }

        if lower == 0 { return 0 }
        if lower == values.count { return values.count - 1 }

        let before = values[lower - 1]
        let after = values[lower]
        return abs(target - before) <= abs(after - target) ? lower - 1 : lower
    }

    static func previousIndex(in values: [Double], before target: Double, epsilon: Double = 0.000_5) -> Int? {
        guard !values.isEmpty else { return nil }
        var lower = 0
        var upper = values.count
        let threshold = target - epsilon

        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if values[middle] < threshold {
                lower = middle + 1
            } else {
                upper = middle
            }
        }

        let candidate = lower - 1
        return candidate >= 0 ? candidate : nil
    }

    static func nextIndex(in values: [Double], after target: Double, epsilon: Double = 0.000_5) -> Int? {
        guard !values.isEmpty else { return nil }
        var lower = 0
        var upper = values.count
        let threshold = target + epsilon

        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if values[middle] <= threshold {
                lower = middle + 1
            } else {
                upper = middle
            }
        }

        return lower < values.count ? lower : nil
    }

    static func timecode(seconds: Double, frameRate: Double) -> String {
        let safeSeconds = max(0, seconds.isFinite ? seconds : 0)
        let displayRate = max(1, Int(frameRate.rounded()))
        let wholeSeconds = Int(floor(safeSeconds))
        let hours = wholeSeconds / 3_600
        let minutes = (wholeSeconds % 3_600) / 60
        let secondsPart = wholeSeconds % 60
        let fraction = safeSeconds - floor(safeSeconds)
        let frame = min(displayRate - 1, max(0, Int(floor(fraction * Double(displayRate)))))
        return String(format: "%02d:%02d:%02d:%02d", hours, minutes, secondsPart, frame)
    }

    static func clock(seconds: Double) -> String {
        let safeSeconds = max(0, seconds.isFinite ? seconds : 0)
        let totalMilliseconds = Int((safeSeconds * 1_000).rounded())
        let hours = totalMilliseconds / 3_600_000
        let minutes = (totalMilliseconds % 3_600_000) / 60_000
        let secondsPart = (totalMilliseconds % 60_000) / 1_000
        let milliseconds = totalMilliseconds % 1_000

        if hours > 0 {
            return String(format: "%02d:%02d:%02d.%03d", hours, minutes, secondsPart, milliseconds)
        }
        return String(format: "%02d:%02d.%03d", minutes, secondsPart, milliseconds)
    }

    static func endExclusive(
        outPoint: Double,
        duration: Double,
        frameDuration: Double,
        frameTimes: [Double]
    ) -> Double {
        guard duration > 0 else { return 0 }
        if let index = nearestIndex(in: frameTimes, to: outPoint) {
            if index + 1 < frameTimes.count {
                return min(duration, max(outPoint, frameTimes[index + 1]))
            }
            return duration
        }
        return min(duration, outPoint + max(frameDuration, 1.0 / 30.0))
    }
}

enum FrameIndexBuilder {
    static func build(url: URL) async throws -> FrameIndexResult {
        let asset = AVURLAsset(url: url)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw MediaProcessingError.noVideoTrack
        }
        let trackTimeRange = try await videoTrack.load(.timeRange)

        if try await videoTrack.load(.canProvideSampleCursors),
           let cursor = videoTrack.makeSampleCursorAtFirstSampleInDecodeOrder() {
            return try buildUsingSampleCursor(cursor, trackTimeRange: trackTimeRange)
        }

        return try buildUsingAssetReader(
            asset: asset,
            videoTrack: videoTrack,
            trackTimeRange: trackTimeRange
        )
    }

    private static func buildUsingSampleCursor(
        _ cursor: AVSampleCursor,
        trackTimeRange: CMTimeRange
    ) throws -> FrameIndexResult {
        var frameTimes: [Double] = []
        var keyframeTimes: [Double] = []
        frameTimes.reserveCapacity(18_000)
        keyframeTimes.reserveCapacity(600)

        var sampleCount = 0
        repeat {
            if sampleCount.isMultiple(of: 2_048) {
                try Task.checkCancellation()
            }
            sampleCount += 1

            let seconds = cursor.presentationTimeStamp.seconds
            guard seconds.isFinite, seconds >= 0 else { continue }
            frameTimes.append(seconds)
            let syncInfo = cursor.currentSampleSyncInfo
            if syncInfo.sampleIsFullSync.boolValue || syncInfo.sampleIsPartialSync.boolValue {
                keyframeTimes.append(seconds)
            }
        } while cursor.stepInPresentationOrder(byCount: 1) == 1

        return normalizedIndex(
            frameTimes: frameTimes,
            keyframeTimes: keyframeTimes,
            trackTimeRange: trackTimeRange
        )
    }

    private static func buildUsingAssetReader(
        asset: AVAsset,
        videoTrack: AVAssetTrack,
        trackTimeRange: CMTimeRange
    ) throws -> FrameIndexResult {

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
        output.alwaysCopiesSampleData = false

        guard reader.canAdd(output) else {
            throw MediaProcessingError.cannotStartReader
        }
        reader.add(output)
        guard reader.startReading() else {
            throw reader.error ?? MediaProcessingError.cannotStartReader
        }

        var allSampleTimes: [Double] = []
        var attachedSampleTimes: [Double] = []
        var keyframeTimes: [Double] = []
        allSampleTimes.reserveCapacity(18_000)
        attachedSampleTimes.reserveCapacity(18_000)
        keyframeTimes.reserveCapacity(600)

        while let sampleBuffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            let seconds = presentationTime.seconds
            guard seconds.isFinite, seconds >= 0 else { continue }
            allSampleTimes.append(seconds)

            let attachments = CMSampleBufferGetSampleAttachmentsArray(
                sampleBuffer,
                createIfNecessary: false
            ) as? [[CFString: Any]]
            if let attachment = attachments?.first {
                attachedSampleTimes.append(seconds)
                let isNotSync = attachment[kCMSampleAttachmentKey_NotSync] as? Bool ?? false
                if !isNotSync {
                    keyframeTimes.append(seconds)
                }
            }
        }

        if reader.status == .failed {
            throw reader.error ?? MediaProcessingError.cannotStartReader
        }

        let frameTimes = attachedSampleTimes.isEmpty ? allSampleTimes : attachedSampleTimes
        return normalizedIndex(
            frameTimes: frameTimes,
            keyframeTimes: keyframeTimes,
            trackTimeRange: trackTimeRange
        )
    }

    private static func normalizedIndex(
        frameTimes: [Double],
        keyframeTimes: [Double],
        trackTimeRange: CMTimeRange
    ) -> FrameIndexResult {
        var frameTimes = frameTimes
        var keyframeTimes = keyframeTimes
        frameTimes.sort()
        keyframeTimes.sort()
        frameTimes = deduplicated(frameTimes)
        keyframeTimes = deduplicated(keyframeTimes)

        // Compressed H.264/HEVC readers can report every presentation timestamp
        // shifted by the codec reorder delay. Align the first displayed frame to
        // the track's real start while preserving an intentional non-zero track start.
        if let firstFrame = frameTimes.first {
            let trackStart = trackTimeRange.start.seconds.isFinite ? trackTimeRange.start.seconds : 0
            let presentationOffset = firstFrame - trackStart
            frameTimes = frameTimes.map { max(0, $0 - presentationOffset) }
            keyframeTimes = keyframeTimes.map { max(0, $0 - presentationOffset) }
        }

        if keyframeTimes.isEmpty, let first = frameTimes.first {
            keyframeTimes = [first]
        }
        return FrameIndexResult(frameTimes: frameTimes, keyframeTimes: keyframeTimes)
    }

    private static func deduplicated(_ values: [Double]) -> [Double] {
        var result: [Double] = []
        result.reserveCapacity(values.count)
        for value in values {
            if let last = result.last, abs(last - value) < 0.000_001 {
                continue
            }
            result.append(value)
        }
        return result
    }
}

private final class ThumbnailBatchAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private let requestedSeconds: [Double]
    private let continuation: CheckedContinuation<[GeneratedThumbnail], Error>
    private var remaining: Int
    private var thumbnails: [GeneratedThumbnail] = []
    private var firstError: Error?
    private var wasCancelled = false

    init(
        requestedSeconds: [Double],
        continuation: CheckedContinuation<[GeneratedThumbnail], Error>
    ) {
        self.requestedSeconds = requestedSeconds
        self.continuation = continuation
        self.remaining = requestedSeconds.count
        thumbnails.reserveCapacity(requestedSeconds.count)
    }

    func receive(
        requestedTime: CMTime,
        image: CGImage?,
        result: AVAssetImageGenerator.Result,
        error: Error?
    ) {
        var thumbnail: GeneratedThumbnail?
        var callbackError: Error?
        var callbackWasCancelled = false

        switch result {
        case .succeeded:
            if let image,
               let index = FrameMath.nearestIndex(
                   in: requestedSeconds,
                   to: requestedTime.seconds
               ) {
                let bitmap = NSBitmapImageRep(cgImage: image)
                if let data = bitmap.representation(
                    using: .jpeg,
                    properties: [.compressionFactor: 0.68]
                ) {
                    thumbnail = GeneratedThumbnail(
                        index: index,
                        time: requestedSeconds[index],
                        data: data
                    )
                }
            }
        case .failed:
            callbackError = error ?? MediaProcessingError.cannotGenerateThumbnails
        case .cancelled:
            callbackWasCancelled = true
        @unknown default:
            callbackError = error ?? MediaProcessingError.cannotGenerateThumbnails
        }

        lock.lock()
        if let thumbnail {
            thumbnails.append(thumbnail)
        }
        if firstError == nil, let callbackError {
            firstError = callbackError
        }
        wasCancelled = wasCancelled || callbackWasCancelled
        remaining -= 1

        let completion: Result<[GeneratedThumbnail], Error>?
        if remaining == 0 {
            if wasCancelled {
                completion = .failure(CancellationError())
            } else if !thumbnails.isEmpty {
                completion = .success(thumbnails.sorted { $0.index < $1.index })
            } else {
                completion = .failure(firstError ?? MediaProcessingError.cannotGenerateThumbnails)
            }
        } else {
            completion = nil
        }
        lock.unlock()

        if let completion {
            continuation.resume(with: completion)
        }
    }
}

enum TimelineThumbnailGenerator {
    static func generate(
        url: URL,
        duration: Double,
        count: Int = 12
    ) async throws -> [GeneratedThumbnail] {
        let interval = duration / Double(max(1, count))
        return try await generateBatch(
            url: url,
            startTime: 0,
            endTime: duration,
            count: count,
            maximumSize: CGSize(width: 240, height: 135),
            tolerance: min(6, max(0.25, interval * 0.02))
        )
    }

    static func generate(
        url: URL,
        startTime: Double,
        endTime: Double,
        count: Int = 12
    ) async throws -> [GeneratedThumbnail] {
        let interval = (endTime - startTime) / Double(max(1, count))
        return try await generateBatch(
            url: url,
            startTime: startTime,
            endTime: endTime,
            count: count,
            maximumSize: CGSize(width: 240, height: 135),
            tolerance: min(0.75, max(0.08, interval * 0.1))
        )
    }

    private static func generateBatch(
        url: URL,
        startTime: Double,
        endTime: Double,
        count: Int,
        maximumSize: CGSize,
        tolerance: Double
    ) async throws -> [GeneratedThumbnail] {
        try Task.checkCancellation()

        let safeStart = max(0, startTime)
        let safeEnd = max(safeStart, endTime)
        let rangeDuration = safeEnd - safeStart
        guard rangeDuration > 0, count > 0 else { return [] }

        let latestTime = max(safeStart, safeEnd - 0.001)
        let requestedSeconds = (0..<count).map { index in
            let fraction = (Double(index) + 0.5) / Double(count)
            return min(safeStart + rangeDuration * fraction, latestTime)
        }
        let requestedTimes = requestedSeconds.map {
            NSValue(time: CMTime(seconds: $0, preferredTimescale: 60_000))
        }

        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = maximumSize
        let timeTolerance = CMTime(seconds: tolerance, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = timeTolerance
        generator.requestedTimeToleranceAfter = timeTolerance

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let accumulator = ThumbnailBatchAccumulator(
                    requestedSeconds: requestedSeconds,
                    continuation: continuation
                )
                generator.generateCGImagesAsynchronously(forTimes: requestedTimes) {
                    requestedTime,
                    image,
                    _,
                    result,
                    error in
                    accumulator.receive(
                        requestedTime: requestedTime,
                        image: image,
                        result: result,
                        error: error
                    )
                }
            }
        } onCancel: {
            generator.cancelAllCGImageGeneration()
        }
    }
}
