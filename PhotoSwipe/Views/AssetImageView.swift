import SwiftUI
import Photos

/// Fullscreen-capable image for a single asset with a video duration badge.
struct AssetImageView: View {
    @Environment(AppModel.self) private var model
    let assetID: String
    var targetSize: CGSize
    var contentMode: ContentMode = .fit

    @State private var loader: AssetImageLoader?

    var body: some View {
        ZStack {
            if let image = loader?.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else {
                Rectangle().fill(Color(white: 0.12))
                ProgressView().tint(.white)
            }
            if let asset = model.library.asset(for: assetID), asset.mediaType == .video {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Label(durationText(asset.duration), systemImage: "video.fill")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.black.opacity(0.6), in: Capsule())
                            .padding(8)
                    }
                }
            }
        }
        .onAppear { load() }
        .onChange(of: assetID) { _, _ in load() }
        .onDisappear { loader?.cancel() }
    }

    private func load() {
        if loader == nil { loader = AssetImageLoader(library: model.library) }
        let scale = UIScreen.main.scale
        loader?.load(id: assetID, targetSize: CGSize(width: targetSize.width * scale, height: targetSize.height * scale))
    }

    private func durationText(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Square grid thumbnail.
struct AssetThumbnail: View {
    let assetID: String
    var side: CGFloat = 100

    var body: some View {
        AssetImageView(assetID: assetID, targetSize: CGSize(width: side, height: side), contentMode: .fill)
            .frame(width: side, height: side)
            .clipped()
    }
}
