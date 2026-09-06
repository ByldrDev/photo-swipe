import SwiftUI

/// The fullscreen deck. Right = keep, left = delete, up = hide.
struct SwipeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var offset: CGSize = .zero
    @State private var isAnimatingOut = false
    @State private var showReview = false

    private let distanceThreshold: CGFloat = 110
    private let velocityThreshold: CGFloat = 900

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                if let session = model.session {
                    if let currentID = session.currentID {
                        deck(session: session, currentID: currentID, size: geo.size)
                    } else {
                        finished(session: session)
                    }
                }

                VStack {
                    topBar
                    Spacer()
                    if model.session?.currentID != nil {
                        bottomBar
                    }
                }
                .padding()
            }
            .onAppear { model.prefetch(targetSize: geo.size) }
            .onChange(of: model.session?.currentID) { _, _ in model.prefetch(targetSize: geo.size) }
        }
        .statusBarHidden()
        .sheet(isPresented: $showReview) {
            NavigationStack { ReviewView() }
        }
    }

    // MARK: - Deck

    @ViewBuilder
    private func deck(session: SwipeSession, currentID: String, size: CGSize) -> some View {
        // Next card sits underneath so the reveal is instant.
        if let nextID = session.neighborIDs(ahead: 1, behind: 0).dropFirst().first {
            AssetImageView(assetID: nextID, targetSize: size)
                .frame(width: size.width, height: size.height)
                .ignoresSafeArea()
        }

        AssetMediaView(assetID: currentID, targetSize: size)
            .frame(width: size.width, height: size.height)
            .ignoresSafeArea()
            .overlay(decisionOverlay)
            .offset(offset)
            .rotationEffect(.degrees(Double(offset.width / size.width) * 12), anchor: .bottom)
            .gesture(dragGesture(size: size))
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
            }
            .allowsHitTesting(false)
        }
    }

    private func dragGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard !isAnimatingOut else { return }
                offset = value.translation
            }
            .onEnded { value in
                guard !isAnimatingOut else { return }
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
            isAnimatingOut = false
        }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.title3.weight(.semibold))
                    .padding(10)
                    .background(.black.opacity(0.5), in: Circle())
            }
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
            .accessibilityIdentifier("reviewButton")
            .accessibilityLabel("Review")
        }
        .foregroundStyle(.white)
    }

    private var bottomBar: some View {
        HStack(spacing: 18) {
            Button { model.undo() } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.title2.weight(.semibold))
                    .frame(width: 52, height: 52)
                    .background(.black.opacity(0.5), in: Circle())
            }
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
            flyOut(verdict, size: UIScreen.main.bounds.size)
        } label: {
            Image(systemName: verdict.systemImage)
                .font(.title2.weight(.bold))
                .frame(width: 56, height: 56)
                .background(verdict.color.opacity(0.85), in: Circle())
        }
        .accessibilityIdentifier("\(verdict.rawValue)Button")
        .accessibilityLabel(verdict.label.capitalized)
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
