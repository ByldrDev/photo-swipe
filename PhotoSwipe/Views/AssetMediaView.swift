import SwiftUI

/// The current card's content: a still image, or for videos the poster frame
/// with an inline looping player layered on top once it is ready.
struct AssetMediaView: View {
    @Environment(AppModel.self) private var model
    let assetID: String
    let targetSize: CGSize

    @State private var videoPlayer: AssetVideoPlayer?
    @Environment(\.scenePhase) private var scenePhase

    private var isVideo: Bool { model.library.isVideo(assetID) }

    var body: some View {
        ZStack {
            AssetImageView(assetID: assetID, targetSize: targetSize)
            if isVideo, let videoPlayer {
                switch videoPlayer.state {
                case .ready:
                    PlayerLayerView(player: videoPlayer.player)
                        .transition(.opacity)
                        .accessibilityIdentifier("videoPlayer")
                case .loading(let progress):
                    loadingBadge(progress)
                case .failed(let message):
                    failureBadge(message, retry: videoPlayer.retry)
                case .idle:
                    EmptyView()
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if isVideo, let videoPlayer {
                Button {
                    videoPlayer.isMuted.toggle()
                    Haptics.light()
                } label: {
                    Image(systemName: videoPlayer.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.body.weight(.semibold))
                        .frame(width: 40, height: 40)
                        .background(.black.opacity(0.55), in: Circle())
                        .foregroundStyle(.white)
                }
                .padding(.trailing, 16)
                .padding(.bottom, 110)
                .accessibilityIdentifier("muteButton")
                .accessibilityLabel(videoPlayer.isMuted ? "Unmute" : "Mute")
            }
        }
        .onAppear { startIfVideo() }
        .onChange(of: assetID) { _, _ in startIfVideo() }
        .onChange(of: scenePhase) { _, phase in
            phase == .active ? videoPlayer?.play() : videoPlayer?.pause()
        }
        .onDisappear { videoPlayer?.stop() }
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
        guard isVideo else {
            videoPlayer?.stop()
            return
        }
        if videoPlayer == nil { videoPlayer = AssetVideoPlayer(library: model.library) }
        videoPlayer?.load(id: assetID)
    }
}
