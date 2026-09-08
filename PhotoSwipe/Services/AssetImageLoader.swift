import Foundation
import Photos
import Observation

/// Loads (and re-loads on id change) a single asset image through the service,
/// surfacing the degraded preview first so the swipe deck never shows a blank.
@MainActor
@Observable
final class AssetImageLoader {
    private(set) var image: PlatformImage?
    private(set) var isDegraded = true
    private(set) var loadedID: String?

    @ObservationIgnored private var requestID: PHImageRequestID?
    @ObservationIgnored private let library: PhotoLibraryService

    init(library: PhotoLibraryService) {
        self.library = library
    }

    func load(id: String, targetSize: CGSize) {
        guard id != loadedID else { return }
        library.cancelImageRequest(requestID)
        loadedID = id
        image = nil
        isDegraded = true
        requestID = library.requestImage(for: id, targetSize: targetSize) { [weak self] image, degraded in
            guard let self, self.loadedID == id else { return }
            if let image {
                // Never replace a full-quality image with a late degraded one.
                if self.isDegraded || !degraded {
                    self.image = image
                    self.isDegraded = degraded
                }
            }
        }
    }

    func cancel() {
        library.cancelImageRequest(requestID)
        requestID = nil
    }
}
