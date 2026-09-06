import Foundation

/// Pure, PhotoKit-free model of one triage session.
///
/// Holds the ordered list of asset ids (newest first), a cursor into it, the
/// walking direction and an ordered decision log. Swiping never touches the
/// library; it only appends to the log. `deleteIDs` / `hideIDs` are what the
/// Review screen commits later.
struct SwipeSession: Codable, Equatable {
    struct Decision: Codable, Equatable {
        let id: String
        var verdict: SwipeDecision
    }

    /// All asset ids in library order, newest → oldest.
    private(set) var assetIDs: [String]
    private(set) var direction: SwipeDirection
    /// Index into `assetIDs`. Out of range means the walk is finished.
    private(set) var cursor: Int
    /// Ordered log; the last entry is the most recent swipe (used by undo).
    private(set) var history: [Decision]
    let startedAt: Date

    init(assetIDs: [String], direction: SwipeDirection = .newestFirst, startID: String? = nil, startedAt: Date = Date()) {
        self.assetIDs = assetIDs
        self.direction = direction
        self.history = []
        self.startedAt = startedAt
        if let startID, let index = assetIDs.firstIndex(of: startID) {
            cursor = index
        } else {
            cursor = direction == .newestFirst ? 0 : assetIDs.count - 1
        }
    }

    // MARK: - State

    var isFinished: Bool { !assetIDs.indices.contains(cursor) }
    var isEmpty: Bool { assetIDs.isEmpty }
    var currentID: String? { isFinished ? nil : assetIDs[cursor] }
    var totalCount: Int { assetIDs.count }

    /// 1-based position of the current asset along the walking direction.
    var position: Int {
        guard !isFinished else { return totalCount }
        return direction == .newestFirst ? cursor + 1 : totalCount - cursor
    }

    /// Assets still ahead of the cursor (excluding the current one).
    var remainingCount: Int {
        guard !isFinished else { return 0 }
        return direction == .newestFirst ? totalCount - cursor - 1 : cursor
    }

    var canUndo: Bool { !history.isEmpty }

    var deleteIDs: [String] { history.filter { $0.verdict == .delete }.map(\.id) }
    var hideIDs: [String] { history.filter { $0.verdict == .hide }.map(\.id) }
    var keepCount: Int { history.filter { $0.verdict == .keep }.count }
    var pendingCount: Int { deleteIDs.count + hideIDs.count }

    func verdict(for id: String) -> SwipeDecision? {
        history.last(where: { $0.id == id })?.verdict
    }

    /// Ids of the assets around the cursor in walking order, used for prefetching.
    func neighborIDs(ahead: Int, behind: Int = 1) -> [String] {
        guard !isFinished else { return [] }
        let range = (-behind)...ahead
        return range.compactMap { offset -> String? in
            let index = cursor + offset * direction.step
            return assetIDs.indices.contains(index) ? assetIDs[index] : nil
        }
    }

    // MARK: - Mutation

    /// Records `verdict` for the current asset and advances the cursor.
    mutating func decide(_ verdict: SwipeDecision) {
        guard let id = currentID else { return }
        history.removeAll { $0.id == id }
        history.append(Decision(id: id, verdict: verdict))
        cursor += direction.step
    }

    /// Removes the most recent decision and moves the cursor back onto that asset.
    /// Returns the asset id that is now current, or nil if there was nothing to undo.
    @discardableResult
    mutating func undo() -> String? {
        guard let last = history.popLast() else { return nil }
        if let index = assetIDs.firstIndex(of: last.id) {
            cursor = index
        }
        return last.id
    }

    /// Moves the cursor onto `id` without changing any decision.
    mutating func jump(to id: String) {
        if let index = assetIDs.firstIndex(of: id) { cursor = index }
    }

    mutating func setDirection(_ newDirection: SwipeDirection) {
        direction = newDirection
        if isFinished {
            cursor = newDirection == .newestFirst ? 0 : assetIDs.count - 1
        }
    }

    /// Flips a queued delete/hide back to keep (Review screen "rescue").
    mutating func rescue(_ id: String) {
        guard let index = history.firstIndex(where: { $0.id == id }) else { return }
        history[index].verdict = .keep
    }

    /// Drops ids that have been committed (deleted/hidden) or no longer exist.
    /// Keeps the cursor on the same asset where possible.
    mutating func remove(ids: Set<String>) {
        guard !ids.isEmpty else { return }
        let current = currentID
        let wasFinished = isFinished
        assetIDs.removeAll { ids.contains($0) }
        history.removeAll { ids.contains($0.id) }
        if let current, let index = assetIDs.firstIndex(of: current) {
            cursor = index
        } else if wasFinished {
            cursor = direction == .newestFirst ? assetIDs.count : -1
        } else {
            cursor = min(max(cursor, 0), assetIDs.count)
            if direction == .oldestFirst { cursor = min(cursor, assetIDs.count - 1) }
        }
    }

    /// Rebuilds the session on a fresh library snapshot (e.g. after relaunch):
    /// keeps direction and every decision whose asset still exists, and puts the
    /// cursor back on the same asset (or the next surviving one in walking order).
    func rebased(onto newIDs: [String]) -> SwipeSession {
        let newSet = Set(newIDs)
        var session = SwipeSession(assetIDs: newIDs, direction: direction, startID: nil, startedAt: startedAt)
        session.history = history.filter { newSet.contains($0.id) }

        if isFinished {
            session.cursor = direction == .newestFirst ? newIDs.count : -1
            return session
        }
        var index = cursor
        while assetIDs.indices.contains(index) {
            if let newIndex = newIDs.firstIndex(of: assetIDs[index]) {
                session.cursor = newIndex
                return session
            }
            index += direction.step
        }
        session.cursor = direction == .newestFirst ? newIDs.count : -1
        return session
    }
}
