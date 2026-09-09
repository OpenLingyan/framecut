import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: VideoEditorModel
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            TopBar(model: model)

            Rectangle()
                .fill(FrameCutColors.border)
                .frame(height: 1)

            HStack(spacing: 0) {
                EditorWorkspace(model: model, isDropTargeted: isDropTargeted)

                Rectangle()
                    .fill(FrameCutColors.border)
                    .frame(width: 1)

                SelectionInspector(model: model)
                    .frame(width: 304)
            }

            if let error = model.errorMessage {
                ErrorBanner(message: error, model: model)
            }

            if model.exportState != .idle {
                ExportStatusBar(model: model)
            }

            FooterStatusBar(model: model)
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(FrameCutColors.canvas)
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(FrameCutColors.accentBright, style: StrokeStyle(lineWidth: 2, dash: [8, 5]))
                    .padding(9)
                    .background(FrameCutColors.accent.opacity(0.045))
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.openDroppedURLs(urls)
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .sheet(isPresented: $model.showExportReview) {
            ExportReviewSheet(model: model)
        }
        .onOpenURL { url in
            model.loadVideo(url)
        }
        .onAppear {
            model.loadStartupArgumentIfNeeded()
        }
    }
}

private struct TopBar: View {
    @ObservedObject var model: VideoEditorModel

    var body: some View {
        HStack(spacing: 14) {
            FrameCutBrandIcon()
            .frame(width: 36, height: 36)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("FrameCut")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(FrameCutColors.primaryText)
                Text(model.fileDisplayPath)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(FrameCutColors.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(model.mediaURL?.path ?? "打开一个本地视频")
            }
            .frame(minWidth: 260, maxWidth: 430, alignment: .leading)
            .layoutPriority(1)

            Spacer(minLength: 12)

            if let metadata = model.metadata {
                MediaChip(icon: "rectangle.inset.filled", text: metadata.resolutionText)
                MediaChip(icon: "film", text: metadata.frameRateText)
                MediaChip(
                    icon: metadata.hasAudio ? "speaker.wave.2.fill" : "speaker.slash.fill",
                    text: metadata.hasAudio ? "含音频" : "无音频"
                )
            }

            Spacer(minLength: 12)

            Button {
                model.openVideoPanel()
            } label: {
                Label("打开视频", systemImage: "folder")
            }
            .buttonStyle(ToolbarActionButtonStyle())
            .keyboardShortcut("o", modifiers: .command)
            .help("打开视频（⌘O），也可以直接拖入窗口")

            Button {
                model.requestExportReview()
            } label: {
                Label("导出片段", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(ToolbarActionButtonStyle(isPrimary: true))
            .keyboardShortcut("e", modifiers: .command)
            .disabled(!model.canExport)
            .help(exportHelp)
        }
        .padding(.leading, 82)
        .padding(.trailing, 18)
        .frame(height: 66)
        .background(FrameCutColors.toolbar)
    }

    private var exportHelp: String {
        if model.isPreparingCompatibilityMedia { return "正在准备兼容预览" }
        if model.isIndexingFrames { return "完成精确帧索引后即可导出" }
        if !model.canEdit { return "请先打开一个视频" }
        return "检查并导出所选片段（⌘E）"
    }
}

private struct FrameCutBrandIcon: View {
    var body: some View {
        Group {
            if let icon = bundledIcon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(FrameCutColors.accent)
                    Image(systemName: "film.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.white)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
    }

    private var bundledIcon: NSImage? {
        guard let url = Bundle.main.url(forResource: "FrameCut", withExtension: "icns") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}

private struct MediaChip: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(FrameCutColors.secondaryText)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(Color.white.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(FrameCutColors.border, lineWidth: 1)
            }
    }
}

private struct EditorWorkspace: View {
    @ObservedObject var model: VideoEditorModel
    let isDropTargeted: Bool

    var body: some View {
        VStack(spacing: 14) {
            PlayerStage(model: model, isDropTargeted: isDropTargeted)
                .layoutPriority(1)

            TransportControls(model: model)

            TimelinePanel(model: model)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PlayerStage: View {
    @ObservedObject var model: VideoEditorModel
    let isDropTargeted: Bool

    var body: some View {
        ZStack {
            FrameCutColors.player

            if model.canEdit {
                VideoPlayerView(player: model.player)
                    .accessibilityLabel("视频预览")
            } else if model.isLoading {
                LoadingVideoState(model: model)
            } else {
                EmptyVideoState(model: model, isDropTargeted: isDropTargeted)
            }

            if model.canEdit {
                VStack {
                    HStack {
                        Label("所选区间", systemImage: "selection.pin.in.out")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(FrameCutColors.primaryText)
                            .padding(.horizontal, 8)
                            .frame(height: 25)
                            .background(Color.black.opacity(0.56))
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        Spacer()
                    }

                    Spacer()

                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("当前帧")
                                .font(.system(size: 9, weight: .semibold))
                                .tracking(0.6)
                                .foregroundStyle(Color.white.opacity(0.52))
                            Text(model.currentTimecode)
                                .font(.system(size: 20, weight: .medium, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(Color.white)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.black.opacity(0.62))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                        Spacer()

                        Text("帧 \(model.currentFrameNumber.formatted()) / \(model.totalFrameCount.formatted())")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(Color.white.opacity(0.76))
                            .padding(.horizontal, 9)
                            .frame(height: 28)
                            .background(Color.black.opacity(0.62))
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                }
                .padding(12)
                .allowsHitTesting(false)
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minHeight: 280)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    isDropTargeted ? FrameCutColors.accentBright : FrameCutColors.borderStrong,
                    lineWidth: isDropTargeted ? 2 : 1
                )
        }
        .shadow(color: Color.black.opacity(0.28), radius: 18, y: 8)
    }
}

private struct EmptyVideoState: View {
    @ObservedObject var model: VideoEditorModel
    let isDropTargeted: Bool

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(isDropTargeted ? FrameCutColors.accent.opacity(0.18) : Color.white.opacity(0.045))
                Image(systemName: isDropTargeted ? "arrow.down.doc.fill" : "film.stack")
                    .font(.system(size: 27, weight: .medium))
                    .foregroundStyle(isDropTargeted ? FrameCutColors.accentBright : FrameCutColors.secondaryText)
            }
            .frame(width: 62, height: 62)

            VStack(spacing: 5) {
                Text(isDropTargeted ? "松开即可打开视频" : "打开一个视频开始精确切割")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(FrameCutColors.primaryText)
                Text("拖入 MP4、MOV、AVI、MKV、WebM 等常见视频")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(FrameCutColors.secondaryText)
            }

            Button {
                model.openVideoPanel()
            } label: {
                Label("选择本地视频", systemImage: "folder")
            }
            .buttonStyle(ToolbarActionButtonStyle(isPrimary: true))
        }
    }
}

private struct LoadingVideoState: View {
    @ObservedObject var model: VideoEditorModel

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
                .tint(FrameCutColors.accentBright)
            Text(model.compatibilityPreparationStatus ?? "正在读取视频")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(FrameCutColors.primaryText)
            if let progress = model.compatibilityPreparationProgress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(FrameCutColors.accentBright)
                    .frame(maxWidth: 280)
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(FrameCutColors.secondaryText)
            }
            Text(model.fileDisplayName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(FrameCutColors.tertiaryText)
                .lineLimit(1)
        }
    }
}

private struct TransportControls: View {
    @ObservedObject var model: VideoEditorModel

    var body: some View {
        HStack(spacing: 8) {
            Spacer()

            TransportButton(
                icon: "backward.end.fill",
                label: "上一关键帧",
                shortcut: "⇧←",
                isPrimary: false,
                action: { model.jumpToKeyframe(-1) }
            )

            TransportButton(
                icon: "backward.fill",
                label: "上一帧",
                shortcut: "←",
                isPrimary: false,
                action: { model.stepFrame(-1) }
            )

            TransportButton(
                icon: model.isPlaying ? "pause.fill" : "play.fill",
                label: model.isPlaying ? "暂停" : "播放选区",
                shortcut: "Space",
                isPrimary: true,
                action: { model.togglePlayback() }
            )

            TransportButton(
                icon: "forward.fill",
                label: "下一帧",
                shortcut: "→",
                isPrimary: false,
                action: { model.stepFrame(1) }
            )

            TransportButton(
                icon: "forward.end.fill",
                label: "下一关键帧",
                shortcut: "⇧→",
                isPrimary: false,
                action: { model.jumpToKeyframe(1) }
            )

            Spacer()
        }
        .disabled(!model.canEdit)
    }
}

private struct TransportButton: View {
    let icon: String
    let label: String
    let shortcut: String
    let isPrimary: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                if !isPrimary {
                    ShortcutBadge(text: shortcut)
                }
            }
        }
        .buttonStyle(TransportButtonStyle(isPrimary: isPrimary))
        .help("\(label)（\(shortcut)）")
    }
}

private struct TimelinePanel: View {
    @ObservedObject var model: VideoEditorModel
    @State private var timelineZoom = 1.0
    @State private var timelineCenter = 0.0

    var body: some View {
        VStack(spacing: 9) {
            HStack {
                HStack(spacing: 7) {
                    Text(model.currentTimecode)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(FrameCutColors.primaryText)
                    Text("/ \(model.durationClock)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(FrameCutColors.tertiaryText)
                }

                Spacer()

                if model.isIndexingFrames {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(FrameCutColors.accentBright)
                        Text("正在建立精确帧索引")
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(FrameCutColors.secondaryText)
                } else if model.canEdit {
                    HStack(spacing: 8) {
                        Text("\(model.frameTimes.count.formatted()) 帧 · \(model.keyframeTimes.count.formatted()) 关键帧")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(FrameCutColors.tertiaryText)

                        TimelineZoomControls(
                            model: model,
                            zoom: $timelineZoom,
                            center: $timelineCenter
                        )
                    }
                }
            }

            TrimTimelineView(
                model: model,
                zoom: $timelineZoom,
                center: $timelineCenter
            )
                .disabled(!model.canEdit)

            HStack {
                Label("精细轨道定位与 I/O；下方总览平移", systemImage: "cursorarrow.motionlines")
                Spacer()
                if model.isGeneratingThumbnails || model.isGeneratingDetailThumbnails {
                    Text("正在更新缩略图…")
                } else if timelineZoom > 1.001 {
                    Text(visibleRangeText)
                        .monospacedDigit()
                }
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(FrameCutColors.tertiaryText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .panelSurface(radius: 10, color: FrameCutColors.panel)
    }

    private var visibleRangeText: String {
        let viewport = TimelineViewport(
            mediaDuration: model.duration,
            zoom: timelineZoom,
            center: timelineCenter
        )
        return "\(FrameMath.clock(seconds: viewport.start)) – \(FrameMath.clock(seconds: viewport.end))"
    }
}

private struct SelectionInspector: View {
    @ObservedObject var model: VideoEditorModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("剪辑区间")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(FrameCutColors.primaryText)
                    Text("出点包含当前帧")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(FrameCutColors.tertiaryText)
                }

                MarkerCard(
                    marker: "I",
                    title: "入点",
                    timecode: model.canEdit ? model.selectionStartTimecode : "--:--:--:--",
                    frameText: model.canEdit ? "第 \(model.selectionStartFrameNumber.formatted()) 帧" : "尚未设置",
                    shortcut: "I",
                    actionTitle: "设为当前帧",
                    jumpAction: model.jumpToInPoint,
                    setAction: model.setInPointAtCurrentFrame
                )

                MarkerCard(
                    marker: "O",
                    title: "出点",
                    timecode: model.canEdit ? model.selectionEndTimecode : "--:--:--:--",
                    frameText: model.canEdit ? "第 \(model.selectionEndFrameNumber.formatted()) 帧" : "尚未设置",
                    shortcut: "O",
                    actionTitle: "设为当前帧",
                    jumpAction: model.jumpToOutPoint,
                    setAction: model.setOutPointAtCurrentFrame
                )

                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "所选片段")

                    HStack(spacing: 0) {
                        SelectionMetric(
                            title: "时长",
                            value: model.canEdit ? model.selectionDurationClock : "--:--.---"
                        )
                        Divider()
                            .overlay(FrameCutColors.border)
                            .padding(.vertical, 2)
                        SelectionMetric(
                            title: "帧数",
                            value: model.canEdit ? model.selectionFrameCount.formatted() : "—"
                        )
                    }
                    .frame(height: 48)

                    Button {
                        model.togglePlayback()
                    } label: {
                        Label(model.isPlaying ? "暂停预览" : "播放所选片段", systemImage: model.isPlaying ? "pause.fill" : "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ToolbarActionButtonStyle())
                    .disabled(!model.canEdit)

                    Button {
                        model.requestExportReview()
                    } label: {
                        Label("检查并导出", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ToolbarActionButtonStyle(isPrimary: true))
                    .disabled(!model.canExport)
                    .help(model.isIndexingFrames ? "正在建立精确帧索引" : "导出所选片段")
                }
                .padding(14)
                .panelSurface(radius: 9, color: FrameCutColors.elevated)

                if let metadata = model.metadata {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(title: "媒体信息")

                        MediaInfoGroup(
                            title: "文件",
                            items: [
                                MediaInfoItem(label: "容器", value: metadata.containerFormat),
                                MediaInfoItem(label: "文件大小", value: metadata.fileSizeText)
                            ]
                        )

                        MediaInfoGroup(
                            title: "视频",
                            items: [
                                MediaInfoItem(label: "编码", value: metadata.videoCodec),
                                MediaInfoItem(label: "分辨率", value: metadata.resolutionText),
                                MediaInfoItem(label: "画面比例", value: metadata.aspectRatioText),
                                MediaInfoItem(label: "帧率", value: metadata.frameRateText),
                                MediaInfoItem(label: "视频码率", value: metadata.videoBitRateText)
                            ]
                        )

                        MediaInfoGroup(
                            title: "音频",
                            items: audioItems(for: metadata)
                        )

                        MediaInfoGroup(
                            title: "时间线",
                            items: [
                                MediaInfoItem(label: "总时长", value: model.durationClock),
                                MediaInfoItem(label: "总帧数", value: frameCountText),
                                MediaInfoItem(label: "关键帧", value: keyframeCountText)
                            ]
                        )
                    }
                }
            }
            .padding(18)
        }
        .background(FrameCutColors.toolbar)
        .disabled(model.isLoading)
    }

    private var frameCountText: String {
        if model.isIndexingFrames { return "建立中…" }
        return model.frameTimes.isEmpty ? "不可用" : model.frameTimes.count.formatted()
    }

    private var keyframeCountText: String {
        if model.isIndexingFrames { return "建立中…" }
        return model.keyframeTimes.isEmpty ? "不可用" : model.keyframeTimes.count.formatted()
    }

    private func audioItems(for metadata: MediaMetadata) -> [MediaInfoItem] {
        guard metadata.hasAudio else {
            return [MediaInfoItem(label: "音轨", value: "无")]
        }
        return [
            MediaInfoItem(label: "编码", value: metadata.audioCodec ?? "未知"),
            MediaInfoItem(label: "采样率", value: metadata.audioSampleRateText),
            MediaInfoItem(label: "声道", value: metadata.audioChannelText),
            MediaInfoItem(label: "音频码率", value: metadata.audioBitRateText)
        ]
    }
}

private struct MarkerCard: View {
    let marker: String
    let title: String
    let timecode: String
    let frameText: String
    let shortcut: String
    let actionTitle: String
    let jumpAction: () -> Void
    let setAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text(marker)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .frame(width: 21, height: 21)
                    .background(FrameCutColors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(FrameCutColors.secondaryText)
                Spacer()
                Button(action: jumpAction) {
                    Image(systemName: "arrow.right.to.line")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 26, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(FrameCutColors.secondaryText)
                .help("跳转到\(title)")
            }

            Text(timecode)
                .font(.system(size: 21, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(FrameCutColors.primaryText)
                .contentTransition(.numericText())

            HStack {
                Text(frameText)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(FrameCutColors.tertiaryText)
                Spacer()
                Button(action: setAction) {
                    HStack(spacing: 5) {
                        Text(actionTitle)
                        ShortcutBadge(text: shortcut)
                    }
                    .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(FrameCutColors.accentBright)
            }
        }
        .padding(13)
        .panelSurface(radius: 9, color: FrameCutColors.elevated)
    }
}

private struct SelectionMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(FrameCutColors.tertiaryText)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(FrameCutColors.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
    }
}

private struct MediaInfoItem: Identifiable {
    let label: String
    let value: String

    var id: String { label }
}

private struct MediaInfoGroup: View {
    let title: String
    let items: [MediaInfoItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(FrameCutColors.tertiaryText)

            VStack(spacing: 7) {
                ForEach(items) { item in
                    InspectorInfoRow(label: item.label, value: item.value)
                }
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelSurface(radius: 7, color: FrameCutColors.elevated)
    }
}

private struct InspectorInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(FrameCutColors.tertiaryText)
            Spacer()
            Text(value)
                .foregroundStyle(FrameCutColors.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(value)
        }
        .font(.system(size: 11, weight: .medium))
    }
}

private struct ErrorBanner: View {
    let message: String
    @ObservedObject var model: VideoEditorModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(FrameCutColors.danger)
            VStack(alignment: .leading, spacing: 1) {
                Text("无法完成操作")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(FrameCutColors.primaryText)
                Text(message)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(FrameCutColors.secondaryText)
                    .lineLimit(1)
            }
            Spacer()
            Button("重新打开") { model.openVideoPanel() }
                .buttonStyle(.plain)
                .foregroundStyle(FrameCutColors.accentBright)
            Button { model.clearError() } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(FrameCutColors.secondaryText)
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
        .background(FrameCutColors.danger.opacity(0.09))
        .overlay(alignment: .top) {
            Rectangle().fill(FrameCutColors.danger.opacity(0.24)).frame(height: 1)
        }
    }
}

private struct ExportStatusBar: View {
    @ObservedObject var model: VideoEditorModel

    var body: some View {
        HStack(spacing: 11) {
            statusIcon

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(FrameCutColors.primaryText)
                if model.isExporting {
                    ProgressView(value: model.exportProgress)
                        .progressViewStyle(.linear)
                        .tint(FrameCutColors.accentBright)
                        .frame(maxWidth: 340)
                } else if let detail {
                    Text(detail)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(FrameCutColors.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer()

            if model.isExporting {
                Text("\(Int(model.exportProgress * 100))%")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(FrameCutColors.secondaryText)
                Button("取消") { model.cancelExport() }
                    .buttonStyle(.plain)
                    .foregroundStyle(FrameCutColors.danger)
            } else if case .completed = model.exportState {
                Button("在 Finder 中显示") { model.revealLastExport() }
                    .buttonStyle(.plain)
                    .foregroundStyle(FrameCutColors.accentBright)
                Button { model.dismissExportStatus() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .foregroundStyle(FrameCutColors.secondaryText)
            } else {
                Button("关闭") { model.dismissExportStatus() }
                    .buttonStyle(.plain)
                    .foregroundStyle(FrameCutColors.secondaryText)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background(FrameCutColors.elevated)
        .overlay(alignment: .top) {
            Rectangle().fill(FrameCutColors.border).frame(height: 1)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch model.exportState {
        case .preparing, .exporting:
            ProgressView().controlSize(.small).tint(FrameCutColors.accentBright)
        case .completed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(FrameCutColors.success)
        case .cancelled:
            Image(systemName: "stop.circle.fill").foregroundStyle(FrameCutColors.warning)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(FrameCutColors.danger)
        case .idle:
            EmptyView()
        }
    }

    private var title: String {
        switch model.exportState {
        case .preparing: return "正在准备导出"
        case .exporting: return "正在导出所选片段"
        case .completed: return "片段已保存"
        case .cancelled: return "导出已取消"
        case .failed: return "导出失败"
        case .idle: return ""
        }
    }

    private var detail: String? {
        switch model.exportState {
        case let .completed(url): return url.path
        case let .failed(message): return message
        case .cancelled: return "没有写入新的片段。"
        default: return nil
        }
    }
}

private struct FooterStatusBar: View {
    @ObservedObject var model: VideoEditorModel

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            Text(statusText)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(FrameCutColors.tertiaryText)
                .lineLimit(1)

            Spacer()

            Label("仅在本机处理，不上传视频", systemImage: "lock.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(FrameCutColors.tertiaryText)
        }
        .padding(.horizontal, 15)
        .frame(height: 28)
        .background(FrameCutColors.toolbar)
        .overlay(alignment: .top) {
            Rectangle().fill(FrameCutColors.border).frame(height: 1)
        }
    }

    private var statusColor: Color {
        if model.isLoading || model.isPreparingCompatibilityMedia || model.isIndexingFrames {
            return FrameCutColors.warning
        }
        if model.canEdit { return FrameCutColors.success }
        return FrameCutColors.tertiaryText
    }

    private var statusText: String {
        if model.isPreparingCompatibilityMedia {
            let status = model.compatibilityPreparationStatus ?? "正在准备兼容预览…"
            guard let progress = model.compatibilityPreparationProgress else { return status }
            return "\(status) \(Int((progress * 100).rounded()))%"
        }
        if model.isLoading { return "正在读取媒体信息…" }
        if model.isIndexingFrames { return "正在扫描真实帧时间和关键帧；完成后即可精确导出" }
        if let notice = model.indexingNotice { return notice }
        if model.canEdit { return "精确帧索引就绪" }
        return "等待打开视频"
    }
}

private struct ExportReviewSheet: View {
    @ObservedObject var model: VideoEditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(FrameCutColors.accent.opacity(0.16))
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(FrameCutColors.accentBright)
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 3) {
                    Text("导出所选片段")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(FrameCutColors.primaryText)
                    Text("确认范围后，再选择保存位置")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(FrameCutColors.secondaryText)
                }
            }

            VStack(spacing: 0) {
                ReviewRow(label: "源视频", value: model.fileDisplayPath)
                Divider().overlay(FrameCutColors.border)
                ReviewRow(label: "入点", value: "\(model.selectionStartTimecode)  ·  第 \(model.selectionStartFrameNumber.formatted()) 帧")
                Divider().overlay(FrameCutColors.border)
                ReviewRow(label: "出点", value: "\(model.selectionEndTimecode)  ·  第 \(model.selectionEndFrameNumber.formatted()) 帧")
                Divider().overlay(FrameCutColors.border)
                ReviewRow(label: "片段", value: "\(model.selectionDurationClock)  ·  \(model.selectionFrameCount.formatted()) 帧")
            }
            .padding(.horizontal, 13)
            .panelSurface(radius: 9, color: FrameCutColors.elevated)

            VStack(alignment: .leading, spacing: 9) {
                Text("输出格式")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(FrameCutColors.secondaryText)
                Picker("输出格式", selection: $model.exportFormat) {
                    ForEach(ExportFormat.allCases) { format in
                        Text(format.title).tag(format)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("压缩质量")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(FrameCutColors.secondaryText)
                    Spacer()
                    Text("智能模式推荐")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(FrameCutColors.tertiaryText)
                }

                Picker("压缩质量", selection: $model.exportCompression) {
                    ForEach(ExportCompression.allCases) { compression in
                        Text(compression.title).tag(compression)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)

                HStack(spacing: 10) {
                    Image(systemName: model.exportCompression.systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(FrameCutColors.accentBright)
                        .frame(width: 24, height: 24)
                        .background(FrameCutColors.accent.opacity(0.13))
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.exportCompressionDetail)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(FrameCutColors.secondaryText)
                        Text(model.exportCompressionAnalysisText)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(FrameCutColors.tertiaryText)
                    }

                    Spacer(minLength: 12)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("预计大小")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(FrameCutColors.tertiaryText)
                        Text(model.estimatedExportSizeText)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(FrameCutColors.primaryText)
                        if let reductionText = model.estimatedExportReductionText {
                            Text(reductionText)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(FrameCutColors.success)
                        }
                    }
                }
                .padding(10)
                .panelSurface(radius: 7, color: FrameCutColors.elevated)
            }

            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(FrameCutColors.success)
                Text("导出只会创建新文件，源视频保持不变；覆盖文件仍由 macOS 再次确认。")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(FrameCutColors.secondaryText)
            }
            .padding(11)
            .background(FrameCutColors.success.opacity(0.075))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            HStack {
                Spacer()
                Button("取消") {
                    model.showExportReview = false
                }
                .buttonStyle(ToolbarActionButtonStyle())

                Button {
                    model.chooseExportDestination()
                } label: {
                    Label("选择保存位置", systemImage: "arrow.right")
                }
                .buttonStyle(ToolbarActionButtonStyle(isPrimary: true))
            }
        }
        .padding(24)
        .frame(width: 520)
        .background(FrameCutColors.panel)
    }
}

private struct ReviewRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 16) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(FrameCutColors.tertiaryText)
                .frame(width: 48, alignment: .leading)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: label == "源视频" ? .default : .monospaced))
                .monospacedDigit()
                .foregroundStyle(FrameCutColors.primaryText)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .frame(height: 39)
    }
}
