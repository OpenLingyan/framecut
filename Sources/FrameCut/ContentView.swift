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
        GeometryReader { geometry in
            toolbar(showMetadata: geometry.size.width >= 1_200)
        }
        .frame(height: 66)
    }

    private func toolbar(showMetadata: Bool) -> some View {
        HStack(spacing: 14) {
            FrameCutBrandIcon()
            .frame(width: 36, height: 36)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.text("app.name"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(FrameCutColors.primaryText)
                Text(model.fileDisplayPath)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(FrameCutColors.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(model.mediaURL?.path ?? L10n.text("file.open_local_hint"))
            }
            .frame(minWidth: 260, maxWidth: 430, alignment: .leading)
            .layoutPriority(1)

            Spacer(minLength: 12)

            if showMetadata, let metadata = model.metadata {
                MediaChip(icon: "rectangle.inset.filled", text: metadata.resolutionText)
                MediaChip(icon: "film", text: metadata.frameRateText)
                MediaChip(
                    icon: metadata.hasAudio ? "speaker.wave.2.fill" : "speaker.slash.fill",
                    text: metadata.hasAudio ? L10n.text("media.has_audio") : L10n.text("media.no_audio")
                )
            }

            Spacer(minLength: 12)

            Button {
                model.openVideoPanel()
            } label: {
                Label(L10n.text("file.open_video"), systemImage: "folder")
            }
            .buttonStyle(ToolbarActionButtonStyle())
            .keyboardShortcut("o", modifiers: .command)
            .help(L10n.text("file.open_video_hint"))

            Button {
                model.requestExportReview()
            } label: {
                Label(L10n.text("export.clip"), systemImage: "square.and.arrow.up")
            }
            .buttonStyle(ToolbarActionButtonStyle(isPrimary: true))
            .keyboardShortcut("e", modifiers: .command)
            .disabled(!model.canExport)
            .help(exportHelp)

            SettingsLink {
                Image(systemName: "gearshape")
            }
            .buttonStyle(ToolbarActionButtonStyle())
            .help(L10n.text("settings.menu"))
            .accessibilityLabel(L10n.text("settings.title"))
        }
        .padding(.leading, 82)
        .padding(.trailing, 18)
        .frame(height: 66)
        .background(FrameCutColors.toolbar)
    }

    private var exportHelp: String {
        if model.isPreparingCompatibilityMedia { return L10n.text("compatibility.preparing") }
        if model.isIndexingFrames { return L10n.text("export.wait_for_index") }
        if !model.canEdit { return L10n.text("file.open_first") }
        return L10n.text("export.review_hint")
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
                    .accessibilityLabel(L10n.text("player.preview"))
            } else if model.isLoading {
                LoadingVideoState(model: model)
            } else {
                EmptyVideoState(model: model, isDropTargeted: isDropTargeted)
            }

            if model.canEdit {
                VStack {
                    HStack {
                        Label(L10n.text("selection.range"), systemImage: "selection.pin.in.out")
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
                            Text(L10n.text("player.current_frame"))
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

                        Text(L10n.format("player.frame_position", "\(L10n.number(model.currentFrameNumber))", "\(L10n.number(model.totalFrameCount))"))
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
                Text(isDropTargeted ? L10n.text("file.drop_to_open") : L10n.text("file.empty_title"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(FrameCutColors.primaryText)
                Text(L10n.text("file.supported_hint"))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(FrameCutColors.secondaryText)
            }

            Button {
                model.openVideoPanel()
            } label: {
                Label(L10n.text("file.choose_video"), systemImage: "folder")
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
            Text(model.compatibilityPreparationStatus ?? L10n.text("file.loading_video"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(FrameCutColors.primaryText)
            if let progress = model.compatibilityPreparationProgress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(FrameCutColors.accentBright)
                    .frame(maxWidth: 280)
                Text(L10n.format("common.percent", "\(Int((progress * 100).rounded()))"))
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
        ViewThatFits(in: .horizontal) {
            controls(showsLabels: true)
            controls(showsLabels: false)
        }
        .disabled(!model.canEdit)
    }

    private func controls(showsLabels: Bool) -> some View {
        HStack(spacing: 8) {
            Spacer()

            TransportButton(
                icon: "backward.end.fill",
                label: L10n.text("transport.previous_keyframe"),
                shortcut: "⇧←",
                isPrimary: false,
                action: { model.jumpToKeyframe(-1) },
                showsLabel: showsLabels
            )

            TransportButton(
                icon: "backward.fill",
                label: L10n.text("transport.previous_frame"),
                shortcut: "←",
                isPrimary: false,
                action: { model.stepFrame(-1) },
                showsLabel: showsLabels
            )

            TransportButton(
                icon: model.isPlaying ? "pause.fill" : "play.fill",
                label: model.isPlaying ? L10n.text("transport.pause") : L10n.text("transport.play_selection"),
                shortcut: L10n.text("shortcut.space"),
                isPrimary: true,
                action: { model.togglePlayback() },
                showsLabel: showsLabels
            )

            TransportButton(
                icon: "forward.fill",
                label: L10n.text("transport.next_frame"),
                shortcut: "→",
                isPrimary: false,
                action: { model.stepFrame(1) },
                showsLabel: showsLabels
            )

            TransportButton(
                icon: "forward.end.fill",
                label: L10n.text("transport.next_keyframe"),
                shortcut: "⇧→",
                isPrimary: false,
                action: { model.jumpToKeyframe(1) },
                showsLabel: showsLabels
            )

            Spacer()
        }
    }
}

private struct TransportButton: View {
    let icon: String
    let label: String
    let shortcut: String
    let isPrimary: Bool
    let action: () -> Void
    var showsLabel = true

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                if showsLabel {
                    Text(label)
                        .font(.system(size: 11, weight: .semibold))
                        .fixedSize()
                }
                if !isPrimary {
                    ShortcutBadge(text: shortcut)
                }
            }
        }
        .buttonStyle(TransportButtonStyle(isPrimary: isPrimary))
        .accessibilityLabel(label)
        .help(L10n.format("common.shortcut_hint", label, shortcut))
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
                    Text(L10n.format("player.total_duration", model.durationClock))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(FrameCutColors.tertiaryText)
                }

                Spacer()

                if model.isIndexingFrames {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(FrameCutColors.accentBright)
                        Text(L10n.text("timeline.indexing"))
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(FrameCutColors.secondaryText)
                } else if model.canEdit {
                    HStack(spacing: 8) {
                        Text(L10n.format("timeline.frame_counts", "\(L10n.number(model.frameTimes.count))", "\(L10n.number(model.keyframeTimes.count))"))
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
                Label(L10n.text("timeline.navigation_hint"), systemImage: "cursorarrow.motionlines")
                Spacer()
                if model.isGeneratingThumbnails || model.isGeneratingDetailThumbnails {
                    Text(L10n.text("timeline.updating_thumbnails"))
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
        return L10n.format("timeline.time_range", FrameMath.clock(seconds: viewport.start), FrameMath.clock(seconds: viewport.end))
    }
}

private struct SelectionInspector: View {
    @ObservedObject var model: VideoEditorModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.text("selection.title"))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(FrameCutColors.primaryText)
                    Text(L10n.text("selection.inclusive_out"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(FrameCutColors.tertiaryText)
                }

                MarkerCard(
                    marker: "I",
                    title: L10n.text("selection.in"),
                    timecode: model.canEdit ? model.selectionStartTimecode : "--:--:--:--",
                    frameText: model.canEdit ? L10n.format("selection.frame_number", "\(L10n.number(model.selectionStartFrameNumber))") : L10n.text("selection.not_set"),
                    shortcut: "I",
                    actionTitle: L10n.text("selection.set_current"),
                    jumpAction: model.jumpToInPoint,
                    setAction: model.setInPointAtCurrentFrame
                )

                MarkerCard(
                    marker: "O",
                    title: L10n.text("selection.out"),
                    timecode: model.canEdit ? model.selectionEndTimecode : "--:--:--:--",
                    frameText: model.canEdit ? L10n.format("selection.frame_number", "\(L10n.number(model.selectionEndFrameNumber))") : L10n.text("selection.not_set"),
                    shortcut: "O",
                    actionTitle: L10n.text("selection.set_current"),
                    jumpAction: model.jumpToOutPoint,
                    setAction: model.setOutPointAtCurrentFrame
                )

                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: L10n.text("selection.clip"))

                    HStack(spacing: 0) {
                        SelectionMetric(
                            title: L10n.text("media.duration"),
                            value: model.canEdit ? model.selectionDurationClock : "--:--.---"
                        )
                        Divider()
                            .overlay(FrameCutColors.border)
                            .padding(.vertical, 2)
                        SelectionMetric(
                            title: L10n.text("media.frame_count"),
                            value: model.canEdit ? L10n.number(model.selectionFrameCount) : "—"
                        )
                    }
                    .frame(height: 48)

                    Button {
                        model.togglePlayback()
                    } label: {
                        Label(model.isPlaying ? L10n.text("transport.pause_preview") : L10n.text("transport.play_clip"), systemImage: model.isPlaying ? "pause.fill" : "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ToolbarActionButtonStyle())
                    .disabled(!model.canEdit)

                    Button {
                        model.requestExportReview()
                    } label: {
                        Label(L10n.text("export.review"), systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ToolbarActionButtonStyle(isPrimary: true))
                    .disabled(!model.canExport)
                    .help(model.isIndexingFrames ? L10n.text("timeline.indexing") : L10n.text("export.selected_clip"))
                }
                .padding(14)
                .panelSurface(radius: 9, color: FrameCutColors.elevated)

                if let metadata = model.metadata {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(title: L10n.text("media.info"))

                        MediaInfoGroup(
                            title: L10n.text("media.file"),
                            items: [
                                MediaInfoItem(label: L10n.text("media.container"), value: metadata.containerFormat),
                                MediaInfoItem(label: L10n.text("media.file_size"), value: metadata.fileSizeText)
                            ]
                        )

                        MediaInfoGroup(
                            title: L10n.text("media.video"),
                            items: [
                                MediaInfoItem(label: L10n.text("media.codec"), value: metadata.videoCodec),
                                MediaInfoItem(label: L10n.text("media.resolution"), value: metadata.resolutionText),
                                MediaInfoItem(label: L10n.text("media.aspect_ratio"), value: metadata.aspectRatioText),
                                MediaInfoItem(label: L10n.text("media.frame_rate"), value: metadata.frameRateText),
                                MediaInfoItem(label: L10n.text("media.video_bitrate"), value: metadata.videoBitRateText)
                            ]
                        )

                        MediaInfoGroup(
                            title: L10n.text("media.audio"),
                            items: audioItems(for: metadata)
                        )

                        MediaInfoGroup(
                            title: L10n.text("timeline.title"),
                            items: [
                                MediaInfoItem(label: L10n.text("media.total_duration"), value: model.durationClock),
                                MediaInfoItem(label: L10n.text("media.total_frames"), value: frameCountText),
                                MediaInfoItem(label: L10n.text("media.keyframes"), value: keyframeCountText)
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
        if model.isIndexingFrames { return L10n.text("timeline.indexing_short") }
        return model.frameTimes.isEmpty ? L10n.text("common.unavailable") : L10n.number(model.frameTimes.count)
    }

    private var keyframeCountText: String {
        if model.isIndexingFrames { return L10n.text("timeline.indexing_short") }
        return model.keyframeTimes.isEmpty ? L10n.text("common.unavailable") : L10n.number(model.keyframeTimes.count)
    }

    private func audioItems(for metadata: MediaMetadata) -> [MediaInfoItem] {
        guard metadata.hasAudio else {
            return [MediaInfoItem(label: L10n.text("media.audio_track"), value: L10n.text("common.none"))]
        }
        return [
            MediaInfoItem(label: L10n.text("media.codec"), value: metadata.audioCodec ?? L10n.text("common.unknown")),
            MediaInfoItem(label: L10n.text("media.sample_rate"), value: metadata.audioSampleRateText),
            MediaInfoItem(label: L10n.text("media.channels"), value: metadata.audioChannelText),
            MediaInfoItem(label: L10n.text("media.audio_bitrate"), value: metadata.audioBitRateText)
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
                .accessibilityLabel(L10n.format("selection.jump_hint", title))
                .help(L10n.format("selection.jump_hint", "\(title)"))
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
                Text(L10n.text("error.operation_failed"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(FrameCutColors.primaryText)
                Text(message)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(FrameCutColors.secondaryText)
                    .lineLimit(1)
            }
            Spacer()
            Button(L10n.text("file.reopen")) { model.openVideoPanel() }
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
                Text(L10n.format("common.percent", "\(Int(model.exportProgress * 100))"))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(FrameCutColors.secondaryText)
                Button(L10n.text("common.cancel")) { model.cancelExport() }
                    .buttonStyle(.plain)
                    .foregroundStyle(FrameCutColors.danger)
            } else if case .completed = model.exportState {
                Button(L10n.text("file.reveal_in_finder")) { model.revealLastExport() }
                    .buttonStyle(.plain)
                    .foregroundStyle(FrameCutColors.accentBright)
                Button { model.dismissExportStatus() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .foregroundStyle(FrameCutColors.secondaryText)
            } else {
                Button(L10n.text("common.close")) { model.dismissExportStatus() }
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
        case .preparing: return L10n.text("export.preparing")
        case .exporting: return L10n.text("export.exporting")
        case .completed: return L10n.text("export.completed")
        case .cancelled: return L10n.text("export.cancelled")
        case .failed: return L10n.text("export.failed")
        case .idle: return ""
        }
    }

    private var detail: String? {
        switch model.exportState {
        case let .completed(url): return url.path
        case let .failed(message): return message
        case .cancelled: return L10n.text("export.cancelled_detail")
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

            Label(L10n.text("privacy.local_only"), systemImage: "lock.fill")
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
            let status = model.compatibilityPreparationStatus ?? L10n.text("compatibility.preparing_ellipsis")
            guard let progress = model.compatibilityPreparationProgress else { return status }
            return L10n.format("common.status_progress", status, "\(Int((progress * 100).rounded()))")
        }
        if model.isLoading { return L10n.text("file.loading_metadata") }
        if model.isIndexingFrames { return L10n.text("timeline.scanning") }
        if let notice = model.indexingNotice { return notice }
        if model.canEdit { return L10n.text("timeline.ready") }
        return L10n.text("file.waiting")
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
                    Text(L10n.text("export.selected_clip"))
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(FrameCutColors.primaryText)
                    Text(L10n.text("export.review_subtitle"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(FrameCutColors.secondaryText)
                }
            }

            VStack(spacing: 0) {
                ReviewRow(label: L10n.text("export.source_video"), value: model.fileDisplayPath, monospaced: false)
                Divider().overlay(FrameCutColors.border)
                ReviewRow(label: L10n.text("selection.in"), value: L10n.format("selection.time_and_frame", "\(model.selectionStartTimecode)", "\(L10n.number(model.selectionStartFrameNumber))"))
                Divider().overlay(FrameCutColors.border)
                ReviewRow(label: L10n.text("selection.out"), value: L10n.format("selection.time_and_frame", "\(model.selectionEndTimecode)", "\(L10n.number(model.selectionEndFrameNumber))"))
                Divider().overlay(FrameCutColors.border)
                ReviewRow(label: L10n.text("export.segment"), value: L10n.format("selection.duration_and_frames", "\(model.selectionDurationClock)", "\(L10n.number(model.selectionFrameCount))"))
            }
            .padding(.horizontal, 13)
            .panelSurface(radius: 9, color: FrameCutColors.elevated)

            VStack(alignment: .leading, spacing: 9) {
                Text(L10n.text("export.format"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(FrameCutColors.secondaryText)
                Picker(L10n.text("export.format"), selection: $model.exportFormat) {
                    ForEach(ExportFormat.allCases) { format in
                        Text(format.title).tag(format)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text(L10n.text("export.compression"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(FrameCutColors.secondaryText)
                    Spacer()
                    Text(L10n.text("export.smart_recommended"))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(FrameCutColors.tertiaryText)
                }

                Picker(L10n.text("export.compression"), selection: $model.exportCompression) {
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
                            .fixedSize(horizontal: false, vertical: true)
                        Text(model.exportCompressionAnalysisText)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(FrameCutColors.tertiaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 12)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(L10n.text("export.estimated_size"))
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
                Text(L10n.text("export.source_unchanged"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(FrameCutColors.secondaryText)
            }
            .padding(11)
            .background(FrameCutColors.success.opacity(0.075))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            HStack {
                Spacer()
                Button(L10n.text("common.cancel")) {
                    model.showExportReview = false
                }
                .buttonStyle(ToolbarActionButtonStyle())

                Button {
                    model.chooseExportDestination()
                } label: {
                    Label(L10n.text("export.choose_location"), systemImage: "arrow.right")
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
    var monospaced = true

    var body: some View {
        HStack(spacing: 16) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(FrameCutColors.tertiaryText)
                .frame(width: 84, alignment: .leading)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: monospaced ? .monospaced : .default))
                .monospacedDigit()
                .foregroundStyle(FrameCutColors.primaryText)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .frame(height: 39)
    }
}
