import AppKit
import AVFoundation
import Combine
import Foundation
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable, Identifiable {
    case mp4
    case mov

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mp4: return L10n.text("format.mp4")
        case .mov: return L10n.text("format.mov")
        }
    }

    var shortTitle: String {
        switch self {
        case .mp4: return "MP4"
        case .mov: return "MOV"
        }
    }

    var fileExtension: String { rawValue }

    var avFileType: AVFileType {
        switch self {
        case .mp4: return .mp4
        case .mov: return .mov
        }
    }

    var contentType: UTType {
        switch self {
        case .mp4: return .mpeg4Movie
        case .mov: return .quickTimeMovie
        }
    }
}

enum ExportCompression: String, CaseIterable, Identifiable {
    case smart
    case highQuality
    case balanced
    case spaceSaving

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smart: return L10n.text("compression.smart")
        case .highQuality: return L10n.text("compression.high_quality")
        case .balanced: return L10n.text("compression.balanced")
        case .spaceSaving: return L10n.text("compression.space_saving")
        }
    }

    var detail: String {
        switch self {
        case .smart: return L10n.text("compression.smart_detail")
        case .highQuality: return L10n.text("compression.high_quality_detail")
        case .balanced: return L10n.text("compression.balanced_detail")
        case .spaceSaving: return L10n.text("compression.space_saving_detail")
        }
    }

    var systemImage: String {
        switch self {
        case .smart: return "wand.and.stars"
        case .highQuality: return "sparkles.tv"
        case .balanced: return "scale.3d"
        case .spaceSaving: return "arrow.down.right.and.arrow.up.left"
        }
    }

    var avPresetName: String {
        switch self {
        case .smart: return AVAssetExportPresetHEVCHighestQuality
        case .highQuality: return AVAssetExportPresetHighestQuality
        case .balanced: return AVAssetExportPreset640x480
        case .spaceSaving: return AVAssetExportPresetMediumQuality
        }
    }

    func estimatedByteCount(metadata: MediaMetadata, duration: Double) -> Int64 {
        guard duration > 0 else { return 0 }
        if self == .smart {
            return SmartCompressionAdvisor.recommendation(for: metadata)
                .estimatedByteCount(duration: duration)
        }

        let pixels = Double(max(1, metadata.width)) * Double(max(1, metadata.height))
        let framesPerSecond = min(max(metadata.frameRate, 1), 60)
        let bitsPerPixel: Double
        let audioBitRate: Double

        switch self {
        case .smart:
            return 0
        case .highQuality:
            bitsPerPixel = 0.11
            audioBitRate = metadata.hasAudio ? 160_000 : 0
        case .balanced:
            bitsPerPixel = 0.065
            audioBitRate = metadata.hasAudio ? 128_000 : 0
        case .spaceSaving:
            bitsPerPixel = 0.038
            audioBitRate = metadata.hasAudio ? 96_000 : 0
        }

        let videoBitRate = pixels * framesPerSecond * bitsPerPixel
        let totalBitRate = videoBitRate + audioBitRate
        return Int64((totalBitRate * duration / 8).rounded())
    }
}

enum ExportState: Equatable {
    case idle
    case preparing
    case exporting
    case completed(URL)
    case cancelled
    case failed(String)
}

@MainActor
final class VideoEditorModel: ObservableObject {
    private struct PlayerSeekRequest {
        let seconds: Double
        let tolerance: CMTime
        let autoplay: Bool
        let completesTimelineScrub: Bool
    }

    private struct DetailThumbnailRequest: Equatable {
        let startTime: Double
        let endTime: Double
        let count: Int
    }

    let player = AVPlayer()

    @Published private(set) var mediaURL: URL?
    @Published private(set) var metadata: MediaMetadata?
    @Published private(set) var isLoading = false
    @Published private(set) var isPlaying = false
    @Published private(set) var isTimelineScrubbing = false
    @Published private(set) var currentTime = 0.0
    @Published private(set) var selectionStart = 0.0
    @Published private(set) var selectionEnd = 0.0
    @Published private(set) var frameTimes: [Double] = []
    @Published private(set) var keyframeTimes: [Double] = []
    @Published private(set) var timelineThumbnails: [TimelineThumbnail] = []
    @Published private(set) var detailTimelineThumbnails: [TimelineThumbnail] = []
    @Published private(set) var isPreparingCompatibilityMedia = false
    @Published private(set) var compatibilityPreparationProgress: Double?
    @Published private(set) var compatibilityPreparationStatus: String?
    @Published private(set) var isIndexingFrames = false
    @Published private(set) var isGeneratingThumbnails = false
    @Published private(set) var isGeneratingDetailThumbnails = false
    @Published private(set) var indexingNotice: String?
    @Published var errorMessage: String?
    @Published var showExportReview = false
    @Published var exportFormat: ExportFormat = .mp4
    @Published var exportCompression: ExportCompression = .smart
    @Published private(set) var exportState: ExportState = .idle
    @Published private(set) var exportProgress = 0.0

    private var frameDuration = 1.0 / 30.0
    private var selectionWasEdited = false
    private var timeObserverToken: Any?
    private var endObserverToken: NSObjectProtocol?
    private var cancellables: Set<AnyCancellable> = []
    private var metadataTask: Task<Void, Never>?
    private var frameIndexTask: Task<Void, Never>?
    private var thumbnailTask: Task<Void, Never>?
    private var detailThumbnailTask: Task<Void, Never>?
    private var exportSession: AVAssetExportSession?
    private var externalExportProcess: Process?
    private var externalExportProgressPipe: Pipe?
    private var externalExportErrorPipe: Pipe?
    private var externalExportProgressParser: FFmpegProgressParser?
    private var externalExportWasCancelled = false
    private var exportProgressTimer: Timer?
    private var securityScopedURL: URL?
    private var workingMediaURL: URL?
    private var compatibilityTemporaryDirectoryURL: URL?
    private(set) var mediaPreparationKind: MediaPreparationKind = .original
    private var didHandleStartupArgument = false
    private var pendingSeekRequest: PlayerSeekRequest?
    private var isSeekInProgress = false
    private var seekGeneration = 0
    private var detailThumbnailGeneration = 0
    private var pendingDetailThumbnailRequest: DetailThumbnailRequest?
    private var activeDetailThumbnailRequest: DetailThumbnailRequest?
    private var completedDetailThumbnailRequest: DetailThumbnailRequest?

    init() {
        player.actionAtItemEnd = .pause
        observePlayer()
    }

    deinit {
        metadataTask?.cancel()
        frameIndexTask?.cancel()
        thumbnailTask?.cancel()
        detailThumbnailTask?.cancel()
        exportSession?.cancelExport()
        if let externalExportProcess, externalExportProcess.isRunning {
            externalExportProcess.terminate()
        }
        exportProgressTimer?.invalidate()
        player.currentItem?.cancelPendingSeeks()
        if let timeObserverToken {
            player.removeTimeObserver(timeObserverToken)
        }
        if let endObserverToken {
            NotificationCenter.default.removeObserver(endObserverToken)
        }
        securityScopedURL?.stopAccessingSecurityScopedResource()
        if let compatibilityTemporaryDirectoryURL {
            try? FileManager.default.removeItem(at: compatibilityTemporaryDirectoryURL)
        }
    }

    var canEdit: Bool {
        mediaURL != nil && workingMediaURL != nil && metadata != nil && !isLoading
    }

    var canExport: Bool {
        canEdit && !isIndexingFrames && !frameTimes.isEmpty && selectionDuration > 0 && !isExporting
    }

    var isExporting: Bool {
        exportState == .preparing || exportState == .exporting
    }

    var duration: Double {
        metadata?.duration ?? 0
    }

    var isAVISource: Bool {
        mediaURL?.pathExtension.caseInsensitiveCompare("avi") == .orderedSame
    }

    var usesCompatibilityPipeline: Bool {
        mediaPreparationKind != .original
    }

    var framesPerSecond: Double {
        metadata?.frameRate ?? 30
    }

    var selectionEndExclusive: Double {
        FrameMath.endExclusive(
            outPoint: selectionEnd,
            duration: duration,
            frameDuration: frameDuration,
            frameTimes: frameTimes
        )
    }

    var selectionDuration: Double {
        max(0, selectionEndExclusive - selectionStart)
    }

    var currentFrameIndex: Int? {
        if let exact = FrameMath.nearestIndex(in: frameTimes, to: currentTime) {
            return exact
        }
        guard duration > 0 else { return nil }
        return max(0, Int((currentTime / max(frameDuration, 0.000_001)).rounded()))
    }

    var currentFrameNumber: Int {
        (currentFrameIndex ?? 0) + 1
    }

    var totalFrameCount: Int {
        if !frameTimes.isEmpty { return frameTimes.count }
        guard duration > 0 else { return 0 }
        return max(1, Int((duration / max(frameDuration, 0.000_001)).rounded()))
    }

    var selectionStartFrameNumber: Int {
        (FrameMath.nearestIndex(in: frameTimes, to: selectionStart) ?? 0) + 1
    }

    var selectionEndFrameNumber: Int {
        if let index = FrameMath.nearestIndex(in: frameTimes, to: selectionEnd) {
            return index + 1
        }
        return max(selectionStartFrameNumber, Int((selectionEnd / max(frameDuration, 0.000_001)).rounded()) + 1)
    }

    var selectionFrameCount: Int {
        max(1, selectionEndFrameNumber - selectionStartFrameNumber + 1)
    }

    var currentTimecode: String {
        FrameMath.timecode(seconds: currentTime, frameRate: framesPerSecond)
    }

    var durationClock: String {
        FrameMath.clock(seconds: duration)
    }

    var selectionStartTimecode: String {
        FrameMath.timecode(seconds: selectionStart, frameRate: framesPerSecond)
    }

    var selectionEndTimecode: String {
        FrameMath.timecode(seconds: selectionEnd, frameRate: framesPerSecond)
    }

    var selectionDurationClock: String {
        FrameMath.clock(seconds: selectionDuration)
    }

    var fileDisplayName: String {
        mediaURL?.lastPathComponent ?? L10n.text("file.no_video")
    }

    var fileDisplayPath: String {
        mediaURL?.standardizedFileURL.path ?? L10n.text("file.no_video")
    }

    var exportDefaultDirectoryURL: URL? {
        mediaURL?.standardizedFileURL.deletingLastPathComponent()
    }

    var exportSuggestedName: String {
        let stem = mediaURL?.deletingPathExtension().lastPathComponent ?? "FrameCut"
        return L10n.format("export.suggested_filename", "\(stem)", "\(exportFormat.fileExtension)")
    }

    var estimatedExportSizeText: String {
        guard let metadata else { return "—" }
        let byteCount = exportCompression.estimatedByteCount(
            metadata: metadata,
            duration: selectionDuration
        )
        return L10n.byteCount(byteCount)
    }

    var smartCompressionRecommendation: SmartCompressionRecommendation? {
        metadata.map(SmartCompressionAdvisor.recommendation(for:))
    }

    var exportCompressionDetail: String {
        if exportCompression == .smart, usesCompatibilityPipeline {
            return L10n.text("compression.compatibility_detail")
        }
        if exportCompression == .smart, let recommendation = smartCompressionRecommendation {
            return recommendation.assessment.detail
        }
        return exportCompression.detail
    }

    var exportCompressionAnalysisText: String {
        guard exportCompression == .smart,
              let recommendation = smartCompressionRecommendation else {
            return L10n.text("compression.size_notice")
        }

        let sourceRate = recommendation.sourceVideoBitRate > 0
            ? recommendation.sourceVideoBitRateText
            : L10n.text("common.unknown")
        if usesCompatibilityPipeline {
            return L10n.format("compression.compatibility_analysis", "\(sourceRate)", "\(recommendation.targetVideoBitRateText)")
        }
        return L10n.format("compression.analysis", "\(recommendation.assessment.title)", "\(sourceRate)", "\(recommendation.targetVideoBitRateText)")
    }

    var estimatedExportReductionText: String? {
        guard exportCompression == .smart,
              let percentage = smartCompressionRecommendation?.reductionPercent else { return nil }
        if percentage < 5 {
            return L10n.text("compression.already_efficient")
        }
        return L10n.format("compression.estimated_reduction", "\(percentage)")
    }

    func openVideoPanel() {
        let panel = NSOpenPanel()
        panel.title = L10n.text("file.open_video")
        panel.message = L10n.text("file.open_panel_message")
        panel.prompt = L10n.text("common.open")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        var supportedTypes: [UTType] = [.movie]
        for fileExtension in MediaCompatibilityPreparer.supportedFileExtensions {
            guard let contentType = UTType(filenameExtension: fileExtension),
                  !supportedTypes.contains(contentType) else { continue }
            supportedTypes.append(contentType)
        }
        panel.allowedContentTypes = supportedTypes

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor [weak self] in
                self?.loadVideo(url)
            }
        }
    }

    func loadStartupArgumentIfNeeded() {
        guard !didHandleStartupArgument else { return }
        didHandleStartupArgument = true
        guard let argument = CommandLine.arguments.dropFirst().first,
              !argument.hasPrefix("-") else { return }
        let url = URL(fileURLWithPath: argument)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        loadVideo(url)
    }

    @discardableResult
    func openDroppedURLs(_ urls: [URL]) -> Bool {
        guard let url = urls.first, url.isFileURL else { return false }
        loadVideo(url)
        return true
    }

    func loadVideo(_ url: URL) {
        guard !isExporting else {
            errorMessage = L10n.text("error.export_in_progress")
            return
        }

        stopSecurityScope()
        if url.startAccessingSecurityScopedResource() {
            securityScopedURL = url
        }

        metadataTask?.cancel()
        frameIndexTask?.cancel()
        thumbnailTask?.cancel()
        detailThumbnailTask?.cancel()
        detailThumbnailGeneration &+= 1
        pendingDetailThumbnailRequest = nil
        activeDetailThumbnailRequest = nil
        completedDetailThumbnailRequest = nil
        exportProgressTimer?.invalidate()
        resetSeekCoordinator()
        player.pause()
        player.replaceCurrentItem(with: nil)
        discardCompatibilityMedia()

        mediaURL = url
        metadata = nil
        currentTime = 0
        selectionStart = 0
        selectionEnd = 0
        frameTimes = []
        keyframeTimes = []
        timelineThumbnails = []
        detailTimelineThumbnails = []
        indexingNotice = nil
        errorMessage = nil
        isLoading = true
        isPreparingCompatibilityMedia = MediaCompatibilityPreparer.requiresPreparation(for: url)
        compatibilityPreparationProgress = nil
        compatibilityPreparationStatus = isPreparingCompatibilityMedia
            ? MediaPreparationStage.checking.statusText
            : nil
        isIndexingFrames = false
        isGeneratingThumbnails = false
        isGeneratingDetailThumbnails = false
        selectionWasEdited = false
        exportState = .idle
        exportProgress = 0

        metadataTask = Task { [weak self] in
            guard let self else { return }
            var preparedSource: PreparedMediaSource?
            var didAdoptPreparedSource = false
            do {
                let prepared = try await MediaCompatibilityPreparer.prepare(url: url) {
                    [weak self] update in
                    Task { @MainActor [weak self] in
                        guard let self, self.mediaURL == url else { return }
                        self.isPreparingCompatibilityMedia = true
                        self.compatibilityPreparationStatus = update.stage.statusText
                        self.compatibilityPreparationProgress = update.progress
                    }
                }
                preparedSource = prepared
                guard !Task.isCancelled, self.mediaURL == url else {
                    prepared.discardTemporaryFiles()
                    return
                }
                self.workingMediaURL = prepared.url
                self.compatibilityTemporaryDirectoryURL = prepared.temporaryDirectoryURL
                self.mediaPreparationKind = prepared.preparationKind
                self.isPreparingCompatibilityMedia = false
                self.compatibilityPreparationProgress = nil
                self.compatibilityPreparationStatus = nil
                didAdoptPreparedSource = true

                let asset = AVURLAsset(url: prepared.url)
                let isPlayable = try await asset.load(.isPlayable)
                guard isPlayable else { throw MediaProcessingError.noVideoTrack }

                async let assetDurationLoad = asset.load(.duration)
                async let videoTracksLoad = asset.loadTracks(withMediaType: .video)
                async let audioTracksLoad = asset.loadTracks(withMediaType: .audio)
                let (assetDuration, videoTracks, audioTracks) = try await (
                    assetDurationLoad,
                    videoTracksLoad,
                    audioTracksLoad
                )
                guard let videoTrack = videoTracks.first else {
                    throw MediaProcessingError.noVideoTrack
                }

                async let naturalSizeLoad = videoTrack.load(.naturalSize)
                async let transformLoad = videoTrack.load(.preferredTransform)
                async let nominalFrameRateLoad = videoTrack.load(.nominalFrameRate)
                async let minimumFrameDurationLoad = videoTrack.load(.minFrameDuration)
                async let videoDescriptionsLoad = videoTrack.load(.formatDescriptions)
                async let videoBitRateLoad = videoTrack.load(.estimatedDataRate)
                let (
                    naturalSize,
                    transform,
                    nominalFrameRateValue,
                    minimumFrameDuration,
                    videoDescriptions,
                    videoBitRateValue
                ) = try await (
                    naturalSizeLoad,
                    transformLoad,
                    nominalFrameRateLoad,
                    minimumFrameDurationLoad,
                    videoDescriptionsLoad,
                    videoBitRateLoad
                )

                var audioCodec: String?
                var audioSampleRate = 0.0
                var audioChannelCount = 0
                var audioBitRate = 0.0
                if let audioTrack = audioTracks.first {
                    async let audioDescriptionsLoad = audioTrack.load(.formatDescriptions)
                    async let audioBitRateLoad = audioTrack.load(.estimatedDataRate)
                    let (audioDescriptions, audioBitRateValue) = try await (
                        audioDescriptionsLoad,
                        audioBitRateLoad
                    )
                    audioCodec = MediaFormatInfo.codecName(from: audioDescriptions.first)
                    let audioProperties = MediaFormatInfo.audioProperties(
                        from: audioDescriptions.first
                    )
                    audioSampleRate = audioProperties.sampleRate
                    audioChannelCount = audioProperties.channelCount
                    audioBitRate = Double(audioBitRateValue)
                }

                guard !Task.isCancelled,
                      self.mediaURL == url,
                      self.workingMediaURL == prepared.url else { return }
                let preparedDuration = assetDuration.seconds.isFinite ? assetDuration.seconds : 0
                let durationSeconds = max(
                    0,
                    (prepared.sourceInfo?.duration ?? 0) > 0
                        ? prepared.sourceInfo?.duration ?? 0
                        : preparedDuration
                )
                guard durationSeconds > 0 else { throw MediaProcessingError.noVideoTrack }

                let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(transform)
                let preparedWidth = Int(abs(transformedRect.width).rounded())
                let preparedHeight = Int(abs(transformedRect.height).rounded())
                let width = (prepared.sourceInfo?.width ?? 0) > 0
                    ? prepared.sourceInfo?.width ?? preparedWidth
                    : preparedWidth
                let height = (prepared.sourceInfo?.height ?? 0) > 0
                    ? prepared.sourceInfo?.height ?? preparedHeight
                    : preparedHeight
                let loadedFrameDuration = minimumFrameDuration.seconds
                let fallbackRate = loadedFrameDuration.isFinite && loadedFrameDuration > 0
                    ? 1.0 / loadedFrameDuration
                    : 30.0
                let nominalFrameRate = Double(nominalFrameRateValue)
                let preparedFrameRate = nominalFrameRate > 0 ? nominalFrameRate : fallbackRate
                let frameRate = (prepared.sourceInfo?.frameRate ?? 0) > 0
                    ? prepared.sourceInfo?.frameRate ?? preparedFrameRate
                    : preparedFrameRate
                let fileAttributes = try? FileManager.default.attributesOfItem(atPath: url.path)
                let attributeFileSize = (fileAttributes?[.size] as? NSNumber)?.int64Value ?? 0
                let fileSize = (prepared.sourceInfo?.fileSize ?? 0) > 0
                    ? prepared.sourceInfo?.fileSize ?? attributeFileSize
                    : attributeFileSize

                self.frameDuration = loadedFrameDuration.isFinite && loadedFrameDuration > 0
                    ? loadedFrameDuration
                    : 1.0 / max(frameRate, 1)
                self.metadata = MediaMetadata(
                    duration: durationSeconds,
                    width: width,
                    height: height,
                    frameRate: frameRate,
                    hasAudio: prepared.sourceInfo?.hasAudio ?? !audioTracks.isEmpty,
                    containerFormat: MediaFormatInfo.containerName(for: url),
                    fileSize: fileSize,
                    videoCodec: prepared.sourceInfo?.videoCodec
                        ?? MediaFormatInfo.codecName(from: videoDescriptions.first),
                    videoBitRate: (prepared.sourceInfo?.videoBitRate ?? 0) > 0
                        ? prepared.sourceInfo?.videoBitRate ?? Double(videoBitRateValue)
                        : Double(videoBitRateValue),
                    audioCodec: prepared.sourceInfo?.audioCodec ?? audioCodec,
                    audioSampleRate: (prepared.sourceInfo?.audioSampleRate ?? 0) > 0
                        ? prepared.sourceInfo?.audioSampleRate ?? audioSampleRate
                        : audioSampleRate,
                    audioChannelCount: (prepared.sourceInfo?.audioChannelCount ?? 0) > 0
                        ? prepared.sourceInfo?.audioChannelCount ?? audioChannelCount
                        : audioChannelCount,
                    audioBitRate: (prepared.sourceInfo?.audioBitRate ?? 0) > 0
                        ? prepared.sourceInfo?.audioBitRate ?? audioBitRate
                        : audioBitRate
                )
                self.selectionEnd = max(0, durationSeconds - self.frameDuration)
                self.player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
                self.isLoading = false
                self.startFrameIndexing(for: prepared.url)
                self.startThumbnailGeneration(for: prepared.url, duration: durationSeconds)
            } catch is CancellationError {
                if !didAdoptPreparedSource {
                    preparedSource?.discardTemporaryFiles()
                }
                return
            } catch {
                guard self.mediaURL == url else { return }
                if didAdoptPreparedSource {
                    self.discardCompatibilityMedia()
                } else {
                    preparedSource?.discardTemporaryFiles()
                }
                self.isPreparingCompatibilityMedia = false
                self.compatibilityPreparationProgress = nil
                self.compatibilityPreparationStatus = nil
                self.isLoading = false
                self.metadata = nil
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func togglePlayback() {
        guard canEdit else { return }
        if isPlaying {
            player.pause()
            return
        }

        let epsilon = max(0.002, frameDuration * 0.15)
        if currentTime < selectionStart - epsilon || currentTime >= selectionEndExclusive - epsilon {
            seek(to: selectionStart, autoplay: true)
        } else {
            player.play()
        }
    }

    func stepFrame(_ delta: Int) {
        guard canEdit, delta != 0 else { return }
        player.pause()

        if let currentIndex = FrameMath.nearestIndex(in: frameTimes, to: currentTime), !frameTimes.isEmpty {
            let targetIndex = min(max(0, currentIndex + delta), frameTimes.count - 1)
            seek(to: frameTimes[targetIndex])
            return
        }

        player.currentItem?.step(byCount: delta)
    }

    func jumpToKeyframe(_ direction: Int) {
        guard canEdit, direction != 0 else { return }
        player.pause()

        if direction < 0,
           let index = FrameMath.previousIndex(in: keyframeTimes, before: currentTime) {
            seek(to: keyframeTimes[index])
            return
        }
        if direction > 0,
           let index = FrameMath.nextIndex(in: keyframeTimes, after: currentTime) {
            seek(to: keyframeTimes[index])
            return
        }

        if isIndexingFrames {
            seek(to: currentTime + (direction < 0 ? -1 : 1))
        }
    }

    func seek(to seconds: Double, autoplay: Bool = false) {
        guard canEdit else { return }
        let clamped = min(max(0, seconds), duration)
        player.pause()
        isTimelineScrubbing = false
        currentTime = clamped
        enqueuePlayerSeek(
            to: clamped,
            tolerance: .zero,
            autoplay: autoplay,
            completesTimelineScrub: false
        )
    }

    func beginTimelineScrubbing() {
        guard canEdit else { return }
        player.pause()
        isTimelineScrubbing = true
    }

    func scrubTimeline(to seconds: Double) {
        guard canEdit else { return }
        if !isTimelineScrubbing {
            beginTimelineScrubbing()
        }

        let aligned = alignedFrameTime(for: min(max(0, seconds), duration))
        guard abs(aligned - currentTime) > max(0.000_5, frameDuration * 0.05) else {
            return
        }
        currentTime = aligned
        enqueuePlayerSeek(
            to: aligned,
            tolerance: timelineScrubTolerance,
            autoplay: false,
            completesTimelineScrub: false
        )
    }

    func endTimelineScrubbing(at seconds: Double) {
        guard canEdit else {
            isTimelineScrubbing = false
            return
        }
        if !isTimelineScrubbing {
            beginTimelineScrubbing()
        }

        let aligned = alignedFrameTime(for: min(max(0, seconds), duration))
        currentTime = aligned
        enqueuePlayerSeek(
            to: aligned,
            tolerance: .zero,
            autoplay: false,
            completesTimelineScrub: true
        )
    }

    func jumpToInPoint() {
        seek(to: selectionStart)
    }

    func jumpToOutPoint() {
        seek(to: selectionEnd)
    }

    func setInPointAtCurrentFrame() {
        updateInPoint(to: alignedFrameTime(for: currentTime), shouldSeek: false)
    }

    func setOutPointAtCurrentFrame() {
        updateOutPoint(to: alignedFrameTime(for: currentTime), shouldSeek: false)
    }

    func updateInPoint(to seconds: Double, shouldSeek: Bool = true) {
        guard canEdit else { return }
        player.pause()
        selectionWasEdited = true
        let aligned = alignedFrameTime(for: min(max(0, seconds), duration))
        selectionStart = min(aligned, selectionEnd)
        if shouldSeek { seek(to: selectionStart) }
    }

    func updateOutPoint(to seconds: Double, shouldSeek: Bool = true) {
        guard canEdit else { return }
        player.pause()
        selectionWasEdited = true
        let aligned = alignedFrameTime(for: min(max(0, seconds), duration))
        selectionEnd = max(aligned, selectionStart)
        if shouldSeek { seek(to: selectionEnd) }
    }

    func requestExportReview() {
        guard canExport else { return }
        player.pause()
        showExportReview = true
    }

    func chooseExportDestination() {
        guard canExport else { return }
        showExportReview = false

        let selectedFormat = exportFormat
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let panel = NSSavePanel()
            panel.title = L10n.text("export.selected_clip")
            panel.message = L10n.format("export.save_panel_message", "\(self.exportCompression.title)")
            panel.prompt = L10n.text("export.start")
            panel.canCreateDirectories = true
            panel.isExtensionHidden = false
            panel.allowsOtherFileTypes = false
            panel.allowedContentTypes = [selectedFormat.contentType]
            panel.nameFieldStringValue = self.exportSuggestedName
            panel.directoryURL = self.exportDefaultDirectoryURL

            panel.begin { [weak self] response in
                guard response == .OK, let outputURL = panel.url else { return }
                Task { @MainActor [weak self] in
                    self?.exportSelection(to: outputURL)
                }
            }
        }
    }

    func cancelExport() {
        guard isExporting else { return }
        externalExportWasCancelled = true
        exportSession?.cancelExport()
        if let externalExportProcess, externalExportProcess.isRunning {
            externalExportProcess.terminate()
        }
        exportProgressTimer?.invalidate()
        exportProgressTimer = nil
        exportProgress = 0
        exportState = .cancelled
    }

    func revealLastExport() {
        guard case let .completed(url) = exportState else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func dismissExportStatus() {
        guard !isExporting else { return }
        exportState = .idle
        exportProgress = 0
    }

    func clearError() {
        errorMessage = nil
    }

    private func observePlayer() {
        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1.0 / 60.0, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                self?.handlePeriodicTime(time)
            }
        }

        player.publisher(for: \.timeControlStatus)
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                self?.isPlaying = status == .playing
            }
            .store(in: &cancellables)

        endObserverToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let endedItem = notification.object as? AVPlayerItem
            Task { @MainActor [weak self, weak endedItem] in
                self?.handlePlaybackEnded(endedItem)
            }
        }
    }

    private func handlePeriodicTime(_ time: CMTime) {
        guard !isTimelineScrubbing, !isSeekInProgress else { return }
        let seconds = time.seconds
        guard seconds.isFinite else { return }
        currentTime = min(max(0, seconds), duration)

        let threshold = max(0.003, frameDuration * 0.2)
        if isPlaying && currentTime >= selectionEndExclusive - threshold {
            player.pause()
            seek(to: selectionEnd)
        }
    }

    private func handlePlaybackEnded(_ endedItem: AVPlayerItem?) {
        guard let endedItem, endedItem === player.currentItem else { return }
        player.pause()
        currentTime = selectionEnd
    }

    private func alignedFrameTime(for seconds: Double) -> Double {
        if let index = FrameMath.nearestIndex(in: frameTimes, to: seconds) {
            return frameTimes[index]
        }
        let approximate = (seconds / max(frameDuration, 0.000_001)).rounded() * frameDuration
        return min(max(0, approximate), duration)
    }

    private var timelineScrubTolerance: CMTime {
        let seconds = max(0.002, min(frameDuration * 0.5, 0.05))
        return CMTime(seconds: seconds, preferredTimescale: 60_000)
    }

    private func enqueuePlayerSeek(
        to seconds: Double,
        tolerance: CMTime,
        autoplay: Bool,
        completesTimelineScrub: Bool
    ) {
        let shouldCancelStaleSeek = isTimelineScrubbing && isSeekInProgress
        pendingSeekRequest = PlayerSeekRequest(
            seconds: seconds,
            tolerance: tolerance,
            autoplay: autoplay,
            completesTimelineScrub: completesTimelineScrub
        )
        if shouldCancelStaleSeek {
            player.currentItem?.cancelPendingSeeks()
        }
        performNextPlayerSeekIfNeeded()
    }

    private func performNextPlayerSeekIfNeeded() {
        guard !isSeekInProgress, let request = pendingSeekRequest else { return }
        pendingSeekRequest = nil
        isSeekInProgress = true

        let generation = seekGeneration
        let target = CMTime(seconds: request.seconds, preferredTimescale: 60_000)
        player.seek(
            to: target,
            toleranceBefore: request.tolerance,
            toleranceAfter: request.tolerance
        ) { [weak self] finished in
            DispatchQueue.main.async {
                guard let self, generation == self.seekGeneration else { return }
                self.isSeekInProgress = false

                let hasNewerRequest = self.pendingSeekRequest != nil
                if !hasNewerRequest {
                    if finished {
                        self.currentTime = request.seconds
                    }
                    if request.completesTimelineScrub {
                        self.isTimelineScrubbing = false
                    }
                    if finished, request.autoplay {
                        self.player.play()
                    }
                }

                self.performNextPlayerSeekIfNeeded()
            }
        }
    }

    private func resetSeekCoordinator() {
        seekGeneration &+= 1
        player.currentItem?.cancelPendingSeeks()
        pendingSeekRequest = nil
        isSeekInProgress = false
        isTimelineScrubbing = false
    }

    private func startFrameIndexing(for url: URL) {
        frameIndexTask?.cancel()
        isIndexingFrames = true
        indexingNotice = nil

        frameIndexTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { () -> Result<FrameIndexResult, Error> in
                do {
                    return .success(try await FrameIndexBuilder.build(url: url))
                } catch {
                    return .failure(error)
                }
            }.value

            guard let self, !Task.isCancelled, self.workingMediaURL == url else { return }
            self.isIndexingFrames = false

            switch result {
            case let .success(index):
                guard !index.frameTimes.isEmpty else {
                    self.indexingNotice = L10n.text("error.frame_times_unavailable")
                    return
                }
                self.frameTimes = index.frameTimes
                self.keyframeTimes = index.keyframeTimes
                if self.selectionWasEdited {
                    self.selectionStart = self.alignedFrameTime(for: self.selectionStart)
                    self.selectionEnd = max(
                        self.selectionStart,
                        self.alignedFrameTime(for: self.selectionEnd)
                    )
                } else {
                    self.selectionStart = index.frameTimes.first ?? 0
                    self.selectionEnd = index.frameTimes.last ?? max(0, self.duration - self.frameDuration)
                }
            case let .failure(error):
                if error is CancellationError { return }
                self.indexingNotice = L10n.format("error.frame_index_detail", "\(error.localizedDescription)")
            }
        }
    }

    func requestDetailTimelineThumbnails(
        startTime: Double,
        endTime: Double,
        count: Int = 12
    ) {
        guard let url = workingMediaURL, duration > 0, count > 0 else {
            clearDetailTimelineThumbnails()
            return
        }

        let lowerBound = min(max(0, startTime), duration)
        let upperBound = min(max(lowerBound, endTime), duration)
        guard upperBound - lowerBound > 0.001 else {
            clearDetailTimelineThumbnails()
            return
        }

        let request = DetailThumbnailRequest(
            startTime: lowerBound,
            endTime: upperBound,
            count: count
        )
        if completedDetailThumbnailRequest == request,
           !detailTimelineThumbnails.isEmpty {
            return
        }
        if activeDetailThumbnailRequest == request, isGeneratingDetailThumbnails {
            return
        }
        if isGeneratingThumbnails {
            pendingDetailThumbnailRequest = request
            return
        }

        startDetailThumbnailGeneration(for: url, request: request)
    }

    private func startDetailThumbnailGeneration(
        for url: URL,
        request: DetailThumbnailRequest
    ) {
        detailThumbnailTask?.cancel()
        detailThumbnailGeneration &+= 1
        let generation = detailThumbnailGeneration
        activeDetailThumbnailRequest = request
        isGeneratingDetailThumbnails = true

        detailThumbnailTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled else { return }

            let result: Result<[GeneratedThumbnail], Error>
            do {
                result = .success(try await TimelineThumbnailGenerator.generate(
                    url: url,
                    startTime: request.startTime,
                    endTime: request.endTime,
                    count: request.count
                ))
            } catch {
                result = .failure(error)
            }

            guard let self,
                  !Task.isCancelled,
                  self.workingMediaURL == url,
                  self.detailThumbnailGeneration == generation else { return }

            self.isGeneratingDetailThumbnails = false
            self.activeDetailThumbnailRequest = nil
            if case let .success(generated) = result {
                self.detailTimelineThumbnails = generated.compactMap { item in
                    guard let image = NSImage(data: item.data) else { return nil }
                    return TimelineThumbnail(id: item.index, time: item.time, image: image)
                }
                self.completedDetailThumbnailRequest = request
            }
        }
    }

    func clearDetailTimelineThumbnails() {
        detailThumbnailTask?.cancel()
        detailThumbnailTask = nil
        detailThumbnailGeneration &+= 1
        pendingDetailThumbnailRequest = nil
        activeDetailThumbnailRequest = nil
        completedDetailThumbnailRequest = nil
        detailTimelineThumbnails = []
        isGeneratingDetailThumbnails = false
    }

    private func startThumbnailGeneration(for url: URL, duration: Double) {
        thumbnailTask?.cancel()
        isGeneratingThumbnails = true

        thumbnailTask = Task { [weak self] in
            let result: Result<[GeneratedThumbnail], Error>
            do {
                result = .success(try await TimelineThumbnailGenerator.generate(
                    url: url,
                    duration: duration
                ))
            } catch {
                result = .failure(error)
            }

            guard let self, !Task.isCancelled, self.workingMediaURL == url else { return }
            self.isGeneratingThumbnails = false
            if case let .success(generated) = result {
                self.timelineThumbnails = generated.compactMap { item in
                    guard let image = NSImage(data: item.data) else { return nil }
                    return TimelineThumbnail(id: item.index, time: item.time, image: image)
                }
            }

            if let pendingRequest = self.pendingDetailThumbnailRequest {
                self.pendingDetailThumbnailRequest = nil
                self.startDetailThumbnailGeneration(for: url, request: pendingRequest)
            }
        }
    }

    func exportSelection(to outputURL: URL) {
        guard canExport,
              let sourceURL = mediaURL,
              let processingURL = workingMediaURL else { return }
        do {
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try FileManager.default.removeItem(at: outputURL)
            }

            if exportCompression == .smart, usesCompatibilityPipeline {
                try startContentAdaptiveFFmpegExport(
                    sourceURL: sourceURL,
                    outputURL: outputURL
                )
                return
            }

            let asset = AVURLAsset(url: processingURL)
            guard let session = AVAssetExportSession(
                asset: asset,
                presetName: exportCompression.avPresetName
            ) else {
                throw MediaProcessingError.cannotCreateExportSession
            }
            guard session.supportedFileTypes.contains(exportFormat.avFileType) else {
                throw MediaProcessingError.unsupportedExportFormat
            }

            let start = CMTime(seconds: selectionStart, preferredTimescale: 60_000)
            let end = CMTime(seconds: selectionEndExclusive, preferredTimescale: 60_000)
            guard CMTimeCompare(end, start) > 0 else {
                throw MediaProcessingError.invalidSelection
            }

            session.outputURL = outputURL
            session.outputFileType = exportFormat.avFileType
            session.timeRange = CMTimeRange(start: start, end: end)
            session.shouldOptimizeForNetworkUse = true
            if exportCompression == .smart, let metadata {
                let recommendation = SmartCompressionAdvisor.recommendation(for: metadata)
                session.fileLengthLimit = max(
                    256_000,
                    recommendation.estimatedByteCount(duration: selectionDuration)
                )
                session.canPerformMultiplePassesOverSourceMediaData = true
            }
            exportSession = session
            exportProgress = 0
            exportState = .preparing

            exportProgressTimer?.invalidate()
            exportProgressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.pollExportProgress()
                }
            }

            session.exportAsynchronously { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, let session = self.exportSession else { return }
                    self.finishExport(session: session, outputURL: outputURL)
                }
            }
        } catch {
            exportState = .failed(error.localizedDescription)
            exportProgress = 0
        }
    }

    private func startContentAdaptiveFFmpegExport(
        sourceURL: URL,
        outputURL: URL
    ) throws {
        let duration = selectionDuration
        guard duration > 0 else { throw MediaProcessingError.invalidSelection }

        let audioKilobitsPerSecond: Int
        if metadata?.hasAudio == true {
            let sourceAudioBitRate = metadata?.audioBitRate ?? 0
            audioKilobitsPerSecond = sourceAudioBitRate > 0
                ? min(160, max(96, Int((sourceAudioBitRate / 1_000).rounded())))
                : 128
        } else {
            audioKilobitsPerSecond = 128
        }

        let process = try FFmpegTool.makeProcess(arguments: [
            "-nostdin",
            "-y",
            "-hide_banner",
            "-loglevel", "error",
            "-fflags", "+genpts",
            "-ss", FFmpegTool.secondsArgument(selectionStart),
            "-i", sourceURL.path,
            "-t", FFmpegTool.secondsArgument(duration),
            "-map", "0:v:0",
            "-map", "0:a:0?",
            "-map_metadata", "0",
            "-c:v", "libx265",
            "-preset", "medium",
            "-crf", "24",
            "-x265-params", "log-level=error",
            "-tag:v", "hvc1",
            "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2",
            "-pix_fmt", "yuv420p",
            "-c:a", "aac",
            "-b:a", "\(audioKilobitsPerSecond)k",
            "-ac", "2",
            "-avoid_negative_ts", "make_zero",
            "-movflags", "+faststart",
            "-progress", "pipe:1",
            "-stats_period", "0.5",
            "-nostats",
            outputURL.path
        ])
        let progressPipe = Pipe()
        let errorPipe = Pipe()
        let progressParser = FFmpegProgressParser(duration: duration) { [weak self] progress in
            Task { @MainActor [weak self] in
                guard let self, self.externalExportProcess === process else { return }
                self.exportProgress = progress
                self.exportState = .exporting
            }
        }

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
        process.terminationHandler = { [weak self] completedProcess in
            Task { @MainActor [weak self] in
                self?.finishContentAdaptiveFFmpegExport(
                    process: completedProcess,
                    outputURL: outputURL,
                    progressParser: progressParser
                )
            }
        }

        externalExportWasCancelled = false
        externalExportProcess = process
        externalExportProgressPipe = progressPipe
        externalExportErrorPipe = errorPipe
        externalExportProgressParser = progressParser
        exportProgress = 0
        exportState = .preparing
        do {
            try process.run()
            exportState = .exporting
        } catch {
            clearExternalExportResources()
            throw error
        }
    }

    private func finishContentAdaptiveFFmpegExport(
        process: Process,
        outputURL: URL,
        progressParser: FFmpegProgressParser
    ) {
        guard externalExportProcess === process else { return }
        let wasCancelled = externalExportWasCancelled
        let terminationStatus = process.terminationStatus
        let errorMessage = progressParser.errorMessage
        clearExternalExportResources()

        if wasCancelled {
            try? FileManager.default.removeItem(at: outputURL)
            exportProgress = 0
            exportState = .cancelled
            return
        }

        let outputSize = ((try? FileManager.default.attributesOfItem(
            atPath: outputURL.path
        )[.size]) as? NSNumber)?.int64Value ?? 0
        if terminationStatus == 0, outputSize > 0 {
            exportProgress = 1
            exportState = .completed(outputURL)
        } else {
            try? FileManager.default.removeItem(at: outputURL)
            exportProgress = 0
            exportState = .failed(
                errorMessage.isEmpty
                    ? L10n.text("error.adaptive_compression")
                    : errorMessage
            )
        }
    }

    private func clearExternalExportResources() {
        externalExportProcess?.terminationHandler = nil
        externalExportProgressPipe?.fileHandleForReading.readabilityHandler = nil
        externalExportErrorPipe?.fileHandleForReading.readabilityHandler = nil
        externalExportProcess = nil
        externalExportProgressPipe = nil
        externalExportErrorPipe = nil
        externalExportProgressParser = nil
        externalExportWasCancelled = false
    }

    private func pollExportProgress() {
        guard let exportSession else { return }
        exportProgress = Double(exportSession.progress)
        if exportSession.status == .exporting {
            exportState = .exporting
        }
    }

    private func finishExport(session: AVAssetExportSession, outputURL: URL) {
        exportProgressTimer?.invalidate()
        exportProgressTimer = nil
        exportSession = nil

        switch session.status {
        case .completed:
            exportProgress = 1
            exportState = .completed(outputURL)
        case .cancelled:
            exportProgress = 0
            exportState = .cancelled
        case .failed:
            exportProgress = 0
            exportState = .failed(session.error?.localizedDescription ?? L10n.text("error.export_retry"))
        default:
            exportProgress = 0
            exportState = .failed(session.error?.localizedDescription ?? L10n.text("error.export_incomplete"))
        }
    }

    private func discardCompatibilityMedia() {
        if let compatibilityTemporaryDirectoryURL {
            try? FileManager.default.removeItem(at: compatibilityTemporaryDirectoryURL)
        }
        compatibilityTemporaryDirectoryURL = nil
        workingMediaURL = nil
        mediaPreparationKind = .original
        compatibilityPreparationProgress = nil
        compatibilityPreparationStatus = nil
    }

    private func stopSecurityScope() {
        securityScopedURL?.stopAccessingSecurityScopedResource()
        securityScopedURL = nil
    }
}
