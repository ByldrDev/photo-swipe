import Foundation
import SwiftUI
import UIKit
import Observation

/// Owns the one in-progress session and wires the pure `SwipeSession` model to
/// PhotoKit and disk. Every mutation persists immediately.
@MainActor
@Observable
final class AppModel {
    let library: PhotoLibraryService
    let store: SessionStore
    /// The one player behind every video card. Owned here (not by the card) so
    /// the transport controls in the deck's chrome can drive it.
    let videoPlayer: AssetVideoPlayer

    private(set) var session: SwipeSession?
    var direction: SwipeDirection = .newestFirst
    var isSwiping = false
    var isCommitting = false
    var lastCommit: CommitResult?
    var commitError: String?

    init(library: PhotoLibraryService? = nil, store: SessionStore = SessionStore()) {
        self.library = library ?? PhotoLibraryService()
        self.store = store
        self.videoPlayer = AssetVideoPlayer(library: self.library)
        self.session = store.load()
        if let session { direction = session.direction }
    }

    /// Called once at launch and again whenever the library snapshot changes.
    func bootstrap() async {
        if library.hasAccess {
            await library.loadLibrary()
        }
    }

    func requestAccess() async {
        await library.requestAccess()
        await bootstrap()
    }

    /// Re-anchor the saved session onto the current library so vanished assets
    /// drop out and new ones are included without losing the cursor.
    func rebaseSessionOnLibrary() {
        guard library.hasLoaded, let current = session else { return }
        let rebased = current.rebased(onto: library.assetIDs)
        if rebased != current {
            session = rebased
            persist()
        }
    }

    var hasResumableSession: Bool {
        guard let session else { return false }
        return !session.isEmpty && (session.canUndo || !session.isFinished)
    }

    // MARK: - Session lifecycle

    func startSession(startID: String? = nil) {
        session = SwipeSession(assetIDs: library.assetIDs, direction: direction, startID: startID)
        persist()
        isSwiping = true
    }

    func resumeSession() {
        guard session != nil else { return }
        rebaseSessionOnLibrary()
        isSwiping = true
    }

    func discardSession() {
        session = nil
        store.clear()
        library.stopCachingAll()
    }

    func setDirection(_ newDirection: SwipeDirection) {
        direction = newDirection
        session?.setDirection(newDirection)
        persist()
    }

    // MARK: - Swiping

    func decide(_ verdict: SwipeDecision) {
        session?.decide(verdict)
        persist()
    }

    func undo() {
        session?.undo()
        persist()
    }

    func jump(to id: String) {
        session?.jump(to: id)
        persist()
    }

    func rescue(_ id: String) {
        session?.rescue(id)
        persist()
    }

    /// How far ahead of the cursor to keep screen-sized images decoded.
    static let prefetchAhead = 20
    static let prefetchBehind = 2

    /// Warm the image cache for what comes next (and keep undo targets warm).
    func prefetch(targetSize: CGSize) {
        guard let session else { return }
        let scale = UIScreen.main.scale
        let pixelSize = CGSize(width: targetSize.width * scale, height: targetSize.height * scale)
        library.updateCacheWindow(
            ids: session.neighborIDs(ahead: Self.prefetchAhead, behind: Self.prefetchBehind),
            targetSize: pixelSize
        )
    }

    // MARK: - Commit

    /// Applies every queued delete/hide in one PhotoKit transaction.
    /// On success the committed assets leave the session; on cancel nothing changes.
    func commit() async {
        guard let current = session, !isCommitting else { return }
        isCommitting = true
        defer { isCommitting = false }
        commitError = nil
        do {
            let result = try await library.commit(deleteIDs: current.deleteIDs, hideIDs: current.hideIDs)
            var updated = current
            updated.remove(ids: Set(current.deleteIDs + current.hideIDs))
            session = updated
            lastCommit = result
            if updated.isEmpty || (updated.isFinished && !updated.canUndo) {
                discardSession()
            } else {
                persist()
            }
        } catch let error as PhotoLibraryError {
            if case .cancelled = error { return }
            commitError = error.localizedDescription
        } catch {
            commitError = error.localizedDescription
        }
    }

    private func persist() {
        if let session { store.save(session) } else { store.clear() }
    }
}
