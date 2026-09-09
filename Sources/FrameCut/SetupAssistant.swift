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
        installationLog = L10n.text("setup.installation_initial_log")

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
                    self.errorMessage = L10n.text("setup.homebrew_failed")
                    self.phase = .failed
                    return
                }

                _ = await self.checkDependencies()
                if self.report?.isReady != true {
                    self.errorMessage = L10n.text("setup.verification_failed")
                    self.phase = .failed
                }
            } catch {
                self.clearSelfCheckCompletion()
                self.errorMessage = L10n.format("setup.launch_failed", "\(error.localizedDescription)")
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
        let website = L10n.language == .simplifiedChinese ? "https://brew.sh/zh-cn/" : "https://brew.sh/"
        guard let url = URL(string: website) else { return }
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
                Text(L10n.text("setup.title"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(FrameCutColors.primaryText)
                Text(L10n.text("setup.subtitle"))
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
            Text(L10n.text("setup.checking"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(FrameCutColors.primaryText)
            Text(L10n.text("setup.checking_detail"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(FrameCutColors.secondaryText)
        }
    }

    private var requirementsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("setup.components_needed"))
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
                        Text(L10n.text("setup.homebrew_detected"))
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
                    Text(L10n.text("setup.installing"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(FrameCutColors.primaryText)
                    Text(L10n.text("setup.installing_detail"))
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
                    Text(L10n.text("setup.ready"))
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(FrameCutColors.primaryText)
                    Text(L10n.text("setup.ready_detail"))
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
                    Text(L10n.text("setup.failed"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(FrameCutColors.primaryText)
                    Text(model.errorMessage ?? L10n.text("setup.network_retry"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(FrameCutColors.secondaryText)
                }
            }

            ScrollView {
                Text(model.installationLog.isEmpty ? L10n.text("setup.no_log") : model.installationLog)
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
                title: L10n.text("setup.ffmpeg_title"),
                detail: model.report?.ffmpegURL?.path ?? L10n.text("setup.ffmpeg_detail"),
                isInstalled: model.report?.hasUsableFFmpeg == true
            )
            Divider().overlay(FrameCutColors.border)
            DependencyStatusRow(
                title: L10n.text("setup.ffprobe_title"),
                detail: model.report?.ffprobeURL?.path ?? L10n.text("setup.ffprobe_detail"),
                isInstalled: model.report?.hasUsableFFprobe == true
            )
            Divider().overlay(FrameCutColors.border)
            DependencyStatusRow(
                title: L10n.text("setup.h264_title"),
                detail: L10n.text("setup.h264_detail"),
                isInstalled: model.report?.hasH264PreviewEncoder == true
            )
            Divider().overlay(FrameCutColors.border)
            DependencyStatusRow(
                title: L10n.text("setup.hevc_title"),
                detail: L10n.text("setup.hevc_detail"),
                isInstalled: model.report?.hasHEVCSmartEncoder == true
            )
        }
        .panelSurface(radius: 9, color: FrameCutColors.panel)
    }

    private var homebrewGuide: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(L10n.text("setup.install_steps"))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(FrameCutColors.primaryText)
            Text(L10n.text("setup.homebrew_instructions"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(FrameCutColors.secondaryText)
                .lineSpacing(5)

            HStack(spacing: 10) {
                Button {
                    model.copyHomebrewCommandAndOpenTerminal()
                } label: {
                    Label(
                        model.didCopyHomebrewCommand ? L10n.text("setup.command_copied") : L10n.text("setup.copy_command"),
                        systemImage: model.didCopyHomebrewCommand ? "checkmark" : "terminal"
                    )
                }
                .buttonStyle(ToolbarActionButtonStyle(isPrimary: true))

                Button(L10n.text("setup.homebrew_website")) {
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
            Label(L10n.text("setup.source_notice"), systemImage: "lock.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(FrameCutColors.tertiaryText)

            Spacer()

            switch model.phase {
            case .checking, .installing:
                EmptyView()
            case .ready:
                Button(L10n.text("setup.get_started")) { model.finish() }
                    .buttonStyle(ToolbarActionButtonStyle(isPrimary: true))
            case .requirements:
                Button(L10n.text("common.later")) { model.postpone() }
                    .buttonStyle(ToolbarActionButtonStyle())
                if model.report?.homebrewURL == nil {
                    Button(L10n.text("setup.recheck")) { model.recheck() }
                        .buttonStyle(ToolbarActionButtonStyle(isPrimary: true))
                } else {
                    Button(L10n.text("setup.install_components")) { model.installRequiredComponents() }
                        .buttonStyle(ToolbarActionButtonStyle(isPrimary: true))
                }
            case .failed:
                Button(L10n.text("common.later")) { model.postpone() }
                    .buttonStyle(ToolbarActionButtonStyle())
                Button(L10n.text("common.retry")) {
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
        guard let report = model.report else { return L10n.text("setup.collecting_results") }
        if report.homebrewURL == nil {
            return L10n.format("setup.missing_homebrew", "\(report.missingComponentCount)")
        }
        return L10n.format("setup.missing_components", "\(report.missingComponentCount)")
    }

    private var stepText: String {
        switch model.phase {
        case .checking: return L10n.text("setup.step_check")
        case .requirements, .failed: return L10n.text("setup.step_install")
        case .installing: return L10n.text("setup.step_installing")
        case .ready: return L10n.text("setup.step_complete")
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

            Text(isInstalled ? L10n.text("setup.component_ready") : L10n.text("setup.component_missing"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isInstalled ? FrameCutColors.success : FrameCutColors.warning)
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
    }
}
