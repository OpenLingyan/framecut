import Foundation

enum ExportMode: String, CaseIterable, Identifiable {
    case original
    case smart
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: return L10n.text("export.mode_original")
        case .smart: return L10n.text("export.mode_smart")
        case .custom: return L10n.text("export.mode_custom")
        }
    }

    var systemImage: String {
        switch self {
        case .original: return "film"
        case .smart: return "wand.and.stars"
        case .custom: return "slider.horizontal.3"
        }
    }
}

enum ExportVideoCodec: String, CaseIterable, Identifiable {
    case h264, hevc, mpeg4, prores, mjpeg, av1, vp9, unsupported

    var id: String { rawValue }

    var title: String {
        switch self {
        case .h264: return "H.264 / AVC"
        case .hevc: return "H.265 / HEVC"
        case .mpeg4: return "MPEG-4"
        case .prores: return "Apple ProRes"
        case .mjpeg: return "Motion JPEG"
        case .av1: return "AV1"
        case .vp9: return "VP9"
        case .unsupported: return L10n.text("common.unknown")
        }
    }

    static func source(_ name: String) -> Self {
        let name = name.lowercased()
        if name.contains("264") || name.contains("avc") { return .h264 }
        if name.contains("265") || name.contains("hevc") { return .hevc }
        if name.contains("prores") { return .prores }
        if name.contains("mpeg-4") || name.contains("mpeg4") || name.contains("xvid") || name.contains("divx") { return .mpeg4 }
        if name.contains("mjpeg") || name.contains("motion jpeg") { return .mjpeg }
        if name.contains("av1") { return .av1 }
        if name.contains("vp9") { return .vp9 }
        return .unsupported
    }

    var supportedFormats: [ExportFormat] {
        switch self {
        case .prores, .mjpeg: return [.mov]
        case .av1, .vp9: return [.mp4]
        default: return ExportFormat.allCases
        }
    }

    var encoder: String {
        switch self {
        case .h264: return "libx264"
        case .hevc: return "libx265"
        case .mpeg4: return "mpeg4"
        case .prores: return "prores_ks"
        case .mjpeg: return "mjpeg"
        case .av1: return "libsvtav1"
        case .vp9: return "libvpx-vp9"
        case .unsupported: return ""
        }
    }
}

struct CustomExportSettings: Equatable {
    var format: ExportFormat = .mp4
    var codec: ExportVideoCodec = .h264
    var width = ""
    var height = ""
    var frameRate = ""
    var bitRateMbps = ""

    init() {}

    init(metadata: MediaMetadata, sourceURL: URL) {
        codec = .source(metadata.videoCodec)
        let sourceFormat = ExportFormat(rawValue: sourceURL.pathExtension.lowercased()) ?? .mp4
        format = codec.supportedFormats.contains(sourceFormat)
            ? sourceFormat : codec.supportedFormats[0]
        width = metadata.width > 0 ? String(metadata.width) : ""
        height = metadata.height > 0 ? String(metadata.height) : ""
        frameRate = Self.numberText(metadata.frameRate)
        bitRateMbps = Self.numberText(metadata.videoBitRate / 1_000_000)
    }

    static func numberText(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return "" }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 9
        return formatter.string(from: NSNumber(value: value)) ?? ""
    }

    func validated() throws -> ResolvedExportSettings {
        guard codec != .unsupported else { throw ExportSettingsError.unsupportedCodec }
        guard codec.supportedFormats.contains(format) else { throw ExportSettingsError.container }
        guard let width = Int(width), let height = Int(height),
              (2...16_384).contains(width), (2...16_384).contains(height),
              width.isMultiple(of: 2), height.isMultiple(of: 2) else {
            throw ExportSettingsError.dimensions
        }
        guard let frameRate = Double(frameRate), frameRate.isFinite,
              frameRate >= 0.001, frameRate <= 240 else { throw ExportSettingsError.frameRate }
        guard let bitRate = Double(bitRateMbps), bitRate.isFinite,
              bitRate >= 0.000_001, bitRate <= 2_000 else { throw ExportSettingsError.bitRate }
        return ResolvedExportSettings(
            format: format, codec: codec, width: width, height: height,
            frameRate: frameRate, videoBitRate: bitRate * 1_000_000
        )
    }
}

enum ExportSettingsError: LocalizedError {
    case dimensions, frameRate, bitRate, unsupportedCodec, container, sourceDestination

    var errorDescription: String? {
        switch self {
        case .dimensions: return L10n.text("export.invalid_dimensions")
        case .frameRate: return L10n.text("export.invalid_frame_rate")
        case .bitRate: return L10n.text("export.invalid_bitrate")
        case .unsupportedCodec: return L10n.text("export.unsupported_source_codec")
        case .container: return L10n.text("export.invalid_container")
        case .sourceDestination: return L10n.text("export.source_destination")
        }
    }
}

struct ResolvedExportSettings: Equatable {
    let format: ExportFormat
    let codec: ExportVideoCodec
    let width: Int
    let height: Int
    let frameRate: Double
    let videoBitRate: Double

    func estimatedByteCount(duration: Double, audioBitRate: Double) -> Int64 {
        guard duration.isFinite, duration > 0 else { return 0 }
        let bytes = (videoBitRate + max(0, audioBitRate)) * duration / 8
        return Int64(min(bytes.rounded(), Double(Int64.max / 2)))
    }
}

enum ConfiguredFFmpegExport {
    static func arguments(
        settings: ResolvedExportSettings,
        metadata: MediaMetadata,
        sourceURL: URL,
        outputURL: URL,
        start: Double,
        duration: Double
    ) -> [String] {
        var arguments = [
            "-nostdin", "-y", "-hide_banner", "-loglevel", "error",
            "-ss", FFmpegTool.secondsArgument(start), "-i", sourceURL.path,
            "-t", FFmpegTool.secondsArgument(duration),
            "-map", "0:v:0", "-map", "0:a:0?", "-map_metadata", "0",
            "-c:v", settings.codec.encoder,
            "-b:v", String(Int(settings.videoBitRate.rounded()))
        ]
        switch settings.codec {
        case .h264:
            arguments += ["-preset", "medium", "-pix_fmt", "yuv420p"]
        case .hevc:
            arguments += ["-preset", "medium", "-pix_fmt", "yuv420p",
                          "-x265-params", "log-level=error", "-tag:v", "hvc1"]
        case .prores:
            let name = metadata.videoCodec.lowercased()
            let profile = name.contains("xq") ? 5 : name.contains("4444") ? 4
                : name.contains("hq") ? 3 : name.contains("lt") ? 1 : name.contains("proxy") ? 0 : 2
            let macroblocks = Double((settings.width + 15) / 16 * ((settings.height + 15) / 16))
            let bitsPerMacroblock = Int((settings.videoBitRate / settings.frameRate / macroblocks).rounded())
            arguments += ["-profile:v", String(profile), "-pix_fmt", profile >= 4 ? "yuva444p10le" : "yuv422p10le",
                          "-bits_per_mb", String(min(8_000, max(128, bitsPerMacroblock)))]
        case .mjpeg:
            arguments += ["-pix_fmt", "yuvj420p"]
        case .av1:
            arguments += ["-preset", "8", "-pix_fmt", "yuv420p"]
        case .vp9:
            arguments += ["-deadline", "good", "-cpu-used", "4", "-pix_fmt", "yuv420p"]
        case .mpeg4:
            arguments += ["-pix_fmt", "yuv420p"]
        case .unsupported:
            break
        }

        // Unchanged frame rates preserve source timestamps, including variable-rate video.
        if abs(settings.frameRate - metadata.frameRate) < 0.000_01 {
            arguments += ["-fps_mode", "passthrough", "-enc_time_base", "1:60000"]
        } else {
            arguments += ["-r", CustomExportSettings.numberText(settings.frameRate), "-fps_mode", "cfr"]
        }
        arguments += ["-vf", "scale=\(settings.width):\(settings.height):flags=lanczos,setsar=1"]
        if metadata.hasAudio {
            let audioBitRate = metadata.audioBitRate > 0
                ? min(320_000, max(64_000, metadata.audioBitRate)) : 128_000
            arguments += ["-c:a", "aac", "-b:a", String(Int(audioBitRate.rounded()))]
        }
        arguments += [
            "-movflags", "+faststart", "-f", settings.format.rawValue,
            "-progress", "pipe:1", "-stats_period", "0.5", "-nostats", outputURL.path
        ]
        return arguments
    }
}
