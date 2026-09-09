import AVFoundation
import XCTest
@testable import FrameCut

final class MediaUtilitiesTests: XCTestCase {
    func testRuntimeDependencyReportRequiresEveryMediaCapability() {
        let executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        let ready = RuntimeDependencyReport(
            ffmpegURL: executableURL,
            ffprobeURL: executableURL,
            ffmpegVersion: "ffmpeg version 8.1.1",
            ffprobeVersion: "ffprobe version 8.1.1",
            hasH264PreviewEncoder: true,
            hasHEVCSmartEncoder: true,
            homebrewURL: URL(fileURLWithPath: "/opt/homebrew/bin/brew")
        )
        let missingSmartEncoder = RuntimeDependencyReport(
            ffmpegURL: executableURL,
            ffprobeURL: executableURL,
            ffmpegVersion: "ffmpeg version 8.1.1",
            ffprobeVersion: "ffprobe version 8.1.1",
            hasH264PreviewEncoder: true,
            hasHEVCSmartEncoder: false,
            homebrewURL: URL(fileURLWithPath: "/opt/homebrew/bin/brew")
        )

        XCTAssertTrue(ready.isReady)
        XCTAssertEqual(ready.missingComponentCount, 0)
        XCTAssertFalse(missingSmartEncoder.isReady)
        XCTAssertEqual(missingSmartEncoder.missingComponentCount, 1)
    }

    func testRuntimeDependencyReportCountsMissingExecutablesAndEncoders() {
        let missing = RuntimeDependencyReport(
            ffmpegURL: nil,
            ffprobeURL: nil,
            ffmpegVersion: nil,
            ffprobeVersion: nil,
            hasH264PreviewEncoder: false,
            hasHEVCSmartEncoder: false,
            homebrewURL: nil
        )

        XCTAssertFalse(missing.isReady)
        XCTAssertEqual(missing.missingComponentCount, 4)
        XCTAssertTrue(
            SetupAssistantModel.homebrewInstallCommand.contains(
                "raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
            )
        )
    }

    func testRuntimeDependencyProbeAgainstOptionalLocalFFmpeg() async throws {
        guard FFmpegTool.executableURL != nil, FFmpegTool.probeExecutableURL != nil else {
            throw XCTSkip("Local FFmpeg is not installed.")
        }

        let report = await RuntimeDependencyProbe.inspect()

        XCTAssertTrue(report.hasUsableFFmpeg)
        XCTAssertTrue(report.hasUsableFFprobe)
        XCTAssertTrue(report.hasH264PreviewEncoder)
        XCTAssertTrue(report.hasHEVCSmartEncoder)
        XCTAssertTrue(report.isReady)
    }

    @MainActor
    func testLaunchCheckSkipsInspectionAfterSuccessfulMarker() async {
        let (defaults, suiteName) = makeIsolatedUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: SetupAssistantModel.completionKey)
        var inspectionCount = 0
        let model = SetupAssistantModel(
            userDefaults: defaults,
            dependencyInspector: {
                inspectionCount += 1
                return self.runtimeReport(isReady: true)
            }
        )

        await model.runLaunchCheck()

        XCTAssertEqual(inspectionCount, 0)
        XCTAssertFalse(model.isPresented)
        XCTAssertTrue(model.hasCompletedSelfCheck)
    }

    @MainActor
    func testSuccessfulFirstLaunchCheckPersistsMarkerWithoutShowingInstaller() async {
        let (defaults, suiteName) = makeIsolatedUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = SetupAssistantModel(
            userDefaults: defaults,
            dependencyInspector: { self.runtimeReport(isReady: true) }
        )

        await model.runLaunchCheck()

        XCTAssertEqual(model.phase, .ready)
        XCTAssertFalse(model.isPresented)
        XCTAssertTrue(model.hasCompletedSelfCheck)
        XCTAssertNotNil(
            defaults.object(forKey: "FrameCut.setupAssistant.completedAt.v1")
        )
    }

    @MainActor
    func testMissingHomebrewKeepsMarkerUnsetAndShowsInstallationGuide() async {
        let (defaults, suiteName) = makeIsolatedUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = SetupAssistantModel(
            userDefaults: defaults,
            dependencyInspector: {
                self.runtimeReport(isReady: false, hasHomebrew: false)
            }
        )

        await model.runLaunchCheck()

        XCTAssertEqual(model.phase, .requirements)
        XCTAssertTrue(model.isPresented)
        XCTAssertNil(model.report?.homebrewURL)
        XCTAssertFalse(model.hasCompletedSelfCheck)
    }

    @MainActor
    func testFailedHomebrewInstallationLeavesSelfCheckPending() async throws {
        let (defaults, suiteName) = makeIsolatedUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = SetupAssistantModel(
            userDefaults: defaults,
            dependencyInspector: { self.runtimeReport(isReady: false) },
            componentInstaller: { _ in
                HomebrewInstallResult(terminationStatus: 1, output: "brew failed")
            }
        )

        await model.runLaunchCheck()
        model.installRequiredComponents()
        try await waitUntil(timeout: 1) { model.phase == .failed }

        XCTAssertFalse(model.hasCompletedSelfCheck)
        XCTAssertEqual(model.installationLog, "brew failed")
    }

    @MainActor
    func testSuccessfulHomebrewInstallationRechecksAndPersistsMarker() async throws {
        let (defaults, suiteName) = makeIsolatedUserDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var inspectionCount = 0
        let model = SetupAssistantModel(
            userDefaults: defaults,
            dependencyInspector: {
                inspectionCount += 1
                return self.runtimeReport(isReady: inspectionCount > 1)
            },
            componentInstaller: { _ in
                HomebrewInstallResult(terminationStatus: 0, output: "installed")
            }
        )

        await model.runLaunchCheck()
        model.installRequiredComponents()
        try await waitUntil(timeout: 1) { model.phase == .ready }

        XCTAssertEqual(inspectionCount, 2)
        XCTAssertTrue(model.hasCompletedSelfCheck)
        XCTAssertEqual(model.installationLog, "installed")
    }

    func testFrameIndexerAgainstOptionalQAVideo() async throws {
        guard let path = ProcessInfo.processInfo.environment["FRAMECUT_QA_VIDEO"] else {
            throw XCTSkip("Set FRAMECUT_QA_VIDEO to run the AVFoundation integration check.")
        }

        let result = try await FrameIndexBuilder.build(url: URL(fileURLWithPath: path))

        XCTAssertEqual(result.frameTimes.count, 360)
        XCTAssertEqual(result.keyframeTimes.count, 6)
        XCTAssertEqual(result.frameTimes.first ?? -1, 0, accuracy: 0.000_001)
        XCTAssertEqual(result.frameTimes.last ?? -1, 359.0 / 30.0, accuracy: 0.000_1)

        let detailThumbnails = try await TimelineThumbnailGenerator.generate(
            url: URL(fileURLWithPath: path),
            startTime: 2.0,
            endTime: 4.0,
            count: 4
        )
        XCTAssertEqual(detailThumbnails.count, 4)
        XCTAssertTrue(detailThumbnails.allSatisfy { (2.0...4.0).contains($0.time) })
    }

    @MainActor
    func testModelLoadsSelectsAndExportsOptionalQAVideo() async throws {
        guard let path = ProcessInfo.processInfo.environment["FRAMECUT_QA_VIDEO"] else {
            throw XCTSkip("Set FRAMECUT_QA_VIDEO to run the export integration check.")
        }

        var outputURLs: [URL] = []
        defer {
            for outputURL in outputURLs {
                try? FileManager.default.removeItem(at: outputURL)
            }
        }

        let model = VideoEditorModel()
        model.loadVideo(URL(fileURLWithPath: path))
        try await waitUntil(timeout: 10) {
            model.canExport || model.errorMessage != nil || model.indexingNotice != nil
        }

        XCTAssertNil(model.errorMessage)
        XCTAssertNil(model.indexingNotice)
        XCTAssertEqual(model.totalFrameCount, 360)
        XCTAssertEqual(model.keyframeTimes.count, 6)

        model.beginTimelineScrubbing()
        for frame in stride(from: 0, through: 300, by: 3) {
            model.scrubTimeline(to: Double(frame) / 30.0)
        }
        model.endTimelineScrubbing(at: 4.0)
        try await waitUntil(timeout: 5) {
            let playerTime = model.player.currentTime().seconds
            return playerTime.isFinite && abs(playerTime - 4.0) < 0.02
        }
        XCTAssertEqual(model.currentTime, 4.0, accuracy: 0.000_1)
        XCTAssertEqual(model.currentFrameNumber, 121)

        model.updateInPoint(to: 2.0, shouldSeek: false)
        model.updateOutPoint(to: 4.0, shouldSeek: false)
        XCTAssertEqual(model.selectionStartFrameNumber, 61)
        XCTAssertEqual(model.selectionEndFrameNumber, 121)
        XCTAssertEqual(model.selectionFrameCount, 61)
        XCTAssertEqual(model.selectionDuration, 61.0 / 30.0, accuracy: 0.000_1)

        var byteCounts: [ExportCompression: Int64] = [:]
        let qaAsset = AVURLAsset(url: URL(fileURLWithPath: path))
        for compression in ExportCompression.allCases {
            let compatibilitySession = AVAssetExportSession(
                asset: qaAsset,
                presetName: compression.avPresetName
            )
            XCTAssertNotNil(compatibilitySession, compression.title)
            XCTAssertTrue(
                compatibilitySession?.supportedFileTypes.contains(.mp4) == true,
                "\(compression.title) should support MP4"
            )
            XCTAssertTrue(
                compatibilitySession?.supportedFileTypes.contains(.mov) == true,
                "\(compression.title) should support MOV"
            )

            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("FrameCut-QA-\(compression.rawValue)-\(UUID().uuidString)")
                .appendingPathExtension("mp4")
            outputURLs.append(outputURL)
            model.exportCompression = compression
            model.exportSelection(to: outputURL)
            try await waitUntil(timeout: 20) {
                switch model.exportState {
                case .completed, .failed, .cancelled: return true
                default: return false
                }
            }

            guard case .completed = model.exportState else {
                return XCTFail("\(compression.title) export state: \(model.exportState)")
            }
            XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))

            let exportedIndex = try await FrameIndexBuilder.build(url: outputURL)
            XCTAssertEqual(exportedIndex.frameTimes.count, 61, compression.title)
            XCTAssertEqual(exportedIndex.frameTimes.first ?? -1, 0, accuracy: 0.000_1)
            XCTAssertEqual(exportedIndex.frameTimes.last ?? -1, 2.0, accuracy: 0.02)

            if compression == .smart {
                let exportedAsset = AVURLAsset(url: outputURL)
                guard let exportedVideoTrack = try await exportedAsset
                    .loadTracks(withMediaType: .video)
                    .first else {
                    return XCTFail("智能推荐导出缺少视频轨道")
                }
                async let exportedSizeLoad = exportedVideoTrack.load(.naturalSize)
                async let exportedTransformLoad = exportedVideoTrack.load(.preferredTransform)
                async let exportedDescriptionsLoad = exportedVideoTrack.load(.formatDescriptions)
                async let exportedBitRateLoad = exportedVideoTrack.load(.estimatedDataRate)
                let (
                    exportedSize,
                    exportedTransform,
                    exportedDescriptions,
                    exportedBitRate
                ) = try await (
                    exportedSizeLoad,
                    exportedTransformLoad,
                    exportedDescriptionsLoad,
                    exportedBitRateLoad
                )
                let displayedRect = CGRect(origin: .zero, size: exportedSize)
                    .applying(exportedTransform)

                XCTAssertEqual(Int(abs(displayedRect.width).rounded()), model.metadata?.width)
                XCTAssertEqual(Int(abs(displayedRect.height).rounded()), model.metadata?.height)
                XCTAssertEqual(
                    MediaFormatInfo.codecName(from: exportedDescriptions.first),
                    "H.265 / HEVC"
                )
                if let sourceBitRate = model.metadata?.videoBitRate, sourceBitRate > 0 {
                    XCTAssertLessThan(Double(exportedBitRate), sourceBitRate)
                }
            }

            byteCounts[compression] = try FileManager.default.attributesOfItem(
                atPath: outputURL.path
            )[.size] as? Int64
        }

        XCTAssertGreaterThan(
            byteCounts[.highQuality] ?? 0,
            byteCounts[.balanced] ?? 0
        )
        XCTAssertGreaterThan(
            byteCounts[.balanced] ?? 0,
            byteCounts[.spaceSaving] ?? 0
        )
    }

    @MainActor
    func testSmartCompressionAgainstOptionalContentSample() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["FRAMECUT_CONTENT_QA_VIDEO"] else {
            throw XCTSkip("Set FRAMECUT_CONTENT_QA_VIDEO to run the content sample export check.")
        }

        let sourceURL = URL(fileURLWithPath: path)
        let outputURL: URL
        let shouldDeleteOutput: Bool
        if let outputPath = environment["FRAMECUT_CONTENT_QA_OUTPUT"] {
            outputURL = URL(fileURLWithPath: outputPath)
            shouldDeleteOutput = false
        } else {
            outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("FrameCut-Content-QA-\(UUID().uuidString)")
                .appendingPathExtension("mp4")
            shouldDeleteOutput = true
        }
        defer {
            if shouldDeleteOutput {
                try? FileManager.default.removeItem(at: outputURL)
            }
        }

        let model = VideoEditorModel()
        model.loadVideo(sourceURL)
        let loadTimeout = max(
            10,
            Double(environment["FRAMECUT_CONTENT_QA_LOAD_TIMEOUT"] ?? "60") ?? 60
        )
        try await waitUntil(timeout: loadTimeout) {
            model.canExport || model.errorMessage != nil || model.indexingNotice != nil
        }

        XCTAssertNil(model.errorMessage)
        XCTAssertNil(model.indexingNotice)
        guard let metadata = model.metadata else {
            return XCTFail("内容样本未能读取媒体信息")
        }
        guard let recommendation = model.smartCompressionRecommendation else {
            return XCTFail("内容样本未能生成智能压缩建议")
        }
        if sourceURL.pathExtension.caseInsensitiveCompare("avi") == .orderedSame {
            XCTAssertEqual(metadata.containerFormat, "AVI")
            if metadata.videoCodec.hasPrefix("Xvid") {
                XCTAssertEqual(metadata.audioCodec, "MP3")
                XCTAssertTrue(model.usesCompatibilityPipeline)
                XCTAssertEqual(model.mediaPreparationKind, .transcoded)
            }
        }

        let requestedStart = Double(environment["FRAMECUT_CONTENT_QA_START"] ?? "0") ?? 0
        let start = min(max(0, requestedStart), max(0, model.duration - 2))
        let requestedDuration = max(
            2,
            Double(environment["FRAMECUT_CONTENT_QA_DURATION"] ?? "6") ?? 6
        )
        model.updateInPoint(to: start, shouldSeek: false)
        model.updateOutPoint(
            to: min(model.duration, start + requestedDuration),
            shouldSeek: false
        )
        model.exportFormat = .mp4
        model.exportCompression = .smart
        model.exportSelection(to: outputURL)
        let exportTimeout = max(
            30,
            Double(environment["FRAMECUT_CONTENT_QA_TIMEOUT"] ?? "180") ?? 180
        )
        try await waitUntil(timeout: exportTimeout) {
            switch model.exportState {
            case .completed, .failed, .cancelled: return true
            default: return false
            }
        }

        guard case .completed = model.exportState else {
            return XCTFail("内容样本导出状态：\(model.exportState)")
        }
        let exportedAsset = AVURLAsset(url: outputURL)
        guard let exportedVideoTrack = try await exportedAsset
            .loadTracks(withMediaType: .video)
            .first else {
            return XCTFail("内容样本智能导出缺少视频轨道")
        }
        async let exportedSizeLoad = exportedVideoTrack.load(.naturalSize)
        async let exportedTransformLoad = exportedVideoTrack.load(.preferredTransform)
        async let exportedDescriptionsLoad = exportedVideoTrack.load(.formatDescriptions)
        async let exportedBitRateLoad = exportedVideoTrack.load(.estimatedDataRate)
        let (
            exportedSize,
            exportedTransform,
            exportedDescriptions,
            exportedBitRate
        ) = try await (
            exportedSizeLoad,
            exportedTransformLoad,
            exportedDescriptionsLoad,
            exportedBitRateLoad
        )
        let displayedRect = CGRect(origin: .zero, size: exportedSize)
            .applying(exportedTransform)
        let outputBytes = (try FileManager.default.attributesOfItem(
            atPath: outputURL.path
        )[.size] as? NSNumber)?.int64Value ?? 0

        XCTAssertEqual(Int(abs(displayedRect.width).rounded()), metadata.width)
        XCTAssertEqual(Int(abs(displayedRect.height).rounded()), metadata.height)
        XCTAssertEqual(
            MediaFormatInfo.codecName(from: exportedDescriptions.first),
            "H.265 / HEVC"
        )
        XCTAssertGreaterThan(outputBytes, 0)
        print(
            "CONTENT_QA",
            "assessment=\(recommendation.assessment.title)",
            "sourceVideoBitRate=\(Int(recommendation.sourceVideoBitRate.rounded()))",
            "targetVideoBitRate=\(Int(recommendation.targetVideoBitRate.rounded()))",
            "exportedVideoBitRate=\(Int(Double(exportedBitRate).rounded()))",
            "selectionStart=\(model.selectionStart)",
            "selectionDuration=\(model.selectionDuration)",
            "outputBytes=\(outputBytes)",
            "output=\(outputURL.path)"
        )
    }

    @MainActor
    func testAllExportProfilesAgainstOptionalCompatibilitySample() async throws {
        guard let path = ProcessInfo.processInfo.environment["FRAMECUT_COMPATIBILITY_QA_VIDEO"] else {
            throw XCTSkip(
                "Set FRAMECUT_COMPATIBILITY_QA_VIDEO to test every export profile."
            )
        }

        let model = VideoEditorModel()
        model.loadVideo(URL(fileURLWithPath: path))
        try await waitUntil(timeout: 60) {
            model.canExport || model.errorMessage != nil || model.indexingNotice != nil
        }
        XCTAssertNil(model.errorMessage)
        XCTAssertNil(model.indexingNotice)
        XCTAssertTrue(model.canExport)

        model.updateInPoint(to: 0, shouldSeek: false)
        model.updateOutPoint(to: min(2, model.duration), shouldSeek: false)
        model.exportFormat = .mp4

        var outputURLs: [URL] = []
        defer {
            for outputURL in outputURLs {
                try? FileManager.default.removeItem(at: outputURL)
            }
        }

        for compression in ExportCompression.allCases {
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "FrameCut-Compatibility-QA-\(compression.rawValue)-\(UUID().uuidString)"
                )
                .appendingPathExtension("mp4")
            outputURLs.append(outputURL)
            model.exportCompression = compression
            model.exportSelection(to: outputURL)
            try await waitUntil(timeout: 60) {
                switch model.exportState {
                case .completed, .failed, .cancelled: return true
                default: return false
                }
            }
            guard case .completed = model.exportState else {
                return XCTFail("\(compression.title) 导出失败：\(model.exportState)")
            }
            let index = try await FrameIndexBuilder.build(url: outputURL)
            XCTAssertFalse(index.frameTimes.isEmpty, compression.title)
        }
    }

    @MainActor
    private func waitUntil(
        timeout: TimeInterval,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() >= deadline {
                XCTFail("Timed out after \(timeout) seconds")
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    func testNearestFrameIndexChoosesClosestTimestamp() {
        let frames = [0.0, 0.04, 0.08, 0.12]

        XCTAssertEqual(FrameMath.nearestIndex(in: frames, to: 0.061), 2)
        XCTAssertEqual(FrameMath.nearestIndex(in: frames, to: -1), 0)
        XCTAssertEqual(FrameMath.nearestIndex(in: frames, to: 9), 3)
        XCTAssertNil(FrameMath.nearestIndex(in: [], to: 0))
    }

    func testTimelineViewportMapsOnlyVisibleRange() {
        let viewport = TimelineViewport(mediaDuration: 1_000, zoom: 10, center: 10)

        XCTAssertEqual(viewport.start, 0, accuracy: 0.000_001)
        XCTAssertEqual(viewport.end, 100, accuracy: 0.000_001)
        XCTAssertEqual(viewport.time(at: 300, trackWidth: 600), 50, accuracy: 0.000_001)
        XCTAssertEqual(viewport.x(for: 50, trackWidth: 600), 300, accuracy: 0.000_001)

        let trailingViewport = TimelineViewport(mediaDuration: 1_000, zoom: 10, center: 990)
        XCTAssertEqual(trailingViewport.start, 900, accuracy: 0.000_001)
        XCTAssertEqual(trailingViewport.end, 1_000, accuracy: 0.000_001)
    }

    func testTimelineZoomCanReachFrameLevelPrecision() {
        let duration = 7_361.783
        let frameRate = 15.0
        let trackWidth: CGFloat = 939
        let onePointPerFrameZoom = duration * frameRate / Double(trackWidth)
        let viewport = TimelineViewport(
            mediaDuration: duration,
            zoom: onePointPerFrameZoom,
            center: 0
        )

        XCTAssertEqual(
            viewport.time(at: 1, trackWidth: trackWidth) - viewport.start,
            1.0 / frameRate,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            TimelineViewport.maximumZoom(
                mediaDuration: duration,
                frameRate: frameRate,
                trackWidth: trackWidth
            ),
            onePointPerFrameZoom * 2,
            accuracy: 0.000_001
        )
    }

    func testTimelineHandleProjectionUsesStableDragOrigin() {
        let projected = TimelineDragProjection.time(
            origin: 14,
            translation: 200,
            visibleDuration: 40,
            trackWidth: 800,
            mediaDuration: 7_200
        )

        XCTAssertEqual(projected, 24, accuracy: 0.000_1)
        XCTAssertEqual(
            TimelineDragProjection.time(
                origin: 3,
                translation: -500,
                visibleDuration: 40,
                trackWidth: 800,
                mediaDuration: 7_200
            ),
            0,
            accuracy: 0.000_1
        )
    }

    func testTimelineWheelZoomNormalizesMouseAndTrackpadDeltas() {
        XCTAssertEqual(
            TimelineZoomProjection.targetZoom(
                currentZoom: 8,
                scrollDelta: 1,
                hasPreciseScrollingDeltas: false,
                maximumZoom: 128
            ),
            10,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            TimelineZoomProjection.targetZoom(
                currentZoom: 8,
                scrollDelta: 12,
                hasPreciseScrollingDeltas: true,
                maximumZoom: 128
            ),
            10,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            TimelineZoomProjection.targetZoom(
                currentZoom: 2,
                scrollDelta: -20,
                hasPreciseScrollingDeltas: false,
                maximumZoom: 128
            ),
            1,
            accuracy: 0.000_001
        )
    }

    func testTimelineWheelZoomKeepsPointerTimeStationary() {
        let oldViewport = TimelineViewport(mediaDuration: 1_000, zoom: 10, center: 400)
        let anchorFraction = 0.75
        let anchorTime = oldViewport.start + oldViewport.visibleDuration * anchorFraction
        let newZoom = 20.0
        let newCenter = TimelineZoomProjection.centerPreservingAnchor(
            anchorTime: anchorTime,
            anchorFraction: anchorFraction,
            mediaDuration: 1_000,
            targetZoom: newZoom
        )
        let newViewport = TimelineViewport(
            mediaDuration: 1_000,
            zoom: newZoom,
            center: newCenter
        )

        XCTAssertEqual(
            newViewport.start + newViewport.visibleDuration * anchorFraction,
            anchorTime,
            accuracy: 0.000_001
        )
    }

    func testCompressionEstimatesDecreaseByProfile() {
        let metadata = MediaMetadata(
            duration: 120,
            width: 1_920,
            height: 1_080,
            frameRate: 30,
            hasAudio: true
        )

        let high = ExportCompression.highQuality.estimatedByteCount(metadata: metadata, duration: 60)
        let balanced = ExportCompression.balanced.estimatedByteCount(metadata: metadata, duration: 60)
        let compact = ExportCompression.spaceSaving.estimatedByteCount(metadata: metadata, duration: 60)

        XCTAssertGreaterThan(high, balanced)
        XCTAssertGreaterThan(balanced, compact)
        XCTAssertEqual(ExportCompression.balanced.avPresetName, AVAssetExportPreset640x480)
        XCTAssertEqual(ExportCompression.smart.avPresetName, AVAssetExportPresetHEVCHighestQuality)
    }

    func testSmartCompressionUsesSourceBitrateAndQualityDensity() {
        let metadata = MediaMetadata(
            duration: 120,
            width: 1_920,
            height: 1_080,
            frameRate: 30,
            hasAudio: true,
            containerFormat: "MP4",
            fileSize: 128_000_000,
            videoCodec: "H.264 / AVC",
            videoBitRate: 8_400_000,
            audioCodec: "AAC",
            audioSampleRate: 48_000,
            audioChannelCount: 2,
            audioBitRate: 192_000
        )

        let recommendation = SmartCompressionAdvisor.recommendation(for: metadata)

        XCTAssertEqual(recommendation.assessment, .highQuality)
        XCTAssertLessThan(recommendation.targetVideoBitRate, metadata.videoBitRate)
        XCTAssertGreaterThan(recommendation.targetVideoBitRate, 4_000_000)
        XCTAssertGreaterThan(recommendation.reductionPercent ?? 0, 20)
        XCTAssertLessThan(recommendation.reductionPercent ?? 100, 50)
    }

    func testSmartCompressionProtectsEfficientCodecsAndLowBitrateSources() {
        let hevc = MediaMetadata(
            duration: 60,
            width: 1_920,
            height: 1_080,
            frameRate: 30,
            hasAudio: false,
            videoCodec: "H.265 / HEVC",
            videoBitRate: 4_000_000
        )
        let lowBitrateH264 = MediaMetadata(
            duration: 60,
            width: 1_920,
            height: 1_080,
            frameRate: 30,
            hasAudio: false,
            videoCodec: "H.264 / AVC",
            videoBitRate: 1_500_000
        )

        let hevcRecommendation = SmartCompressionAdvisor.recommendation(for: hevc)
        let lowBitrateRecommendation = SmartCompressionAdvisor.recommendation(for: lowBitrateH264)

        XCTAssertGreaterThanOrEqual(hevcRecommendation.targetVideoBitRate, 3_200_000)
        XCTAssertEqual(lowBitrateRecommendation.assessment, .alreadyCompressed)
        XCTAssertGreaterThanOrEqual(lowBitrateRecommendation.targetVideoBitRate, 1_350_000)
    }

    func testSmartCompressionCapsVeryHighBitrateSources() {
        let metadata = MediaMetadata(
            duration: 60,
            width: 1_920,
            height: 1_080,
            frameRate: 30,
            hasAudio: true,
            videoCodec: "Apple ProRes 422",
            videoBitRate: 100_000_000,
            audioBitRate: 1_536_000
        )

        let recommendation = SmartCompressionAdvisor.recommendation(for: metadata)

        XCTAssertEqual(recommendation.assessment, .bitrateRich)
        XCTAssertLessThan(recommendation.targetVideoBitRate, 9_000_000)
        XCTAssertEqual(recommendation.targetAudioBitRate, 160_000)
    }

    func testAVICompatibilityDetectionIsCaseInsensitive() {
        XCTAssertTrue(
            AVICompatibilityPreparer.requiresPreparation(
                for: URL(fileURLWithPath: "/tmp/sample.avi")
            )
        )
        XCTAssertTrue(
            AVICompatibilityPreparer.requiresPreparation(
                for: URL(fileURLWithPath: "/tmp/sample.AVI")
            )
        )
        XCTAssertFalse(
            AVICompatibilityPreparer.requiresPreparation(
                for: URL(fileURLWithPath: "/tmp/sample.mp4")
            )
        )
    }

    func testCommonMediaCompatibilityListCoversPopularContainers() {
        let supported = Set(MediaCompatibilityPreparer.supportedFileExtensions)

        for fileExtension in [
            "mp4", "mov", "avi", "mkv", "webm", "wmv", "mpg", "ts", "m2ts",
            "mxf", "flv", "3gp", "ogv", "rm", "rmvb", "divx", "dv", "mod",
            "tod", "m4ts", "m2v", "h264", "h265", "hevc", "av1"
        ] {
            XCTAssertTrue(supported.contains(fileExtension), fileExtension)
        }
        XCTAssertTrue(
            MediaCompatibilityPreparer.requiresPreparation(
                for: URL(fileURLWithPath: "/tmp/sample.mkv")
            )
        )
        XCTAssertFalse(
            MediaCompatibilityPreparer.requiresPreparation(
                for: URL(fileURLWithPath: "/tmp/sample.mov")
            )
        )
    }

    func testFFprobeOutputPreservesOriginalXvidAndMP3Metadata() throws {
        let data = Data(
            """
            {
              "streams": [
                {
                  "codec_name": "mpeg4",
                  "codec_long_name": "MPEG-4 part 2",
                  "codec_tag_string": "XVID",
                  "codec_type": "video",
                  "width": 854,
                  "height": 480,
                  "avg_frame_rate": "30000/1001",
                  "bit_rate": "963557"
                },
                {
                  "codec_name": "mp3",
                  "codec_long_name": "MP3",
                  "codec_type": "audio",
                  "sample_rate": "48000",
                  "channels": 2,
                  "bit_rate": "128000"
                }
              ],
              "format": {
                "duration": "7326.218900",
                "size": "1012330134",
                "bit_rate": "1105432"
              }
            }
            """.utf8
        )

        let info = try FFmpegTool.decodeProbeOutput(data)

        XCTAssertEqual(info.videoCodec, "Xvid / MPEG-4 Part 2")
        XCTAssertEqual(info.audioCodec, "MP3")
        XCTAssertEqual(info.width, 854)
        XCTAssertEqual(info.height, 480)
        XCTAssertEqual(info.frameRate, 30_000.0 / 1_001.0, accuracy: 0.000_001)
        XCTAssertEqual(info.videoBitRate, 963_557)
        XCTAssertEqual(info.duration, 7_326.218_9, accuracy: 0.000_001)
    }

    func testFFmpegTimeArgumentKeepsFrameBoundaryPrecision() {
        XCTAssertEqual(
            FFmpegTool.secondsArgument(3_282.015_348_682_015_4),
            "3282.015348682"
        )
    }

    func testSmartCompressionRecommendationMatchesLegacyAVISample() {
        let metadata = MediaMetadata(
            duration: 6_564.397_731,
            width: 656,
            height: 480,
            frameRate: 30_000.0 / 1_001.0,
            hasAudio: true,
            containerFormat: "AVI",
            fileSize: 1_753_882_504,
            videoCodec: "MPEG-4 Video",
            videoBitRate: 1_997_632,
            audioCodec: "MP3",
            audioSampleRate: 48_000,
            audioChannelCount: 2,
            audioBitRate: 128_000
        )

        let recommendation = SmartCompressionAdvisor.recommendation(for: metadata)

        XCTAssertEqual(recommendation.assessment, .bitrateRich)
        XCTAssertEqual(recommendation.targetVideoBitRate, 878_958.08, accuracy: 1)
        XCTAssertEqual(recommendation.targetAudioBitRate, 128_000)
        XCTAssertGreaterThanOrEqual(recommendation.reductionPercent ?? 0, 50)
        XCTAssertLessThanOrEqual(recommendation.reductionPercent ?? 100, 55)
    }

    func testMediaMetadataFormatsRichInspectorValues() {
        let metadata = MediaMetadata(
            duration: 120,
            width: 1_920,
            height: 1_080,
            frameRate: 29.97,
            hasAudio: true,
            containerFormat: "MP4",
            fileSize: 123_456_789,
            videoCodec: "H.264 / AVC",
            videoBitRate: 8_400_000,
            audioCodec: "AAC",
            audioSampleRate: 48_000,
            audioChannelCount: 2,
            audioBitRate: 192_000
        )

        XCTAssertEqual(metadata.aspectRatioText, "16:9")
        XCTAssertEqual(metadata.videoBitRateText, "8.40 Mbps")
        XCTAssertEqual(metadata.audioSampleRateText, "48 kHz")
        XCTAssertEqual(metadata.audioChannelText, "立体声")
        XCTAssertEqual(metadata.audioBitRateText, "192 kbps")
        XCTAssertFalse(metadata.fileSizeText.isEmpty)
    }

    @MainActor
    func testSourcePathAlsoDefinesDefaultExportDirectory() {
        let sourceURL = URL(fileURLWithPath: "/tmp/FrameCut Samples/source clip.mp4")
        let model = VideoEditorModel()

        model.loadVideo(sourceURL)

        XCTAssertEqual(model.fileDisplayPath, sourceURL.standardizedFileURL.path)
        XCTAssertEqual(
            model.exportDefaultDirectoryURL,
            sourceURL.standardizedFileURL.deletingLastPathComponent()
        )
    }

    func testKeyframeNavigationDoesNotRemainOnCurrentKeyframe() {
        let keyframes = [0.0, 1.0, 2.0, 3.0]

        XCTAssertEqual(FrameMath.previousIndex(in: keyframes, before: 2.0), 1)
        XCTAssertEqual(FrameMath.nextIndex(in: keyframes, after: 2.0), 3)
        XCTAssertNil(FrameMath.previousIndex(in: keyframes, before: 0.0))
        XCTAssertNil(FrameMath.nextIndex(in: keyframes, after: 3.0))
    }

    func testTimecodeUsesFrameComponent() {
        XCTAssertEqual(FrameMath.timecode(seconds: 3.5, frameRate: 30), "00:00:03:15")
        XCTAssertEqual(FrameMath.timecode(seconds: 3_661.0, frameRate: 25), "01:01:01:00")
        XCTAssertEqual(FrameMath.timecode(seconds: -3, frameRate: 30), "00:00:00:00")
    }

    func testOutPointIncludesSelectedFrame() {
        let frames = [0.0, 0.04, 0.08, 0.12]

        XCTAssertEqual(
            FrameMath.endExclusive(
                outPoint: 0.08,
                duration: 0.16,
                frameDuration: 0.04,
                frameTimes: frames
            ),
            0.12,
            accuracy: 0.000_001
        )

        XCTAssertEqual(
            FrameMath.endExclusive(
                outPoint: 0.12,
                duration: 0.16,
                frameDuration: 0.04,
                frameTimes: frames
            ),
            0.16,
            accuracy: 0.000_001
        )
    }

    func testClockFormatting() {
        XCTAssertEqual(FrameMath.clock(seconds: 65.125), "01:05.125")
        XCTAssertEqual(FrameMath.clock(seconds: 3_661.125), "01:01:01.125")
    }

    private func makeIsolatedUserDefaults() -> (UserDefaults, String) {
        let suiteName = "FrameCutTests.SetupAssistant.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    private func runtimeReport(
        isReady: Bool,
        hasHomebrew: Bool = true
    ) -> RuntimeDependencyReport {
        let ffmpegURL = isReady
            ? URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
            : nil
        return RuntimeDependencyReport(
            ffmpegURL: ffmpegURL,
            ffprobeURL: ffmpegURL,
            ffmpegVersion: isReady ? "ffmpeg version 8.1.1" : nil,
            ffprobeVersion: isReady ? "ffprobe version 8.1.1" : nil,
            hasH264PreviewEncoder: isReady,
            hasHEVCSmartEncoder: isReady,
            homebrewURL: hasHomebrew
                ? URL(fileURLWithPath: "/opt/homebrew/bin/brew")
                : nil
        )
    }
}
