import SwiftUI
import Photos

/// Fullscreen-capable image for a single asset with a video duration badge.
///
/// With `showsBackdrop` the letterboxed area around a non-full-bleed photo is
/// filled with a blurred, darkened copy of the same photo instead of showing
/// whatever card is stacked underneath.
struct AssetImageView: View {
    @Environment(AppModel.self) private var model
    let assetID: String
    var targetSize: CGSize
    var contentMode: ContentMode = .fit
    var showsBackdrop = false

    @State private var loader: AssetImageLoader?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ZStack {
            if let image = loader?.image {
                if showsBackdrop {
                    backdrop(image)
                }
                Image(platformImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else {
                Rectangle().fill(Color(white: 0.12))
                ProgressView().tint(.white)
            }
            // Deck cards (the ones with a backdrop) get a transport strip with
            // the duration instead, so the badge is thumbnail-only.
            if !showsBackdrop, let asset = model.library.asset(for: assetID), asset.mediaType == .video {
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
        .clipped()
        .onAppear { load() }
        .onChange(of: assetID) { _, _ in load() }
        .onDisappear { loader?.cancel() }
    }

    /// Scaled up past the edges so the blur has no transparent fringe, then
    /// clipped by the parent ZStack.
    private func backdrop(_ image: PlatformImage) -> some View {
        Image(platformImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: targetSize.width, height: targetSize.height)
            .clipped()
            .scaleEffect(1.2)
            .blur(radius: 36, opaque: true)
            .overlay(Color.black.opacity(0.5))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func load() {
        if loader == nil { loader = AssetImageLoader(library: model.library) }
        loader?.load(id: assetID, targetSize: CGSize(width: targetSize.width * displayScale, height: targetSize.height * displayScale))
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
