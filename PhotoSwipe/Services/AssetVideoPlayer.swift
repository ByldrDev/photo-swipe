import Foundation
import AVFoundation
import Photos
import Observation

/// Owns one AVPlayer for the current video card: loads the asset's player item,
/// autoplays muted, loops, reports playback time for the scrubber, and tears
/// down cleanly when the card changes.
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

    /// Seconds into the clip, updated ~30×/s while an item is attached.
    private(set) var currentTime: Double = 0
    /// Clip length in seconds; 0 until the item reports it.
    private(set) var duration: Double = 0
    /// False after the user taps pause. Scrubbing pauses too, but only for the
    /// length of the drag; `isPlaying` stays true so playback resumes on release.
    private(set) var isPlaying = true
    private(set) var isScrubbing = false

    @ObservationIgnored private var requestID: PHImageRequestID?
    @ObservationIgnored private var loopObserver: NSObjectProtocol?
    @ObservationIgnored private var statusObserver: NSKeyValueObservation?
    @ObservationIgnored private var durationObserver: NSKeyValueObservation?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private let library: PhotoLibraryService

    init(library: PhotoLibraryService) {
        self.library = library
        player.isMuted = true
        player.actionAtItemEnd = .none
        player.preventsDisplaySleepDuringVideoPlayback = false
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
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
                if self.isPlaying { self.player.play() }
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
        durationObserver = item.observe(\.duration, options: [.initial, .new]) { [weak self] item, _ in
            let seconds = item.duration.seconds
            Task { @MainActor in
                guard let self else { return }
                self.duration = seconds.isFinite ? seconds : 0
            }
        }
        let interval = CMTime(value: 1, timescale: 30)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self, !self.isScrubbing else { return }
                self.currentTime = time.seconds
            }
        }
        state = .ready
        isPlaying = true
        player.play()
    }

    // MARK: - Transport

    func togglePlayback() {
        guard isReady else { return }
        isPlaying.toggle()
        isPlaying ? player.play() : player.pause()
    }

    /// Call on every drag update of the scrubber. Playback is held for the
    /// duration of the drag; the exact-tolerance seek makes frame stepping work.
    func scrub(to seconds: Double) {
        guard isReady, duration > 0 else { return }
        if !isScrubbing {
            isScrubbing = true
            player.pause()
        }
        let clamped = min(max(0, seconds), duration)
        currentTime = clamped
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func endScrubbing() {
        guard isScrubbing else { return }
        isScrubbing = false
        if isPlaying { player.play() }
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

    /// Scene-phase hooks: resume only if the user hasn't paused.
    func play() { if isReady, isPlaying { player.play() } }
    func pause() { player.pause() }

    func stop() {
        library.cancelImageRequest(requestID)
        requestID = nil
        if let loopObserver { NotificationCenter.default.removeObserver(loopObserver) }
        loopObserver = nil
        statusObserver?.invalidate()
        statusObserver = nil
        durationObserver?.invalidate()
        durationObserver = nil
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        state = .idle
        loadedID = nil
        currentTime = 0
        duration = 0
        isPlaying = true
        isScrubbing = false
        if !isMuted { isMuted = true }
    }
}
