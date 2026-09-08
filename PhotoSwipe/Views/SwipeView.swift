import SwiftUI

/// The fullscreen deck. Right = keep, left = delete, up = hide.
/// Pinch (or double-tap) zooms the current card; while zoomed, one-finger
/// drags pan instead of swiping, and tapping the left/right edge strips
/// stands in for the swipe. The arrow keys, ⌘Z, space and M drive the same
/// actions from a keyboard (the primary input on macOS).
struct SwipeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.displayScale) private var displayScale

    @State private var offset: CGSize = .zero
    @State private var isAnimatingOut = false
    @State private var showReview = false
    /// Size of the deck area, kept so the action buttons can fly the card out.
    @State private var deckSize: CGSize = .zero

    // Zoom state for the current card. Reset whenever the card changes.
    @State private var zoomScale: CGFloat = 1
    @State private var zoomOffset: CGSize = .zero
    /// Scale/offset at the moment a pinch began; nil when not pinching.
    @State private var magnifyStart: (scale: CGFloat, offset: CGSize)?
    /// Zoom offset and drag translation when a pan began; nil when not panning.
    @State private var panStart: (offset: CGSize, translation: CGSize)?
    /// Set when a pinch happens mid-drag so the rest of that drag is not
    /// mistaken for a swipe.
    @State private var dragTaintedByPinch = false

    private let distanceThreshold: CGFloat = 110
    private let velocityThreshold: CGFloat = 900
    private let maxZoom: CGFloat = 6
    private let doubleTapZoom: CGFloat = 2.5
    /// Width of the tap-to-decide strips shown along each edge while zoomed.
    private let hotZoneWidth: CGFloat = 64

    private var isZoomed: Bool { zoomScale > 1.001 }

    var body: some View {
        ZStack {
            // Cards fill the whole screen (under the notch and home indicator)
            // so the blurred backdrop is edge to edge; the chrome below stays
            // inside the safe area.
            GeometryReader { geo in
                ZStack {
                    Color.black
                    if let session = model.session, let currentID = session.currentID {
                        deck(session: session, currentID: currentID, size: geo.size)
                    }
                }
                .onAppear {
                    deckSize = geo.size
                    model.prefetch(targetSize: geo.size, scale: displayScale)
                }
                .onChange(of: geo.size) { _, size in deckSize = size }
                .onChange(of: model.session?.currentID) { _, _ in
                    resetZoom(animated: false)
                    model.prefetch(targetSize: geo.size, scale: displayScale)
                }
            }
            .ignoresSafeArea()

            if let session = model.session, session.currentID == nil {
                finished(session: session)
            }

            VStack(spacing: 0) {
                topBar
                if let currentID = model.session?.currentID,
                   let burst = model.library.burstInfo(for: currentID) {
                    HStack {
                        Spacer()
                        burstBadge(burst)
                    }
                    .padding(.top, 10)
                }
                Spacer()
                if let currentID = model.session?.currentID {
                    if model.library.isVideo(currentID) {
                        VideoControlsView(player: model.videoPlayer)
                            .padding(.bottom, 14)
                    }
                    bottomBar
                    if Platform.isMac { keyboardHints }
                }
            }
            .padding()
        }
        .hidesStatusBar()
        .sheet(isPresented: $showReview) {
            NavigationStack { ReviewView() }
                .sheetFrame()
        }
    }

    // MARK: - Deck

    @ViewBuilder
    private func deck(session: SwipeSession, currentID: String, size: CGSize) -> some View {
        // Next card sits underneath so the reveal is instant.
        if let nextID = session.neighborIDs(ahead: 1, behind: 0).dropFirst().first {
            AssetImageView(assetID: nextID, targetSize: size, showsBackdrop: true)
                .frame(width: size.width, height: size.height)
        }

        ZStack {
            AssetMediaView(assetID: currentID, targetSize: size, player: model.videoPlayer)
                .frame(width: size.width, height: size.height)
                .scaleEffect(zoomScale)
                .offset(zoomOffset)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .overlay(hotZones)
        .overlay(decisionOverlay)
        .contentShape(Rectangle())
        .offset(offset)
        .rotationEffect(.degrees(Double(offset.width / size.width) * 12), anchor: .bottom)
        .gesture(dragGesture(size: size))
        .simultaneousGesture(magnifyGesture(size: size))
        .simultaneousGesture(tapGestures(size: size))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("swipeCard")
        .id(currentID)
    }

    private var pendingVerdict: SwipeDecision? {
        let dx = offset.width, dy = offset.height
        if -dy > abs(dx), -dy > 30 { return .hide }
        if dx > 30 { return .keep }
        if dx < -30 { return .delete }
        return nil
    }

    private var dragProgress: Double {
        let magnitude = max(abs(offset.width), -offset.height)
        return min(1, Double(magnitude / distanceThreshold))
    }

    @ViewBuilder
    private var decisionOverlay: some View {
        if let verdict = pendingVerdict {
            ZStack {
                verdict.color.opacity(0.25 * dragProgress)
                Label(verdict.label, systemImage: verdict.systemImage)
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundStyle(verdict.color)
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(verdict.color, lineWidth: 5))
                    .rotationEffect(.degrees(verdict == .keep ? -15 : verdict == .delete ? 15 : 0))
                    .opacity(dragProgress)
                    .scaleEffect(0.8 + 0.2 * dragProgress)
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: verdict == .keep ? .topLeading : verdict == .delete ? .topTrailing : .top)
                    .padding(verdict == .hide ? 80 : 40)
                    .padding(.top, 60)
            }
            .allowsHitTesting(false)
        }
    }

    /// Edge strips that appear while zoomed: tap left to delete, right to keep.
    /// Purely visual; the taps are handled by `tapGestures`.
    private var hotZones: some View {
        // Conditional (not opacity 0) so the strips leave the accessibility
        // tree when not zoomed; the animation is scoped to this wrapper.
        ZStack {
            if isZoomed {
                HStack {
                    hotZone(.delete, edge: .leading)
                    Spacer()
                    hotZone(.keep, edge: .trailing)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: isZoomed)
        .allowsHitTesting(false)
    }

    private func hotZone(_ verdict: SwipeDecision, edge: HorizontalEdge) -> some View {
        LinearGradient(
            colors: [verdict.color.opacity(0.45), verdict.color.opacity(0)],
            startPoint: edge == .leading ? .leading : .trailing,
            endPoint: edge == .leading ? .trailing : .leading
        )
        .frame(width: hotZoneWidth)
        .overlay {
            Image(systemName: verdict.systemImage)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .padding(10)
                .background(verdict.color.opacity(0.85), in: Circle())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("\(verdict.rawValue)HotZone")
        .accessibilityLabel("Tap to \(verdict.label.lowercased())")
    }

    // MARK: - Swipe / pan

    private func dragGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard !isAnimatingOut, magnifyStart == nil else { return }
                if isZoomed {
                    // Pan. Measure from where the pan began so a drag that
                    // started as a pinch doesn't jump.
                    let start = panStart ?? (zoomOffset, value.translation)
                    if panStart == nil { panStart = start }
                    let proposed = CGSize(width: start.offset.width + value.translation.width - start.translation.width,
                                          height: start.offset.height + value.translation.height - start.translation.height)
                    zoomOffset = clampedZoomOffset(proposed, scale: zoomScale, size: size)
                } else if !dragTaintedByPinch {
                    offset = value.translation
                }
            }
            .onEnded { value in
                defer {
                    panStart = nil
                    dragTaintedByPinch = false
                }
                guard !isAnimatingOut else { return }
                if isZoomed || panStart != nil || dragTaintedByPinch {
                    if offset != .zero {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { offset = .zero }
                    }
                    return
                }
                let t = value.translation
                let v = value.velocity
                let verdict: SwipeDecision?
                if -t.height > abs(t.width), (-t.height > distanceThreshold || -v.height > velocityThreshold) {
                    verdict = .hide
                } else if t.width > distanceThreshold || v.width > velocityThreshold {
                    verdict = .keep
                } else if t.width < -distanceThreshold || v.width < -velocityThreshold {
                    verdict = .delete
                } else {
                    verdict = nil
                }
                if let verdict {
                    flyOut(verdict, size: size)
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { offset = .zero }
                }
            }
    }

    private func flyOut(_ verdict: SwipeDecision, size: CGSize) {
        isAnimatingOut = true
        Haptics.decision(verdict)
        let target: CGSize
        switch verdict {
        case .keep: target = CGSize(width: size.width * 1.5, height: offset.height)
        case .delete: target = CGSize(width: -size.width * 1.5, height: offset.height)
        case .hide: target = CGSize(width: offset.width, height: -size.height * 1.3)
        }
        withAnimation(.easeOut(duration: 0.22)) { offset = target }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.23) {
            model.decide(verdict)
            offset = .zero
            resetZoom(animated: false)
            isAnimatingOut = false
        }
    }

    // MARK: - Zoom

    private func magnifyGesture(size: CGSize) -> some Gesture {
        MagnifyGesture(minimumScaleDelta: 0)
            .onChanged { value in
                guard !isAnimatingOut else { return }
                let start = magnifyStart ?? (zoomScale, zoomOffset)
                if magnifyStart == nil {
                    magnifyStart = start
                    dragTaintedByPinch = true
                    panStart = nil
                    if offset != .zero { offset = .zero }
                }
                // Rubber-band a little below 1× so pinching in feels alive.
                let newScale = min(max(0.7, start.scale * value.magnification), maxZoom)
                let anchor = point(for: value.startAnchor, in: size)
                zoomOffset = offsetKeeping(anchor, fixedFrom: start.scale, to: newScale, startOffset: start.offset)
                zoomScale = newScale
            }
            .onEnded { _ in
                magnifyStart = nil
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    if zoomScale < 1.05 {
                        zoomScale = 1
                        zoomOffset = .zero
                    } else {
                        zoomOffset = clampedZoomOffset(zoomOffset, scale: zoomScale, size: size)
                    }
                }
            }
    }

    /// Double-tap toggles zoom. A single tap does nothing unless zoomed, when a
    /// tap inside the left/right edge strip decides delete/keep (the swipe is
    /// busy panning). Double-tap takes precedence, so single taps land after
    /// the double-tap window closes.
    private func tapGestures(size: CGSize) -> some Gesture {
        let doubleTap = SpatialTapGesture(count: 2)
            .onEnded { value in
                guard !isAnimatingOut else { return }
                if isZoomed {
                    resetZoom(animated: true)
                } else {
                    let anchor = CGPoint(x: value.location.x - size.width / 2, y: value.location.y - size.height / 2)
                    let target = offsetKeeping(anchor, fixedFrom: 1, to: doubleTapZoom, startOffset: .zero)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        zoomScale = doubleTapZoom
                        zoomOffset = clampedZoomOffset(target, scale: doubleTapZoom, size: size)
                    }
                }
            }
        let edgeTap = SpatialTapGesture(count: 1)
            .onEnded { value in
                guard isZoomed, !isAnimatingOut else { return }
                if value.location.x < hotZoneWidth {
                    flyOut(.delete, size: size)
                } else if value.location.x > size.width - hotZoneWidth {
                    flyOut(.keep, size: size)
                }
            }
        return ExclusiveGesture(doubleTap, edgeTap)
    }

    private func resetZoom(animated: Bool) {
        magnifyStart = nil
        panStart = nil
        dragTaintedByPinch = false
        guard isZoomed || zoomOffset != .zero else { return }
        if animated {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                zoomScale = 1
                zoomOffset = .zero
            }
        } else {
            zoomScale = 1
            zoomOffset = .zero
        }
    }

    /// A unit-point anchor as a point relative to the card's centre.
    private func point(for anchor: UnitPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: (anchor.x - 0.5) * size.width, y: (anchor.y - 0.5) * size.height)
    }

    /// The offset that keeps the content under `p` (card-centre coordinates)
    /// stationary while the scale goes from `s0` to `s1`. The card transform is
    /// `x' = s·x + o`, so the fixed content point is `(p − o0)/s0`.
    private func offsetKeeping(_ p: CGPoint, fixedFrom s0: CGFloat, to s1: CGFloat, startOffset o0: CGSize) -> CGSize {
        let ratio = s1 / s0
        return CGSize(width: p.x - ratio * (p.x - o0.width),
                      height: p.y - ratio * (p.y - o0.height))
    }

    /// Keeps the zoomed content covering the card: no panning into empty space
    /// on an axis where the scaled content is larger than the card, and centred
    /// on any axis where it is smaller.
    private func clampedZoomOffset(_ proposed: CGSize, scale: CGFloat, size: CGSize) -> CGSize {
        guard let currentID = model.session?.currentID else { return proposed }
        let content = fittedContentSize(for: currentID, in: size)
        let maxX = max(0, (content.width * scale - size.width) / 2)
        let maxY = max(0, (content.height * scale - size.height) / 2)
        return CGSize(width: min(max(proposed.width, -maxX), maxX),
                      height: min(max(proposed.height, -maxY), maxY))
    }

    /// Aspect-fit size of the asset within the card, from PhotoKit's pixel
    /// dimensions (available before the image is decoded).
    private func fittedContentSize(for id: String, in size: CGSize) -> CGSize {
        guard let pixels = model.library.pixelSize(for: id), pixels.width > 0, pixels.height > 0 else { return size }
        let scale = min(size.width / pixels.width, size.height / pixels.height)
        return CGSize(width: pixels.width * scale, height: pixels.height * scale)
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack {
            Button {
                // Also dismisses the iOS full-screen cover, which is bound to this flag.
                model.isSwiping = false
            } label: {
                Image(systemName: "chevron.down")
                    .font(.title3.weight(.semibold))
                    .padding(10)
                    .background(.black.opacity(0.5), in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            .accessibilityIdentifier("closeButton")
            .accessibilityLabel("Close")

            Spacer()

            if let session = model.session {
                Text("\(session.position.formatted()) / \(session.totalCount.formatted())")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.black.opacity(0.5), in: Capsule())
                    .accessibilityIdentifier("progressLabel")
            }

            Spacer()

            Button {
                showReview = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checklist")
                    if let pending = model.session?.pendingCount, pending > 0 {
                        Text(pending.formatted())
                            .font(.subheadline.monospacedDigit().weight(.bold))
                            .accessibilityIdentifier("pendingCount")
                    }
                }
                .font(.title3.weight(.semibold))
                .padding(10)
                .background(.black.opacity(0.5), in: Capsule())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("r", modifiers: .command)
            .accessibilityIdentifier("reviewButton")
            .accessibilityLabel("Review")
        }
        .foregroundStyle(.white)
    }

    /// "Burst 3/12", with a star when Photos or the user picked this frame.
    private func burstBadge(_ burst: BurstInfo) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "square.stack.3d.down.right.fill")
            Text("Burst \(burst.position)/\(burst.count)")
            if burst.isPicked {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .accessibilityLabel("Picked")
            }
        }
        .font(.subheadline.monospacedDigit().weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.black.opacity(0.5), in: Capsule())
        .accessibilityIdentifier("burstBadge")
    }

    private var bottomBar: some View {
        HStack(spacing: 18) {
            Button { model.undo() } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.title2.weight(.semibold))
                    .frame(width: 52, height: 52)
                    .background(.black.opacity(0.5), in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!(model.session?.canUndo ?? false))
            .opacity((model.session?.canUndo ?? false) ? 1 : 0.35)
            .accessibilityIdentifier("undoButton")
            .accessibilityLabel("Undo")

            Spacer()

            actionButton(.delete)
            actionButton(.hide)
            actionButton(.keep)
        }
        .foregroundStyle(.white)
    }

    private func actionButton(_ verdict: SwipeDecision) -> some View {
        Button {
            guard !isAnimatingOut else { return }
            flyOut(verdict, size: deckSize)
        } label: {
            Image(systemName: verdict.systemImage)
                .font(.title2.weight(.bold))
                .frame(width: 56, height: 56)
                .background(verdict.color.opacity(0.85), in: Circle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(Self.key(for: verdict), modifiers: [])
        .accessibilityIdentifier("\(verdict.rawValue)Button")
        .accessibilityLabel(verdict.label.capitalized)
    }

    private static func key(for verdict: SwipeDecision) -> KeyEquivalent {
        switch verdict {
        case .keep: return .rightArrow
        case .delete: return .leftArrow
        case .hide: return .upArrow
        }
    }

    /// Shown under the buttons on macOS, where the keyboard is the main input.
    private var keyboardHints: some View {
        HStack(spacing: 14) {
            hint("←", "delete")
            hint("↑", "hide")
            hint("→", "keep")
            hint("⌘Z", "undo")
            if let id = model.session?.currentID, model.library.isVideo(id) {
                hint("space", "play/pause")
                hint("M", "mute")
            }
            hint("double-click", "zoom")
            hint("esc", "close")
        }
        .font(.caption)
        .foregroundStyle(.white.opacity(0.8))
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.black.opacity(0.45), in: Capsule())
        .padding(.top, 10)
    }

    private func hint(_ key: String, _ action: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.caption.weight(.semibold).monospaced())
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
            Text(action)
        }
    }

    private func finished(session: SwipeSession) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "flag.checkered")
                .font(.system(size: 56))
            Text("You've reached the end")
                .font(.title2.weight(.bold))
            Text("\(session.deleteIDs.count.formatted()) to delete · \(session.hideIDs.count.formatted()) to hide · \(session.keepCount.formatted()) kept")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("finishedSummary")
            HStack {
                Button("Undo last") { model.undo() }
                    .buttonStyle(.bordered)
                    .disabled(!session.canUndo)
                Button("Review changes") { showReview = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(session.pendingCount == 0)
            }
            .padding(.top)
        }
        .foregroundStyle(.white)
        .padding()
    }
}
