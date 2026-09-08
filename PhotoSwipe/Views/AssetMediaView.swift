import SwiftUI

/// The current card's content: a still image, or for videos the poster frame
/// with an inline looping player layered on top once it is ready.
///
/// The player is shared (owned by `AppModel`) so the transport controls that
/// live in the deck's chrome can drive the same instance.
struct AssetMediaView: View {
    @Environment(AppModel.self) private var model
    let assetID: String
    let targetSize: CGSize
    let player: AssetVideoPlayer

    @Environment(\.scenePhase) private var scenePhase

    private var isVideo: Bool { model.library.isVideo(assetID) }

    var body: some View {
        ZStack {
            AssetImageView(assetID: assetID, targetSize: targetSize, showsBackdrop: true)
            if isVideo, player.loadedID == assetID {
                switch player.state {
                case .ready:
                    PlayerLayerView(player: player.player)
                        .transition(.opacity)
                        .accessibilityIdentifier("videoPlayer")
                case .loading(let progress):
                    loadingBadge(progress)
                case .failed(let message):
                    failureBadge(message, retry: player.retry)
                case .idle:
                    EmptyView()
                }
            }
        }
        .onAppear { startIfVideo() }
        .onChange(of: assetID) { _, _ in startIfVideo() }
        .onChange(of: scenePhase) { _, phase in
            phase == .active ? player.play() : player.pause()
        }
        .onDisappear {
            // Cards are recreated per asset and SwiftUI does not order the old
            // card's disappear against the new card's appear. Only stop the
            // player if it is still showing *this* card's clip.
            if player.loadedID == assetID { player.stop() }
        }
    }

    private func loadingBadge(_ progress: Double?) -> some View {
        VStack(spacing: 10) {
            if let progress, progress > 0 {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(width: 160)
                Text("Downloading from iCloud \(Int(progress * 100))%")
            } else {
                ProgressView().tint(.white)
                Text(progress == nil ? "Loading video…" : "Downloading from iCloud…")
            }
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.white)
        .padding(14)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        .allowsHitTesting(false)
        .accessibilityIdentifier("videoLoading")
    }

    private func failureBadge(_ message: String, retry: @escaping () -> Void) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").font(.title2)
            Text(message).multilineTextAlignment(.center)
            Button("Try again", action: retry).buttonStyle(.bordered).tint(.white)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: 280)
        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("videoError")
    }

    private func startIfVideo() {
        if isVideo {
            player.load(id: assetID)
        } else if player.loadedID != nil {
            player.stop()
        }
    }
}
