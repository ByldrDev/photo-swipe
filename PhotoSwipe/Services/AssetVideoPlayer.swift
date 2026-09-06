import Foundation
import AVFoundation
import Photos
import Observation

/// Owns one AVPlayer for the current video card: loads the asset's player item,
/// autoplays muted, loops, and tears down cleanly when the card changes.
@MainActor
@Observable
final class AssetVideoPlayer {
    enum State: Equatable {
        case idle
        case loading(progress: Double?)   // nil = local, waiting for PhotoKit
        case ready
        case failed(String)
    }

    let player = AVPlayer()
    private(set) var state: State = .idle
    var isReady: Bool { state == .ready }
    var isMuted = true {
        didSet {
            player.isMuted = isMuted
            configureAudioSession(unmuted: !isMuted)
        }
    }
    private(set) var loadedID: String?

    @ObservationIgnored private var requestID: PHImageRequestID?
    @ObservationIgnored private var loopObserver: NSObjectProtocol?
    @ObservationIgnored private var statusObserver: NSKeyValueObservation?
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
        request(id: id, version: .current)
    }

    func retry() {
        guard let id = loadedID else { return }
        loadedID = nil
        load(id: id)
    }

    /// Asks PhotoKit for a player item. Edited/trimmed clips occasionally fail
    /// to render their `.current` version; when that happens we retry with the
    /// `.original` bytes before giving up.
    private func request(id: String, version: PHVideoRequestOptionsVersion) {
        state = .loading(progress: nil)
        requestID = library.requestPlayerItem(for: id, version: version, progress: { [weak self] fraction in
            guard let self, self.loadedID == id else { return }
            if case .ready = self.state { return }
            self.state = .loading(progress: fraction)
        }) { [weak self] item, error in
            guard let self, self.loadedID == id else { return }
            if let item {
                self.attach(item)
            } else if version == .current {
                self.request(id: id, version: .original)
            } else {
                self.state = .failed(Self.describe(error))
            }
        }
    }

    private static func describe(_ error: Error?) -> String {
        guard let error = error as NSError? else { return "This video couldn't be loaded." }
        if error.domain == NSURLErrorDomain || error.code == PHPhotosError.networkAccessRequired.rawValue {
            return "Couldn't download this video from iCloud. Check your connection and try again."
        }
        return error.localizedDescription
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
        // Surface decode/streaming failures that happen after the item is handed over.
        statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let message = item.error?.localizedDescription ?? "Playback failed."
            Task { @MainActor in
                guard let self, self.loadedID != nil else { return }
                self.state = .failed(message)
            }
        }
        state = .ready
        player.play()
    }

    /// Without an explicit playback session iOS treats the video as ambient
    /// sound and the ring/silent switch mutes it. Claim `.playback` only while
    /// the user has unmuted, so muted browsing keeps their music going.
    private func configureAudioSession(unmuted: Bool) {
        let session = AVAudioSession.sharedInstance()
        do {
            if unmuted {
                try session.setCategory(.playback, mode: .moviePlayback, options: [])
                try session.setActive(true)
            } else {
                try session.setActive(false, options: .notifyOthersOnDeactivation)
                try session.setCategory(.ambient, mode: .moviePlayback, options: [.mixWithOthers])
            }
        } catch {
            // Audio session failures are non-fatal; video still plays.
        }
    }

    func play() { if isReady { player.play() } }
    func pause() { player.pause() }

    func stop() {
        library.cancelImageRequest(requestID)
        requestID = nil
        if let loopObserver { NotificationCenter.default.removeObserver(loopObserver) }
        loopObserver = nil
        statusObserver?.invalidate()
        statusObserver = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        state = .idle
        loadedID = nil
        if !isMuted { isMuted = true }
    }
}
