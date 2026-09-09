import AppKit
import SwiftUI

struct TimelineViewport: Equatable {
    let mediaDuration: Double
    let zoom: Double
    let center: Double

    var effectiveZoom: Double {
        max(1, zoom.isFinite ? zoom : 1)
    }

    var visibleDuration: Double {
        guard mediaDuration > 0 else { return 0 }
        return mediaDuration / effectiveZoom
    }

    var start: Double {
        guard mediaDuration > 0 else { return 0 }
        let maximumStart = max(0, mediaDuration - visibleDuration)
        return min(max(0, center - visibleDuration / 2), maximumStart)
    }

    var end: Double {
        min(mediaDuration, start + visibleDuration)
    }

    func contains(_ time: Double, tolerance: Double = 0.000_5) -> Bool {
        time >= start - tolerance && time <= end + tolerance
    }

    func x(for time: Double, trackWidth: CGFloat) -> CGFloat {
        guard visibleDuration > 0, trackWidth > 0 else { return 0 }
        return CGFloat((time - start) / visibleDuration) * trackWidth
    }

    func clampedX(for time: Double, trackWidth: CGFloat) -> CGFloat {
        min(max(0, x(for: time, trackWidth: trackWidth)), trackWidth)
    }

    func time(at x: CGFloat, trackWidth: CGFloat) -> Double {
        guard visibleDuration > 0, trackWidth > 0 else { return start }
        let fraction = Double(min(max(0, x), trackWidth) / trackWidth)
        return min(mediaDuration, max(0, start + fraction * visibleDuration))
    }

    static func clampedCenter(
        _ requestedCenter: Double,
        mediaDuration: Double,
        zoom: Double
    ) -> Double {
        guard mediaDuration > 0 else { return 0 }
        let span = mediaDuration / max(1, zoom)
        guard span < mediaDuration else { return mediaDuration / 2 }
        return min(max(span / 2, requestedCenter), mediaDuration - span / 2)
    }

    static func maximumZoom(
        mediaDuration: Double,
        frameRate: Double,
        trackWidth: CGFloat,
        minimumPointsPerFrame: Double = 2
    ) -> Double {
        guard mediaDuration > 0, frameRate > 0, trackWidth > 0 else { return 8 }
        let zoomForFrameSpacing = mediaDuration * frameRate * minimumPointsPerFrame / Double(trackWidth)
        return min(4_096, max(8, zoomForFrameSpacing))
    }
}

struct TimelineDragProjection {
    static func time(
        origin: Double,
        translation: CGFloat,
        visibleDuration: Double,
        trackWidth: CGFloat,
        mediaDuration: Double
    ) -> Double {
        let delta = Double(translation / max(trackWidth, 1)) * visibleDuration
        return min(max(0, origin + delta), mediaDuration)
    }
}

struct TimelineZoomProjection {
    static func targetZoom(
        currentZoom: Double,
        scrollDelta: Double,
        hasPreciseScrollingDeltas: Bool,
        maximumZoom: Double
    ) -> Double {
        guard currentZoom.isFinite,
              scrollDelta.isFinite,
              maximumZoom.isFinite,
              maximumZoom >= 1 else { return 1 }

        // A mouse wheel normally reports one unit per notch, while a trackpad
        // reports smaller point-based deltas. Normalize both to calm zoom steps.
        let rawSteps = hasPreciseScrollingDeltas ? scrollDelta / 12 : scrollDelta
        let steps = min(4, max(-4, rawSteps))
        let projectedZoom = max(1, currentZoom) * pow(1.25, steps)
        return min(maximumZoom, max(1, projectedZoom))
    }

    static func centerPreservingAnchor(
        anchorTime: Double,
        anchorFraction: Double,
        mediaDuration: Double,
        targetZoom: Double
    ) -> Double {
        guard mediaDuration > 0,
              mediaDuration.isFinite,
              targetZoom.isFinite else { return 0 }
        guard targetZoom > 1.001 else { return mediaDuration / 2 }

        let fraction = min(1, max(0, anchorFraction))
        let visibleDuration = mediaDuration / max(1, targetZoom)
        let requestedStart = anchorTime - fraction * visibleDuration
        let requestedCenter = requestedStart + visibleDuration / 2
        return TimelineViewport.clampedCenter(
            requestedCenter,
            mediaDuration: mediaDuration,
            zoom: targetZoom
        )
    }
}

struct TimelineZoomControls: View {
    @ObservedObject var model: VideoEditorModel
    @Binding var zoom: Double
    @Binding var center: Double

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(FrameCutColors.tertiaryText)
                .frame(width: 18)

            zoomButton(
                icon: "minus",
                help: "缩小时间轴（⌘−）",
                action: { adjustZoom(by: 0.5) }
            )
            .keyboardShortcut("-", modifiers: .command)

            Text(zoom <= 1.001 ? "全片" : "\(Int(zoom.rounded()))×")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(FrameCutColors.secondaryText)
                .frame(minWidth: 34)

            zoomButton(
                icon: "plus",
                help: "放大时间轴（⌘+）",
                action: { adjustZoom(by: 2) }
            )
            .keyboardShortcut("+", modifiers: .command)

            zoomButton(
                icon: "arrow.counterclockwise",
                help: "恢复全片视图",
                action: resetZoom
            )
        }
        .padding(2)
        .background(Color.white.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(FrameCutColors.border, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .disabled(!model.canEdit)
        .onChange(of: model.mediaURL) { _, _ in
            resetZoom()
        }
        .onChange(of: model.duration) { _, newDuration in
            if zoom <= 1.001 {
                center = newDuration / 2
            }
        }
    }

    @ViewBuilder
    private func zoomButton(icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(FrameCutColors.secondaryText)
                .frame(width: 22, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func adjustZoom(by factor: Double) {
        guard model.duration > 0 else { return }
        let targetZoom = min(4_096, max(1, zoom * factor))
        if targetZoom <= 1.001 {
            resetZoom()
            return
        }

        let currentViewport = TimelineViewport(
            mediaDuration: model.duration,
            zoom: zoom,
            center: center
        )
        let anchor = currentViewport.contains(model.currentTime)
            ? model.currentTime
            : currentViewport.start + currentViewport.visibleDuration / 2
        zoom = targetZoom
        center = TimelineViewport.clampedCenter(
            anchor,
            mediaDuration: model.duration,
            zoom: targetZoom
        )
    }

    private func resetZoom() {
        zoom = 1
        center = model.duration / 2
    }
}

struct TrimTimelineView: View {
    @ObservedObject var model: VideoEditorModel
    @Binding var zoom: Double
    @Binding var center: Double

    @State private var magnificationBaseZoom: Double?
    @State private var didApplyInitialZoom = false
    @State private var isPointerInteracting = false

    var body: some View {
        GeometryReader { proxy in
            let horizontalInset: CGFloat = 8
            let trackWidth = max(1, proxy.size.width - horizontalInset * 2)
            let mediaDuration = max(model.duration, 0.000_001)
            let maximumZoom = TimelineViewport.maximumZoom(
                mediaDuration: mediaDuration,
                frameRate: model.framesPerSecond,
                trackWidth: trackWidth
            )
            let effectiveZoom = min(max(1, zoom), maximumZoom)
            let viewport = TimelineViewport(
                mediaDuration: mediaDuration,
                zoom: effectiveZoom,
                center: center
            )

            VStack(spacing: 6) {
                detailTrack(
                    viewport: viewport,
                    horizontalInset: horizontalInset,
                    trackWidth: trackWidth
                )
                .frame(height: 82)
                .background {
                    TimelineScrollWheelCapture { event, location in
                        handleScrollWheel(
                            event: event,
                            locationX: location.x,
                            viewport: viewport,
                            horizontalInset: horizontalInset,
                            trackWidth: trackWidth,
                            maximumZoom: maximumZoom
                        )
                    }
                }
                .simultaneousGesture(
                    magnifyGesture(
                        mediaDuration: mediaDuration,
                        maximumZoom: maximumZoom
                    )
                )

                overviewTrack(
                    viewport: viewport,
                    horizontalInset: horizontalInset,
                    trackWidth: trackWidth
                )
                .frame(height: 22)
            }
            .onAppear {
                normalizeZoom(maximumZoom: maximumZoom, mediaDuration: mediaDuration)
                applyInitialZoomIfNeeded(
                    mediaDuration: mediaDuration,
                    trackWidth: trackWidth,
                    maximumZoom: maximumZoom
                )
                refreshDetailThumbnails(for: viewport)
            }
            .onChange(of: viewport) { _, newViewport in
                refreshDetailThumbnails(for: newViewport)
            }
            .onChange(of: maximumZoom) { _, newMaximum in
                normalizeZoom(maximumZoom: newMaximum, mediaDuration: mediaDuration)
                applyInitialZoomIfNeeded(
                    mediaDuration: mediaDuration,
                    trackWidth: trackWidth,
                    maximumZoom: newMaximum
                )
            }
            .onChange(of: zoom) { _, _ in
                normalizeZoom(maximumZoom: maximumZoom, mediaDuration: mediaDuration)
            }
            .onChange(of: model.canEdit) { _, canEdit in
                guard canEdit else { return }
                applyInitialZoomIfNeeded(
                    mediaDuration: mediaDuration,
                    trackWidth: trackWidth,
                    maximumZoom: maximumZoom
                )
            }
            .onChange(of: model.currentTime) { _, newTime in
                guard !isPointerInteracting,
                      !model.isTimelineScrubbing,
                      effectiveZoom > 1.001,
                      !viewport.contains(newTime) else { return }
                center = TimelineViewport.clampedCenter(
                    newTime,
                    mediaDuration: mediaDuration,
                    zoom: effectiveZoom
                )
            }
            .onChange(of: model.isTimelineScrubbing) { _, isScrubbing in
                guard !isScrubbing, isPointerInteracting else { return }
                Task { @MainActor in
                    await Task.yield()
                    guard !model.isTimelineScrubbing else { return }
                    isPointerInteracting = false
                }
            }
            .onChange(of: model.mediaURL) { _, _ in
                didApplyInitialZoom = false
                zoom = 1
                center = model.duration / 2
                model.clearDetailTimelineThumbnails()
            }
        }
        .frame(height: 110)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("可缩放视频时间线")
    }

    @ViewBuilder
    private func detailTrack(
        viewport: TimelineViewport,
        horizontalInset: CGFloat,
        trackWidth: CGFloat
    ) -> some View {
        let trackHeight: CGFloat = 66
        let selectedStartX = horizontalInset + viewport.clampedX(
            for: model.selectionStart,
            trackWidth: trackWidth
        )
        let selectedEndX = horizontalInset + viewport.clampedX(
            for: model.selectionEnd,
            trackWidth: trackWidth
        )
        let frameTolerance = 0.5 / max(model.framesPerSecond, 1)
        let detailThumbnails = viewport.effectiveZoom > 1.001
            ? model.detailTimelineThumbnails
            : model.timelineThumbnails

        ZStack(alignment: .topLeading) {
            filmstrip(
                width: trackWidth,
                height: trackHeight,
                thumbnails: detailThumbnails
            )
            .frame(width: trackWidth, height: trackHeight)
            .offset(x: horizontalInset, y: 8)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            Rectangle()
                .fill(Color.black.opacity(0.62))
                .frame(width: max(0, selectedStartX - horizontalInset), height: trackHeight)
                .offset(x: horizontalInset, y: 8)

            Rectangle()
                .fill(Color.black.opacity(0.62))
                .frame(
                    width: max(0, horizontalInset + trackWidth - selectedEndX),
                    height: trackHeight
                )
                .offset(x: selectedEndX, y: 8)

            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(FrameCutColors.accentBright, lineWidth: 2)
                .frame(width: max(2, selectedEndX - selectedStartX), height: trackHeight)
                .offset(x: selectedStartX, y: 8)

            ForEach(displayedKeyframes(in: viewport), id: \.self) { keyframe in
                let x = horizontalInset + viewport.x(for: keyframe, trackWidth: trackWidth)
                Rectangle()
                    .fill(FrameCutColors.warning.opacity(0.75))
                    .frame(width: 1, height: 7)
                    .offset(x: x, y: 67)
            }

            Color.clear
                .contentShape(Rectangle())
                .frame(width: trackWidth, height: trackHeight)
                .offset(x: horizontalInset, y: 8)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            beginPointerInteraction()
                            model.scrubTimeline(
                                to: viewport.time(at: value.location.x, trackWidth: trackWidth)
                            )
                        }
                        .onEnded { value in
                            model.endTimelineScrubbing(
                                at: viewport.time(at: value.location.x, trackWidth: trackWidth)
                            )
                        }
                )

            if viewport.contains(model.selectionStart, tolerance: frameTolerance) {
                TimelineHandle(
                    label: "I",
                    color: FrameCutColors.accentBright,
                    value: model.selectionStart,
                    mediaDuration: model.duration,
                    visibleDuration: viewport.visibleDuration,
                    trackWidth: trackWidth,
                    onBegin: {
                        beginPointerInteraction()
                        model.beginTimelineScrubbing()
                    },
                    onChange: { value in
                        model.updateInPoint(to: value, shouldSeek: false)
                        model.scrubTimeline(to: model.selectionStart)
                    },
                    onEnd: { value in
                        model.updateInPoint(to: value, shouldSeek: false)
                        model.endTimelineScrubbing(at: model.selectionStart)
                    }
                )
                .position(
                    x: horizontalInset + viewport.x(for: model.selectionStart, trackWidth: trackWidth),
                    y: 40
                )
            }

            if viewport.contains(model.selectionEnd, tolerance: frameTolerance) {
                TimelineHandle(
                    label: "O",
                    color: FrameCutColors.accentBright,
                    value: model.selectionEnd,
                    mediaDuration: model.duration,
                    visibleDuration: viewport.visibleDuration,
                    trackWidth: trackWidth,
                    onBegin: {
                        beginPointerInteraction()
                        model.beginTimelineScrubbing()
                    },
                    onChange: { value in
                        model.updateOutPoint(to: value, shouldSeek: false)
                        model.scrubTimeline(to: model.selectionEnd)
                    },
                    onEnd: { value in
                        model.updateOutPoint(to: value, shouldSeek: false)
                        model.endTimelineScrubbing(at: model.selectionEnd)
                    }
                )
                .position(
                    x: horizontalInset + viewport.x(for: model.selectionEnd, trackWidth: trackWidth),
                    y: 40
                )
            }

            if viewport.contains(model.currentTime, tolerance: frameTolerance) {
                Playhead()
                    .position(
                        x: horizontalInset + viewport.x(for: model.currentTime, trackWidth: trackWidth),
                        y: 41
                    )
                    .allowsHitTesting(false)
            }

            if viewport.effectiveZoom > 1.001, model.isGeneratingDetailThumbnails {
                ProgressView()
                    .controlSize(.mini)
                    .tint(FrameCutColors.accentBright)
                    .padding(5)
                    .background(Color.black.opacity(0.62))
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .offset(x: horizontalInset + trackWidth - 30, y: 12)
            }
        }
        .help("拖动定位；使用鼠标滚轮或触控板双指捏合可缩放")
    }

    @ViewBuilder
    private func overviewTrack(
        viewport: TimelineViewport,
        horizontalInset: CGFloat,
        trackWidth: CGFloat
    ) -> some View {
        let overviewHeight: CGFloat = 18
        let mediaDuration = max(viewport.mediaDuration, 0.000_001)
        let windowStartX = horizontalInset + CGFloat(viewport.start / mediaDuration) * trackWidth
        let windowEndX = horizontalInset + CGFloat(viewport.end / mediaDuration) * trackWidth
        let playheadX = horizontalInset
            + CGFloat(model.currentTime / mediaDuration) * trackWidth

        ZStack(alignment: .topLeading) {
            filmstrip(
                width: trackWidth,
                height: overviewHeight,
                thumbnails: model.timelineThumbnails
            )
            .frame(width: trackWidth, height: overviewHeight)
            .offset(x: horizontalInset, y: 2)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

            Rectangle()
                .fill(Color.black.opacity(0.58))
                .frame(width: max(0, windowStartX - horizontalInset), height: overviewHeight)
                .offset(x: horizontalInset, y: 2)

            Rectangle()
                .fill(Color.black.opacity(0.58))
                .frame(
                    width: max(0, horizontalInset + trackWidth - windowEndX),
                    height: overviewHeight
                )
                .offset(x: windowEndX, y: 2)

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(FrameCutColors.accentBright.opacity(0.9), lineWidth: 1.5)
                .frame(width: max(3, windowEndX - windowStartX), height: overviewHeight)
                .offset(x: windowStartX, y: 2)

            Rectangle()
                .fill(Color.white.opacity(0.95))
                .frame(width: 1, height: overviewHeight + 2)
                .offset(x: min(max(horizontalInset, playheadX), horizontalInset + trackWidth), y: 1)

            Text("总览")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.78))
                .padding(.horizontal, 4)
                .frame(height: 14)
                .background(Color.black.opacity(0.58))
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                .offset(x: horizontalInset + 4, y: 4)
                .allowsHitTesting(false)

            Color.clear
                .contentShape(Rectangle())
                .frame(width: trackWidth, height: overviewHeight)
                .offset(x: horizontalInset, y: 2)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            recenterOverview(
                                at: value.location.x,
                                viewport: viewport,
                                trackWidth: trackWidth
                            )
                        }
                )
        }
        .help("全片总览：放大后拖动可平移精细轨道")
        .accessibilityLabel("全片时间线总览")
    }

    @ViewBuilder
    private func filmstrip(
        width: CGFloat,
        height: CGFloat,
        thumbnails: [TimelineThumbnail]
    ) -> some View {
        if thumbnails.isEmpty {
            ZStack {
                FrameCutColors.elevated
                HStack(spacing: 1) {
                    ForEach(0..<12, id: \.self) { index in
                        ZStack {
                            Rectangle()
                                .fill(index.isMultiple(of: 2) ? Color.white.opacity(0.025) : Color.clear)
                            Image(systemName: "film")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.07))
                        }
                        .frame(width: width / 12, height: height)
                    }
                }
            }
        } else {
            HStack(spacing: 1) {
                ForEach(thumbnails) { thumbnail in
                    Image(nsImage: thumbnail.image)
                        .resizable()
                        .scaledToFill()
                        .frame(
                            width: max(
                                1,
                                (width - CGFloat(thumbnails.count - 1)) / CGFloat(thumbnails.count)
                            ),
                            height: height
                        )
                        .clipped()
                }
            }
            .background(FrameCutColors.elevated)
        }
    }

    private func displayedKeyframes(in viewport: TimelineViewport) -> [Double] {
        let visible = model.keyframeTimes.filter { viewport.contains($0) }
        guard visible.count > 80 else { return visible }
        let step = max(1, visible.count / 80)
        return stride(from: 0, to: visible.count, by: step).map { visible[$0] }
    }

    private func recenterOverview(
        at x: CGFloat,
        viewport: TimelineViewport,
        trackWidth: CGFloat
    ) {
        guard viewport.effectiveZoom > 1.001, trackWidth > 0 else { return }
        let fraction = Double(min(max(0, x), trackWidth) / trackWidth)
        let requestedCenter = fraction * viewport.mediaDuration
        center = TimelineViewport.clampedCenter(
            requestedCenter,
            mediaDuration: viewport.mediaDuration,
            zoom: viewport.effectiveZoom
        )
    }

    private func normalizeZoom(maximumZoom: Double, mediaDuration: Double) {
        let normalizedZoom = min(max(1, zoom), maximumZoom)
        if abs(normalizedZoom - zoom) > 0.000_1 {
            zoom = normalizedZoom
        }
        center = TimelineViewport.clampedCenter(
            center,
            mediaDuration: mediaDuration,
            zoom: normalizedZoom
        )
    }

    private func applyInitialZoomIfNeeded(
        mediaDuration: Double,
        trackWidth: CGFloat,
        maximumZoom: Double
    ) {
        guard !didApplyInitialZoom,
              model.canEdit,
              mediaDuration > 0.001,
              trackWidth > 1 else { return }

        didApplyInitialZoom = true
        let onePointPerFrameZoom = mediaDuration * model.framesPerSecond / Double(trackWidth)
        let recommendedZoom = min(maximumZoom, max(1, onePointPerFrameZoom))
        guard recommendedZoom > 1.25 else {
            zoom = 1
            center = mediaDuration / 2
            return
        }

        zoom = recommendedZoom
        center = TimelineViewport.clampedCenter(
            model.currentTime,
            mediaDuration: mediaDuration,
            zoom: recommendedZoom
        )
    }

    private func refreshDetailThumbnails(for viewport: TimelineViewport) {
        if viewport.effectiveZoom <= 1.001 {
            model.clearDetailTimelineThumbnails()
            return
        }
        model.requestDetailTimelineThumbnails(
            startTime: viewport.start,
            endTime: viewport.end,
            count: 12
        )
    }

    private func beginPointerInteraction() {
        if !isPointerInteracting {
            isPointerInteracting = true
        }
    }

    private func magnifyGesture(
        mediaDuration: Double,
        maximumZoom: Double
    ) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if magnificationBaseZoom == nil {
                    magnificationBaseZoom = zoom
                }
                let base = magnificationBaseZoom ?? zoom
                let targetZoom = min(maximumZoom, max(1, base * Double(value.magnification)))
                zoom = targetZoom
                center = TimelineViewport.clampedCenter(
                    center,
                    mediaDuration: mediaDuration,
                    zoom: targetZoom
                )
            }
            .onEnded { _ in
                magnificationBaseZoom = nil
            }
    }

    private func handleScrollWheel(
        event: NSEvent,
        locationX: CGFloat,
        viewport: TimelineViewport,
        horizontalInset: CGFloat,
        trackWidth: CGFloat,
        maximumZoom: Double
    ) {
        guard model.canEdit, trackWidth > 0 else { return }

        let targetZoom = TimelineZoomProjection.targetZoom(
            currentZoom: viewport.effectiveZoom,
            scrollDelta: Double(event.scrollingDeltaY),
            hasPreciseScrollingDeltas: event.hasPreciseScrollingDeltas,
            maximumZoom: maximumZoom
        )
        guard abs(targetZoom - viewport.effectiveZoom) > 0.000_1 else { return }

        let trackX = min(max(0, locationX - horizontalInset), trackWidth)
        let anchorFraction = Double(trackX / trackWidth)
        let anchorTime = viewport.time(at: trackX, trackWidth: trackWidth)
        let targetCenter = TimelineZoomProjection.centerPreservingAnchor(
            anchorTime: anchorTime,
            anchorFraction: anchorFraction,
            mediaDuration: viewport.mediaDuration,
            targetZoom: targetZoom
        )

        zoom = targetZoom
        center = targetCenter
    }
}

private struct TimelineScrollWheelCapture: NSViewRepresentable {
    let onScroll: (NSEvent, CGPoint) -> Void

    func makeNSView(context: Context) -> TimelineScrollWheelTrackingView {
        let view = TimelineScrollWheelTrackingView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: TimelineScrollWheelTrackingView, context: Context) {
        nsView.onScroll = onScroll
    }

    static func dismantleNSView(
        _ nsView: TimelineScrollWheelTrackingView,
        coordinator: ()
    ) {
        nsView.stopMonitoring()
    }
}

private final class TimelineScrollWheelTrackingView: NSView {
    var onScroll: ((NSEvent, CGPoint) -> Void)?
    private var eventMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopMonitoring()
        if window != nil {
            startMonitoring()
        }
    }

    func stopMonitoring() {
        guard let eventMonitor else { return }
        NSEvent.removeMonitor(eventMonitor)
        self.eventMonitor = nil
    }

    private func startMonitoring() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self,
                  let window = self.window,
                  let eventWindow = event.window,
                  eventWindow === window,
                  !self.isHidden,
                  abs(event.scrollingDeltaY) > 0.000_1 else { return event }

            let localPoint = self.convert(event.locationInWindow, from: nil)
            guard self.bounds.contains(localPoint) else { return event }

            self.onScroll?(event, localPoint)
            return nil
        }
    }

    deinit {
        stopMonitoring()
    }
}

private struct TimelineHandle: View {
    let label: String
    let color: Color
    let value: Double
    let mediaDuration: Double
    let visibleDuration: Double
    let trackWidth: CGFloat
    let onBegin: () -> Void
    let onChange: (Double) -> Void
    let onEnd: (Double) -> Void

    @State private var dragOrigin: Double?

    var body: some View {
        VStack(spacing: 0) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)
                .frame(width: 18, height: 17)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            Rectangle()
                .fill(color)
                .frame(width: 3, height: 61)
                .shadow(color: color.opacity(0.35), radius: 3)
        }
        .frame(width: 22, height: 78)
        .contentShape(Rectangle())
        .gesture(
            // The handle moves while dragging. Global coordinates keep the reported
            // translation anchored to the pointer instead of the moving handle.
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { gesture in
                    if dragOrigin == nil {
                        dragOrigin = value
                        onBegin()
                    }
                    let origin = dragOrigin ?? value
                    onChange(TimelineDragProjection.time(
                        origin: origin,
                        translation: gesture.translation.width,
                        visibleDuration: visibleDuration,
                        trackWidth: trackWidth,
                        mediaDuration: mediaDuration
                    ))
                }
                .onEnded { gesture in
                    let origin = dragOrigin ?? value
                    let finalValue = TimelineDragProjection.time(
                        origin: origin,
                        translation: gesture.translation.width,
                        visibleDuration: visibleDuration,
                        trackWidth: trackWidth,
                        mediaDuration: mediaDuration
                    )
                    onChange(finalValue)
                    onEnd(finalValue)
                    dragOrigin = nil
                }
        )
        .help(label == "I" ? "拖动入点" : "拖动出点")
    }
}

private struct Playhead: View {
    var body: some View {
        VStack(spacing: -1) {
            Image(systemName: "triangle.fill")
                .font(.system(size: 8))
                .rotationEffect(.degrees(180))
            Rectangle()
                .frame(width: 1.5, height: 69)
        }
        .foregroundStyle(Color.white)
        .shadow(color: Color.black.opacity(0.7), radius: 1)
        .frame(width: 12, height: 78)
    }
}
