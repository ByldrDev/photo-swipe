import Foundation
import AVFoundation
import Photos
import Observation

/// Owns one AVPlayer for the current video card: loads the asset's player item,
/// autoplays muted, loops, and tears down cleanly when the card changes.
@MainActor
@Observable
final class AssetVideoPlayer {
    let player = AVPlayer()
    private(set) var isReady = false
    var isMuted = true { didSet { player.isMuted = isMuted } }
    private(set) var loadedID: String?

    @ObservationIgnored private var requestID: PHImageRequestID?
    @ObservationIgnored private var loopObserver: NSObjectProtocol?
    @ObservationIgnored private let library: PhotoLibraryService

    init(library: PhotoLibraryService) {
        self.library = library
        player.isMuted = true
        player.actionAtItemEnd = .none
        player.preventsDisplaySleepDuringVideoPlayback = false
    }

    func load(id: String) {
        guard id != loadedID else { return }
        stop()
        loadedID = id
        requestID = library.requestPlayerItem(for: id) { [weak self] item in
            guard let self, self.loadedID == id, let item else { return }
            self.attach(item)
        }
    }

    private func attach(_ item: AVPlayerItem) {
        player.replaceCurrentItem(with: item)
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.player.seek(to: .zero)
                self.player.play()
            }
        }
        isReady = true
        player.play()
    }

    func play() { if isReady { player.play() } }
    func pause() { player.pause() }

    func stop() {
        library.cancelImageRequest(requestID)
        requestID = nil
        if let loopObserver { NotificationCenter.default.removeObserver(loopObserver) }
        loopObserver = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        isReady = false
        loadedID = nil
    }
}
