import AppKit
import Combine
import Foundation
import SwiftUI

struct RuntimeDependencyReport: Equatable, Sendable {
    let ffmpegURL: URL?
    let ffprobeURL: URL?
    let ffmpegVersion: String?
    let ffprobeVersion: String?
    let hasH264PreviewEncoder: Bool
    let hasHEVCSmartEncoder: Bool
    let homebrewURL: URL?

    var hasUsableFFmpeg: Bool {
        ffmpegURL != nil && ffmpegVersion != nil
    }

    var hasUsableFFprobe: Bool {
        ffprobeURL != nil && ffprobeVersion != nil
    }

    var isReady: Bool {
        hasUsableFFmpeg
            && hasUsableFFprobe
            && hasH264PreviewEncoder
            && hasHEVCSmartEncoder
    }

    var missingComponentCount: Int {
        [
            hasUsableFFmpeg,
            hasUsableFFprobe,
            hasH264PreviewEncoder,
            hasHEVCSmartEncoder
        ].filter { !$0 }.count
    }
}

enum RuntimeDependencyProbe {
    static func inspect(
        simulateMissing: Bool = false,
        simulateNoHomebrew: Bool = false
    ) async -> RuntimeDependencyReport {
        let homebrewURL = simulateNoHomebrew ? nil : executableURL(candidates: [
                "/opt/homebrew/bin/brew",
                "/usr/local/bin/brew"
            ])
        guard !simulateMissing else {
            return RuntimeDependencyReport(
                ffmpegURL: nil,
                ffprobeURL: nil,
                ffmpegVersion: nil,
                ffprobeVersion: nil,
                hasH264PreviewEncoder: false,
                hasHEVCSmartEncoder: false,
                homebrewURL: homebrewURL
            )
        }

        let ffmpegURL = FFmpegTool.executableURL
        let ffprobeURL = FFmpegTool.probeExecutableURL
        async let ffmpegVersion = firstOutputLine(
            executableURL: ffmpegURL,
            arguments: ["-version"]
        )
        async let ffprobeVersion = firstOutputLine(
            executableURL: ffprobeURL,
            arguments: ["-version"]
        )
        async let encoders = commandOutput(
            executableURL: ffmpegURL,
            arguments: ["-hide_banner", "-encoders"]
        )
        let (resolvedFFmpegVersion, resolvedFFprobeVersion, encoderOutput) = await (
            ffmpegVersion,
            ffprobeVersion,
            encoders
        )

        return RuntimeDependencyReport(
            ffmpegURL: ffmpegURL,
            ffprobeURL: ffprobeURL,
            ffmpegVersion: resolvedFFmpegVersion,
            ffprobeVersion: resolvedFFprobeVersion,
            hasH264PreviewEncoder: encoderOutput?.contains(" h264_videotoolbox ") == true
                || encoderOutput?.contains(" libx264 ") == true,
            hasHEVCSmartEncoder: encoderOutput?.contains(" libx265 ") == true,
            homebrewURL: homebrewURL
        )
    }

    private static func executableURL(candidates: [String]) -> URL? {
        candidates
            .map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private static func firstOutputLine(
        executableURL: URL?,
        arguments: [String]
    ) async -> String? {
        guard let output = await commandOutput(
            executableURL: executableURL,
            arguments: arguments
        ) else { return nil }
        return output.split(whereSeparator: \.isNewline).first.map(String.init)
    }

    private static func commandOutput(
        executableURL: URL?,
        arguments: [String]
    ) async -> String? {
        guard let executableURL,
              let data = try? await FFmpegTool.capture(
                executableURL: executableURL,
                arguments: arguments
              ) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}

enum SetupAssistantPhase: Equatable {
    case checking
    case requirements
    case installing
    case ready
    case failed
}

struct HomebrewInstallResult: Sendable {
    let terminationStatus: Int32
    let output: String
}

enum HomebrewInstaller {
    static let requiredFormulae = ["ffmpeg"]

    static func installRequiredComponents(
        using homebrewURL: URL
    ) async throws -> HomebrewInstallResult {
        try await Task.detached(priority: .userInitiated) {
            var combinedLog: [String] = []

            for formula in requiredFormulae {
                let installedResult = try runHomebrew(
                    at: homebrewURL,
                    arguments: ["list", "--versions", formula]
                )
                let action = installedResult.terminationStatus == 0 ? "reinstall" : "install"
                combinedLog.append("$ brew \(action) \(formula)")

                let installResult = try runHomebrew(
                    at: homebrewURL,
                    arguments: [action, formula]
                )
                let output = installResult.output.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                if !output.isEmpty {
                    combinedLog.append(output)
                }
                guard installResult.terminationStatus == 0 else {
                    return HomebrewInstallResult(
                        terminationStatus: installResult.terminationStatus,
                        output: combinedLog.joined(separator: "\n")
                    )
                }
            }

            return HomebrewInstallResult(
                terminationStatus: 0,
                output: combinedLog.joined(separator: "\n")
            )
        }.value
    }

    private static func runHomebrew(
        at homebrewURL: URL,
        arguments: [String]
    ) throws -> HomebrewInstallResult {
        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = homebrewURL
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ].joined(separator: ":")
        process.environment = environment
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        process.standardInput = FileHandle.nullDevice

        try process.run()
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return HomebrewInstallResult(
            terminationStatus: process.terminationStatus,
            output: String(decoding: outputData, as: UTF8.self)
        )
    }
}

@MainActor
final class SetupAssistantModel: ObservableObject {
    nonisolated static let homebrewInstallCommand =
        #"/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)""#
    nonisolated static let completionKey = "FrameCut.setupAssistant.completed.v1"

    typealias DependencyInspector = () async -> RuntimeDependencyReport
    typealias ComponentInstaller = (URL) async throws -> HomebrewInstallResult

    @Published var isPresented = false
    @Published private(set) var phase: SetupAssistantPhase = .checking
    @Published private(set) var report: RuntimeDependencyReport?
    @Published private(set) var installationLog = ""
    @Published private(set) var errorMessage: String?
    @Published private(set) var didCopyHomebrewCommand = false

    private let userDefaults: UserDefaults
    private let dependencyInspector: DependencyInspector
    private let componentInstaller: ComponentInstaller
    private var didRunLaunchCheck = false
    private var installationTask: Task<Void, Never>?

    init(
        userDefaults: UserDefaults = .standard,
        dependencyInspector: DependencyInspector? = nil,
        componentInstaller: ComponentInstaller? = nil
    ) {
        self.userDefaults = userDefaults

        let arguments = CommandLine.arguments
        let simulateMissing = arguments.contains("--simulate-missing-dependencies")
        let simulateNoHomebrew = arguments.contains("--simulate-no-homebrew")
        self.dependencyInspector = dependencyInspector ?? {
            await RuntimeDependencyProbe.inspect(
                simulateMissing: simulateMissing,
                simulateNoHomebrew: simulateNoHomebrew
            )
        }
        self.componentInstaller = componentInstaller ?? { homebrewURL in
            try await HomebrewInstaller.installRequiredComponents(using: homebrewURL)
        }
    }

    var hasCompletedSelfCheck: Bool {
        userDefaults.bool(forKey: Self.completionKey)
    }

    var isFirstRun: Bool {
        !hasCompletedSelfCheck
    }

    var forcePresentation: Bool {
        CommandLine.arguments.contains("--show-setup-assistant")
    }

    func runLaunchCheck() async {
        guard !didRunLaunchCheck else { return }
        didRunLaunchCheck = true

        guard forcePresentation || !hasCompletedSelfCheck else { return }

        let result = await checkDependencies()
        isPresented = forcePresentation || !result.isReady
    }

    func presentAndCheck() async {
        isPresented = true
        await checkDependencies()
    }

    func recheck() {
        Task { await checkDependencies() }
    }

    func installRequiredComponents() {
        guard phase != .installing,
              let report,
              let homebrewURL = report.homebrewURL else { return }
        phase = .installing
        errorMessage = nil
        installationLog = "正在通过 Homebrew 安装所需组件…\n首次安装可能需要几分钟，请保持网络连接。"

        installationTask?.cancel()
        installationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.componentInstaller(homebrewURL)
                self.installationLog = result.output.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                guard result.terminationStatus == 0 else {
                    self.clearSelfCheckCompletion()
                    self.errorMessage = "Homebrew 安装未完成，请查看安装日志后重试。"
                    self.phase = .failed
                    return
                }

                _ = await self.checkDependencies()
                if self.report?.isReady != true {
                    self.errorMessage = "安装已结束，但仍有组件未通过检测。"
                    self.phase = .failed
                }
            } catch {
                self.clearSelfCheckCompletion()
                self.errorMessage = "无法启动安装：\(error.localizedDescription)"
                self.phase = .failed
            }
        }
    }

    func copyHomebrewCommandAndOpenTerminal() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(Self.homebrewInstallCommand, forType: .string)
        didCopyHomebrewCommand = true

        let terminalURL = URL(
            fileURLWithPath: "/System/Applications/Utilities/Terminal.app",
            isDirectory: true
        )
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(
            at: terminalURL,
            configuration: configuration,
            completionHandler: nil
        )
    }

    func openHomebrewWebsite() {
        guard let url = URL(string: "https://brew.sh/zh-cn/") else { return }
        NSWorkspace.shared.open(url)
    }

    func finish() {
        guard report?.isReady == true else { return }
        markSelfCheckCompleted()
        isPresented = false
    }

    func postpone() {
        isPresented = false
    }

    @discardableResult
    private func checkDependencies() async -> RuntimeDependencyReport {
        phase = .checking
        errorMessage = nil
        let result = await dependencyInspector()
        report = result
        if result.isReady {
            markSelfCheckCompleted()
            phase = .ready
        } else {
            clearSelfCheckCompletion()
            phase = .requirements
        }
        return result
    }

    private func markSelfCheckCompleted() {
        userDefaults.set(true, forKey: Self.completionKey)
        userDefaults.set(Date(), forKey: "FrameCut.setupAssistant.completedAt.v1")
        userDefaults.set(
            report?.ffmpegVersion,
            forKey: "FrameCut.setupAssistant.ffmpegVersion.v1"
        )
    }

    private func clearSelfCheckCompletion() {
        userDefaults.removeObject(forKey: Self.completionKey)
        userDefaults.removeObject(forKey: "FrameCut.setupAssistant.completedAt.v1")
        userDefaults.removeObject(forKey: "FrameCut.setupAssistant.ffmpegVersion.v1")
    }
}

struct SetupAssistantView: View {
    @ObservedObject var model: SetupAssistantModel

    var body: some View {
        VStack(spacing: 0) {
            header

            Rectangle()
                .fill(FrameCutColors.border)
                .frame(height: 1)

            Group {
                switch model.phase {
                case .checking:
                    checkingView
                case .requirements:
                    requirementsView
                case .installing:
                    installingView
                case .ready:
                    readyView
                case .failed:
                    failedView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(26)

            Rectangle()
                .fill(FrameCutColors.border)
                .frame(height: 1)

            footer
        }
        .frame(width: 620, height: 640)
        .background(FrameCutColors.canvas)
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(
            model.phase == .checking || model.phase == .installing
        )
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(FrameCutColors.accent.opacity(0.16))
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(FrameCutColors.accentBright)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text("FrameCut 运行环境向导")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(FrameCutColors.primaryText)
                Text("检查完整媒体兼容功能所需的本地组件")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(FrameCutColors.secondaryText)
            }

            Spacer()

            Text(stepText)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(FrameCutColors.tertiaryText)
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(Color.white.opacity(0.05))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 24)
        .frame(height: 82)
        .background(FrameCutColors.toolbar)
    }

    private var checkingView: some View {
        VStack(spacing: 15) {
            ProgressView()
                .controlSize(.large)
                .tint(FrameCutColors.accentBright)
            Text("正在检测运行环境…")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(FrameCutColors.primaryText)
            Text("正在检查 FFmpeg、媒体探测器和压缩编码能力")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(FrameCutColors.secondaryText)
        }
    }

    private var requirementsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("需要补充运行组件")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(FrameCutColors.primaryText)
                    Text(requirementsSummary)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(FrameCutColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                dependencyList

                if model.report?.homebrewURL == nil {
                    homebrewGuide
                } else {
                    HStack(spacing: 9) {
                        Image(systemName: "shippingbox.fill")
                            .foregroundStyle(FrameCutColors.success)
                        Text("已检测到 Homebrew，可由 FrameCut 自动完成安装。")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(FrameCutColors.secondaryText)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .panelSurface(radius: 8, color: FrameCutColors.elevated)
                }
            }
        }
        .scrollIndicators(.automatic)
    }

    private var installingView: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 13) {
                ProgressView()
                    .controlSize(.regular)
                    .tint(FrameCutColors.accentBright)
                VStack(alignment: .leading, spacing: 3) {
                    Text("正在安装所需组件")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(FrameCutColors.primaryText)
                    Text("请勿退出 FrameCut；安装完成后会自动重新检测。")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(FrameCutColors.secondaryText)
                }
            }

            ScrollView {
                Text(model.installationLog)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(FrameCutColors.secondaryText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(13)
            }
            .panelSurface(radius: 8, color: FrameCutColors.player)
        }
    }

    private var readyView: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(FrameCutColors.success)
                VStack(alignment: .leading, spacing: 4) {
                    Text("运行环境检查通过")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(FrameCutColors.primaryText)
                    Text("自检结果已保存；下次启动无需重复检测。")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(FrameCutColors.secondaryText)
                }
            }

            dependencyList

            if let version = model.report?.ffmpegVersion {
                Text(version)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(FrameCutColors.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()
        }
    }

    private var failedView: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 25))
                    .foregroundStyle(FrameCutColors.danger)
                VStack(alignment: .leading, spacing: 3) {
                    Text("安装未完成")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(FrameCutColors.primaryText)
                    Text(model.errorMessage ?? "请检查网络连接后重试。")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(FrameCutColors.secondaryText)
                }
            }

            ScrollView {
                Text(model.installationLog.isEmpty ? "暂无安装日志" : model.installationLog)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(FrameCutColors.secondaryText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(13)
            }
            .panelSurface(radius: 8, color: FrameCutColors.player)
        }
    }

    private var dependencyList: some View {
        VStack(spacing: 0) {
            DependencyStatusRow(
                title: "FFmpeg 媒体引擎",
                detail: model.report?.ffmpegURL?.path ?? "负责常见格式解码与转换",
                isInstalled: model.report?.hasUsableFFmpeg == true
            )
            Divider().overlay(FrameCutColors.border)
            DependencyStatusRow(
                title: "ffprobe 媒体探测器",
                detail: model.report?.ffprobeURL?.path ?? "负责读取原始编码与码率",
                isInstalled: model.report?.hasUsableFFprobe == true
            )
            Divider().overlay(FrameCutColors.border)
            DependencyStatusRow(
                title: "H.264 兼容预览",
                detail: "用于系统无法直接读取的视频",
                isInstalled: model.report?.hasH264PreviewEncoder == true
            )
            Divider().overlay(FrameCutColors.border)
            DependencyStatusRow(
                title: "HEVC 智能压缩",
                detail: "需要 libx265 编码器",
                isInstalled: model.report?.hasHEVCSmartEncoder == true
            )
        }
        .panelSurface(radius: 9, color: FrameCutColors.panel)
    }

    private var homebrewGuide: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("安装步骤")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(FrameCutColors.primaryText)
            Text("1. 复制 Homebrew 官方安装命令并打开终端\n2. 在终端粘贴命令，按提示完成安装\n3. 返回此窗口并点击“重新检测”")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(FrameCutColors.secondaryText)
                .lineSpacing(5)

            HStack(spacing: 10) {
                Button {
                    model.copyHomebrewCommandAndOpenTerminal()
                } label: {
                    Label(
                        model.didCopyHomebrewCommand ? "已复制，终端已打开" : "复制命令并打开终端",
                        systemImage: model.didCopyHomebrewCommand ? "checkmark" : "terminal"
                    )
                }
                .buttonStyle(ToolbarActionButtonStyle(isPrimary: true))

                Button("查看 Homebrew 官网") {
                    model.openHomebrewWebsite()
                }
                .buttonStyle(ToolbarActionButtonStyle())
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelSurface(radius: 8, color: FrameCutColors.elevated)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Label("检测在本机完成；安装来自 Homebrew 官方源", systemImage: "lock.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(FrameCutColors.tertiaryText)

            Spacer()

            switch model.phase {
            case .checking, .installing:
                EmptyView()
            case .ready:
                Button("开始使用") { model.finish() }
                    .buttonStyle(ToolbarActionButtonStyle(isPrimary: true))
            case .requirements:
                Button("稍后") { model.postpone() }
                    .buttonStyle(ToolbarActionButtonStyle())
                if model.report?.homebrewURL == nil {
                    Button("重新检测") { model.recheck() }
                        .buttonStyle(ToolbarActionButtonStyle(isPrimary: true))
                } else {
                    Button("安装所需组件") { model.installRequiredComponents() }
                        .buttonStyle(ToolbarActionButtonStyle(isPrimary: true))
                }
            case .failed:
                Button("稍后") { model.postpone() }
                    .buttonStyle(ToolbarActionButtonStyle())
                Button("重试") {
                    if model.report?.homebrewURL == nil {
                        model.recheck()
                    } else {
                        model.installRequiredComponents()
                    }
                }
                .buttonStyle(ToolbarActionButtonStyle(isPrimary: true))
            }
        }
        .padding(.horizontal, 22)
        .frame(height: 68)
        .background(FrameCutColors.toolbar)
    }

    private var requirementsSummary: String {
        guard let report = model.report else { return "正在整理检测结果。" }
        if report.homebrewURL == nil {
            return "检测到 \(report.missingComponentCount) 项缺失。需要先安装 Homebrew，再安装 FFmpeg；你仍可稍后使用系统原生 MP4/MOV 功能。"
        }
        return "检测到 \(report.missingComponentCount) 项缺失。点击下方按钮后，FrameCut 将通过 Homebrew 安装标准 FFmpeg 套件。"
    }

    private var stepText: String {
        switch model.phase {
        case .checking: return "步骤 1 / 3 · 检测"
        case .requirements, .failed: return "步骤 2 / 3 · 安装"
        case .installing: return "步骤 2 / 3 · 安装中"
        case .ready: return "步骤 3 / 3 · 完成"
        }
    }
}

private struct DependencyStatusRow: View {
    let title: String
    let detail: String
    let isInstalled: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isInstalled ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(isInstalled ? FrameCutColors.success : FrameCutColors.warning)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(FrameCutColors.primaryText)
                Text(detail)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(FrameCutColors.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text(isInstalled ? "已就绪" : "需要安装")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isInstalled ? FrameCutColors.success : FrameCutColors.warning)
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
    }
}
