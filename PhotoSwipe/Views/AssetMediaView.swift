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
            if isVideo, let videoPlayer, videoPlayer.isReady {
                PlayerLayerView(player: videoPlayer.player)
                    .transition(.opacity)
                    .accessibilityIdentifier("videoPlayer")
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

    private func startIfVideo() {
        guard isVideo else {
            videoPlayer?.stop()
            return
        }
        if videoPlayer == nil { videoPlayer = AssetVideoPlayer(library: model.library) }
        videoPlayer?.load(id: assetID)
    }
}
