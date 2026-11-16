import AVFoundation
import XCTest
@testable import FrameCut

final class ExportSettingsTests: XCTestCase {
    private func metadata(codec: String = "H.265 / HEVC") -> MediaMetadata {
        MediaMetadata(duration: 10, width: 1920, height: 1080,
                      frameRate: 60_000.0 / 1_001, hasAudio: true,
                      videoCodec: codec, videoBitRate: 7_420_123, audioBitRate: 128_000)
    }

    func testCustomDefaultsPreserveSourceValuesAndFractionalFrameRate() throws {
        let source = metadata()
        let draft = CustomExportSettings(metadata: source, sourceURL: URL(fileURLWithPath: "/sample.mov"))
        let settings = try draft.validated()
        XCTAssertEqual(settings.format, .mov)
        XCTAssertEqual(settings.codec, .hevc)
        XCTAssertEqual(settings.width, source.width)
        XCTAssertEqual(settings.height, source.height)
        XCTAssertEqual(settings.frameRate, source.frameRate, accuracy: 0.000_000_001)
        XCTAssertEqual(settings.videoBitRate, source.videoBitRate, accuracy: 0.001)
    }

    func testInvalidDraftsCannotBecomeExportSettings() {
        let source = CustomExportSettings(metadata: metadata(), sourceURL: URL(fileURLWithPath: "/sample.mp4"))
        for keyPath in [\CustomExportSettings.width, \.height] {
            for value in ["", "0", "-2", "1919", "640.5", "999999999999999999999999"] {
                var draft = source
                draft[keyPath: keyPath] = value
                XCTAssertThrowsError(try draft.validated(), value)
            }
        }
        for keyPath in [\CustomExportSettings.frameRate, \.bitRateMbps] {
            for value in ["", "0", "-1", "nan", "inf", "1e300", "0.0000000001", "abc"] {
                var draft = source
                draft[keyPath: keyPath] = value
                XCTAssertThrowsError(try draft.validated(), value)
            }
        }
    }

    func testSourceCodecIsNeverSilentlyChangedToH264() throws {
        for (name, codec, format) in [
            ("Apple ProRes 422 HQ", ExportVideoCodec.prores, ExportFormat.mov),
            ("Xvid / MPEG-4 Part 2", .mpeg4, .mp4),
            ("VP9", .vp9, .mp4)
        ] {
            let draft = CustomExportSettings(metadata: metadata(codec: name), sourceURL: URL(fileURLWithPath: "/sample.mkv"))
            XCTAssertEqual(try draft.validated().codec, codec)
            XCTAssertEqual(draft.format, format)
        }
        let unsupported = CustomExportSettings(metadata: metadata(codec: "VP8"), sourceURL: URL(fileURLWithPath: "/sample.webm"))
        XCTAssertEqual(unsupported.codec, .unsupported)
        XCTAssertThrowsError(try unsupported.validated())
    }

    @MainActor
    func testSmartAlwaysUsesMP4WithoutOverwritingCustomSettings() {
        let model = VideoEditorModel()
        model.customExportSettings = CustomExportSettings(metadata: metadata(), sourceURL: URL(fileURLWithPath: "/sample.mov"))
        model.customExportSettings.width = "1280"
        model.exportMode = .custom
        XCTAssertEqual(model.exportFormat, .mov)
        model.exportMode = .smart
        XCTAssertEqual(model.exportFormat, .mp4)
        XCTAssertTrue(model.exportSuggestedName.hasSuffix(".mp4"))
        model.exportMode = .original
        model.exportMode = .custom
        XCTAssertEqual(model.customExportSettings.width, "1280")
        XCTAssertEqual(model.exportFormat, .mov)
    }

    func testFrameTimingAndBitrateArgumentsFollowTheChosenSettings() throws {
        var draft = CustomExportSettings(metadata: metadata(), sourceURL: URL(fileURLWithPath: "/source.mov"))
        let original = ConfiguredFFmpegExport.arguments(
            settings: try draft.validated(), metadata: metadata(),
            sourceURL: URL(fileURLWithPath: "/source.mov"), outputURL: URL(fileURLWithPath: "/out.mov"),
            start: 1, duration: 2
        )
        XCTAssertTrue(original.contains("passthrough"))
        XCTAssertFalse(original.contains("-r"))
        draft.width = "640"
        draft.height = "360"
        draft.frameRate = "24"
        draft.bitRateMbps = "1.25"
        let settings = try draft.validated()
        let custom = ConfiguredFFmpegExport.arguments(
            settings: settings, metadata: metadata(),
            sourceURL: URL(fileURLWithPath: "/original source.mov"), outputURL: URL(fileURLWithPath: "/out.mov"),
            start: 1, duration: 2
        )
        XCTAssertTrue(custom.contains("scale=640:360:flags=lanczos,setsar=1"))
        XCTAssertEqual(custom[try XCTUnwrap(custom.firstIndex(of: "-r")) + 1], "24")
        XCTAssertEqual(custom[try XCTUnwrap(custom.firstIndex(of: "-b:v")) + 1], "1250000")
        XCTAssertEqual(custom[try XCTUnwrap(custom.firstIndex(of: "-i")) + 1], "/original source.mov")
        XCTAssertEqual(settings.estimatedByteCount(duration: 2, audioBitRate: 128_000), 344_500)
    }

    @MainActor
    func testCustomExportAppliesDimensionsCodecFrameRateAndBitrate() async throws {
        guard let path = ProcessInfo.processInfo.environment["FRAMECUT_QA_VIDEO"] else {
            throw XCTSkip("Set FRAMECUT_QA_VIDEO to run custom export integration checks.")
        }
        let model = VideoEditorModel()
        model.loadVideo(URL(fileURLWithPath: path))
        try await waitUntil { model.canExport || model.errorMessage != nil }
        XCTAssertNil(model.errorMessage)
        let sourceSettings = model.customExportSettings
        model.updateInPoint(to: 2, shouldSeek: false)
        model.updateOutPoint(to: 4, shouldSeek: false)
        model.exportMode = .custom

        for (codec, format, rate) in [(ExportVideoCodec.h264, ExportFormat.mp4, "24"), (.hevc, .mov, "15")] {
            let output = FileManager.default.temporaryDirectory.appendingPathComponent("FrameCut-Custom-\(UUID().uuidString).\(format.rawValue)")
            defer { try? FileManager.default.removeItem(at: output) }
            model.customExportSettings.codec = codec
            model.customExportSettings.format = format
            model.customExportSettings.width = "640"
            model.customExportSettings.height = "360"
            model.customExportSettings.frameRate = rate
            model.customExportSettings.bitRateMbps = "0.8"
            model.exportSelection(to: output)
            try await waitUntil { !model.isExporting }
            guard case .completed = model.exportState else {
                return XCTFail("Custom export failed: \(model.exportState)")
            }
            let info = try await FFmpegTool.probe(url: output)
            XCTAssertEqual(info.width, 640)
            XCTAssertEqual(info.height, 360)
            XCTAssertEqual(info.videoCodecIdentifier, codec == .h264 ? "h264" : "hevc")
            XCTAssertEqual(info.frameRate, Double(rate)!, accuracy: 0.01)
            XCTAssertGreaterThan(info.videoBitRate, 100_000)
            XCTAssertLessThan(info.videoBitRate, 1_600_000)
            XCTAssertEqual(info.duration, model.selectionDuration, accuracy: 0.1)
            XCTAssertTrue(info.hasAudio)
        }

        model.resetCustomExportSettings()
        XCTAssertEqual(model.customExportSettings, sourceSettings)
        model.customExportSettings.width = "0"
        XCTAssertFalse(model.canConfirmExport)
        let untouched = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sentinel = Data("Existing file".utf8)
        try sentinel.write(to: untouched)
        defer { try? FileManager.default.removeItem(at: untouched) }
        model.exportSelection(to: untouched)
        XCTAssertEqual(try Data(contentsOf: untouched), sentinel)
    }

    @MainActor
    func testOriginalExportPreservesSourceCodecOrientationAndVariableFrameTiming() async throws {
        guard let path = ProcessInfo.processInfo.environment["FRAMECUT_QA_VIDEO"] else {
            throw XCTSkip("Set FRAMECUT_QA_VIDEO to run source-preservation integration checks.")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("FrameCut-Source-QA-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixtures: [(String, [String], String)] = [
            ("source.mov", ["-c", "copy"], "h264"),
            ("legacy.avi", ["-an", "-c:v", "mpeg4", "-b:v", "3M"], "mpeg4"),
            ("variable.mp4", ["-an", "-vf", "select='if(lt(t,1),1,not(mod(n,2)))'", "-fps_mode", "vfr", "-c:v", "libx264", "-preset", "fast"], "h264"),
            ("portrait.mov", ["-c", "copy", "-metadata:s:v:0", "rotate=90"], "h264"),
            ("prores.mov", ["-an", "-vf", "scale=320:180", "-c:v", "prores_ks", "-profile:v", "3"], "prores")
        ]
        let model = VideoEditorModel()
        for (name, options, codec) in fixtures {
            let source = directory.appendingPathComponent(name)
            try await FFmpegTool.run(arguments: ["-nostdin", "-y", "-hide_banner", "-loglevel", "error", "-i", path, "-t", "3"] + options + [source.path])
            model.customExportSettings.width = "640"
            model.loadVideo(source)
            try await waitUntil { model.canExport || model.errorMessage != nil }
            XCTAssertNil(model.errorMessage, name)
            let metadata = try XCTUnwrap(model.metadata)
            XCTAssertEqual(model.customExportSettings.width, String(metadata.width), name)
            XCTAssertEqual(model.customExportSettings, model.originalExportSettings, name)
            model.updateInPoint(to: 0.1, shouldSeek: false)
            model.updateOutPoint(to: 1.7, shouldSeek: false)
            model.exportMode = .original
            let selectedTimes = model.frameTimes.filter { $0 >= model.selectionStart && $0 <= model.selectionEnd }
                .map { $0 - model.selectionStart }
            let output = directory.appendingPathComponent("output-\(name).\(model.exportFormat.rawValue)")
            model.exportSelection(to: output)
            try await waitUntil { !model.isExporting }
            guard case .completed = model.exportState else {
                return XCTFail("\(name): \(model.exportState)")
            }
            let info = try await FFmpegTool.probe(url: output)
            XCTAssertEqual(info.videoCodecIdentifier, codec, name)
            XCTAssertEqual(info.width, metadata.width, name)
            XCTAssertEqual(info.height, metadata.height, name)
            XCTAssertEqual(info.hasAudio, metadata.hasAudio, name)
            let index = try await FrameIndexBuilder.build(url: output)
            XCTAssertEqual(index.frameTimes.count, selectedTimes.count, name)
            for (actual, expected) in zip(index.frameTimes, selectedTimes) {
                XCTAssertEqual(actual, expected, accuracy: 0.000_1, name)
            }
        }
    }

    @MainActor
    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(45)
        while !condition() {
            guard Date() < deadline else {
                throw NSError(domain: "ExportSettingsTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Export timed out"])
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}
