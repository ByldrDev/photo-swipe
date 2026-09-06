import Foundation
import Photos
import AVFoundation
import UIKit
import Observation

/// Result of a batched commit to the photo library.
struct CommitResult: Equatable {
    var deletedCount: Int
    var hiddenCount: Int
}

enum PhotoLibraryError: LocalizedError {
    case notAuthorized
    case cancelled
    case underlying(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthorized: return "PhotoSwipe needs full access to your photo library. Enable it in Settings → Privacy → Photos."
        case .cancelled: return "Cancelled. Nothing was changed."
        case .underlying(let error): return error.localizedDescription
        }
    }
}

/// Thin wrapper around PhotoKit: authorization, a newest-first snapshot of the
/// library (images + videos, hidden excluded), cached image loading, and the
/// single batched `commit` that actually deletes/hides assets.
@MainActor
@Observable
final class PhotoLibraryService: NSObject {
    private(set) var authorizationStatus: PHAuthorizationStatus
    /// Asset local identifiers, newest → oldest. Feed straight into `SwipeSession`.
    private(set) var assetIDs: [String] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    /// Incremented whenever the library snapshot changes so views can react.
    private(set) var libraryVersion = 0

    @ObservationIgnored private var assetsByID: [String: PHAsset] = [:]
    @ObservationIgnored private var fetchResult: PHFetchResult<PHAsset>?
    @ObservationIgnored private let imageManager = PHCachingImageManager()
    @ObservationIgnored private var observing = false

    override init() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        super.init()
    }

    deinit {
        if observing { PHPhotoLibrary.shared().unregisterChangeObserver(self) }
    }

    // MARK: - Authorization

    /// True for both full and limited access. Limited access still lets the
    /// user triage the photos they picked.
    var hasAccess: Bool {
        authorizationStatus == .authorized || authorizationStatus == .limited
    }

    func requestAccess() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authorizationStatus = status
    }

    // MARK: - Library snapshot

    /// Fetches every non-hidden image/video, newest first, and builds the id map.
    /// Safe to call repeatedly; later calls refresh the snapshot.
    func loadLibrary() async {
        guard hasAccess else { return }
        isLoading = true
        defer { isLoading = false }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.includeHiddenAssets = false
        options.predicate = NSPredicate(
            format: "mediaType == %d OR mediaType == %d",
            PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue
        )
        let result = PHAsset.fetchAssets(with: options)

        // Enumerating tens of thousands of assets takes a moment; keep it off the main thread.
        let (ids, map) = await Task.detached(priority: .userInitiated) { () -> ([String], [String: PHAsset]) in
            var ids: [String] = []
            var map: [String: PHAsset] = [:]
            ids.reserveCapacity(result.count)
            map.reserveCapacity(result.count)
            result.enumerateObjects { asset, _, _ in
                ids.append(asset.localIdentifier)
                map[asset.localIdentifier] = asset
            }
            return (ids, map)
        }.value

        fetchResult = result
        assetsByID = map
        assetIDs = ids
        hasLoaded = true
        libraryVersion += 1

        if !observing {
            PHPhotoLibrary.shared().register(self)
            observing = true
        }
    }

    func asset(for id: String) -> PHAsset? { assetsByID[id] }

    func assets(for ids: [String]) -> [PHAsset] { ids.compactMap { assetsByID[$0] } }

    // MARK: - Images

    /// Requests an image, delivering a fast degraded version first and the full
    /// quality version after. The handler may be called more than once.
    @discardableResult
    func requestImage(for id: String,
                      targetSize: CGSize,
                      contentMode: PHImageContentMode = .aspectFit,
                      handler: @escaping (UIImage?, Bool) -> Void) -> PHImageRequestID? {
        guard let asset = assetsByID[id] else {
            handler(nil, false)
            return nil
        }
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        options.resizeMode = .fast
        return imageManager.requestImage(for: asset, targetSize: targetSize, contentMode: contentMode, options: options) { image, info in
            let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
            if cancelled { return }
            DispatchQueue.main.async { handler(image, degraded) }
        }
    }

    /// Requests a playable item for a video asset, streaming from iCloud if
    /// needed. `progress` reports download progress (0...1) on the main thread.
    @discardableResult
    func requestPlayerItem(for id: String,
                           version: PHVideoRequestOptionsVersion = .current,
                           progress: ((Double) -> Void)? = nil,
                           handler: @escaping (AVPlayerItem?, Error?) -> Void) -> PHImageRequestID? {
        guard let asset = assetsByID[id], asset.mediaType == .video else {
            handler(nil, nil)
            return nil
        }
        let options = PHVideoRequestOptions()
        options.deliveryMode = .automatic
        options.isNetworkAccessAllowed = true
        options.version = version
        if let progress {
            options.progressHandler = { fraction, _, _, _ in
                DispatchQueue.main.async { progress(fraction) }
            }
        }
        return imageManager.requestPlayerItem(forVideo: asset, options: options) { item, info in
            let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
            if cancelled { return }
            let error = info?[PHImageErrorKey] as? Error
            DispatchQueue.main.async { handler(item, error) }
        }
    }

    func isVideo(_ id: String) -> Bool { assetsByID[id]?.mediaType == .video }

    func cancelImageRequest(_ requestID: PHImageRequestID?) {
        guard let requestID else { return }
        imageManager.cancelImageRequest(requestID)
    }

    /// Warms the cache for the assets the user is about to see.
    func startCaching(ids: [String], targetSize: CGSize) {
        let assets = assets(for: ids)
        guard !assets.isEmpty else { return }
        imageManager.startCachingImages(for: assets, targetSize: targetSize, contentMode: .aspectFit, options: nil)
    }

    func stopCachingAll() {
        imageManager.stopCachingImagesForAllAssets()
    }

    // MARK: - Commit

    /// Deletes and hides in one `performChanges` call so iOS shows a single
    /// confirmation dialog. Throws `.cancelled` if the user declines it.
    func commit(deleteIDs: [String], hideIDs: [String]) async throws -> CommitResult {
        guard hasAccess else { throw PhotoLibraryError.notAuthorized }
        let toDelete = assets(for: deleteIDs)
        let toHide = assets(for: hideIDs)
        guard !toDelete.isEmpty || !toHide.isEmpty else {
            return CommitResult(deletedCount: 0, hiddenCount: 0)
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                if !toDelete.isEmpty {
                    PHAssetChangeRequest.deleteAssets(toDelete as NSArray)
                }
                for asset in toHide {
                    PHAssetChangeRequest(for: asset).isHidden = true
                }
            }
        } catch let error as NSError {
            if error.domain == PHPhotosErrorDomain, error.code == PHPhotosError.userCancelled.rawValue {
                throw PhotoLibraryError.cancelled
            }
            throw PhotoLibraryError.underlying(error)
        }
        return CommitResult(deletedCount: toDelete.count, hiddenCount: toHide.count)
    }
}

// MARK: - Change observation

extension PhotoLibraryService: PHPhotoLibraryChangeObserver {
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            guard let fetchResult, changeInstance.changeDetails(for: fetchResult) != nil else { return }
            await loadLibrary()
        }
    }
}
