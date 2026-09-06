import XCTest
@testable import PhotoSwipe

final class SwipeSessionTests: XCTestCase {
    let ids = ["a", "b", "c", "d", "e"] // newest → oldest

    func testDefaultStartsAtNewest() {
        let s = SwipeSession(assetIDs: ids)
        XCTAssertEqual(s.currentID, "a")
        XCTAssertEqual(s.position, 1)
        XCTAssertEqual(s.remainingCount, 4)
        XCTAssertFalse(s.isFinished)
    }

    func testOldestFirstStartsAtEnd() {
        let s = SwipeSession(assetIDs: ids, direction: .oldestFirst)
        XCTAssertEqual(s.currentID, "e")
        XCTAssertEqual(s.position, 1)
        XCTAssertEqual(s.remainingCount, 4)
    }

    func testStartIDSetsCursor() {
        let s = SwipeSession(assetIDs: ids, startID: "c")
        XCTAssertEqual(s.currentID, "c")
        XCTAssertEqual(s.position, 3)
    }

    func testDecideAdvancesAndRecords() {
        var s = SwipeSession(assetIDs: ids)
        s.decide(.keep)
        s.decide(.delete)
        s.decide(.hide)
        XCTAssertEqual(s.currentID, "d")
        XCTAssertEqual(s.deleteIDs, ["b"])
        XCTAssertEqual(s.hideIDs, ["c"])
        XCTAssertEqual(s.keepCount, 1)
        XCTAssertEqual(s.pendingCount, 2)
        XCTAssertEqual(s.verdict(for: "a"), .keep)
        XCTAssertNil(s.verdict(for: "d"))
    }

    func testWalkOffEndFinishes() {
        var s = SwipeSession(assetIDs: ["a", "b"])
        s.decide(.keep)
        s.decide(.keep)
        XCTAssertTrue(s.isFinished)
        XCTAssertNil(s.currentID)
        XCTAssertEqual(s.remainingCount, 0)
        s.decide(.delete) // no-op when finished
        XCTAssertEqual(s.deleteIDs, [])
    }

    func testOldestFirstWalksBackwardsThroughArray() {
        var s = SwipeSession(assetIDs: ids, direction: .oldestFirst)
        s.decide(.delete)
        XCTAssertEqual(s.currentID, "d")
        XCTAssertEqual(s.deleteIDs, ["e"])
        s.decide(.keep); s.decide(.keep); s.decide(.keep); s.decide(.keep)
        XCTAssertTrue(s.isFinished)
    }

    func testUndoRestoresPositionAndRemovesVerdict() {
        var s = SwipeSession(assetIDs: ids)
        s.decide(.delete)
        s.decide(.hide)
        XCTAssertEqual(s.undo(), "b")
        XCTAssertEqual(s.currentID, "b")
        XCTAssertEqual(s.hideIDs, [])
        XCTAssertEqual(s.deleteIDs, ["a"])
        XCTAssertEqual(s.undo(), "a")
        XCTAssertEqual(s.currentID, "a")
        XCTAssertEqual(s.deleteIDs, [])
        XCTAssertNil(s.undo())
        XCTAssertFalse(s.canUndo)
    }

    func testUndoAfterFinishingReopensSession() {
        var s = SwipeSession(assetIDs: ["a"])
        s.decide(.delete)
        XCTAssertTrue(s.isFinished)
        s.undo()
        XCTAssertEqual(s.currentID, "a")
        XCTAssertFalse(s.isFinished)
    }

    func testRedecideReplacesVerdict() {
        var s = SwipeSession(assetIDs: ids)
        s.decide(.delete)
        s.undo()
        s.decide(.keep)
        XCTAssertEqual(s.deleteIDs, [])
        XCTAssertEqual(s.verdict(for: "a"), .keep)
        XCTAssertEqual(s.history.count, 1)
    }

    func testRescueFlipsToKeep() {
        var s = SwipeSession(assetIDs: ids)
        s.decide(.delete)
        s.decide(.hide)
        s.rescue("a")
        XCTAssertEqual(s.deleteIDs, [])
        XCTAssertEqual(s.hideIDs, ["b"])
        XCTAssertEqual(s.keepCount, 1)
    }

    func testJumpMovesCursorOnly() {
        var s = SwipeSession(assetIDs: ids)
        s.decide(.keep)
        s.jump(to: "e")
        XCTAssertEqual(s.currentID, "e")
        XCTAssertEqual(s.keepCount, 1)
        s.jump(to: "nope")
        XCTAssertEqual(s.currentID, "e")
    }

    func testDirectionFlipMidSession() {
        var s = SwipeSession(assetIDs: ids, startID: "c")
        s.setDirection(.oldestFirst)
        s.decide(.keep)
        XCTAssertEqual(s.currentID, "b")
        XCTAssertEqual(s.position, 4)
    }

    func testEmptyLibrary() {
        var s = SwipeSession(assetIDs: [])
        XCTAssertTrue(s.isEmpty)
        XCTAssertTrue(s.isFinished)
        XCTAssertNil(s.currentID)
        XCTAssertEqual(s.position, 0)
        s.decide(.keep)
        XCTAssertNil(s.undo())
    }

    func testNeighborIDsFollowDirection() {
        let s = SwipeSession(assetIDs: ids, startID: "c")
        XCTAssertEqual(s.neighborIDs(ahead: 2), ["b", "c", "d", "e"])
        var o = SwipeSession(assetIDs: ids, direction: .oldestFirst)
        o.jump(to: "c")
        XCTAssertEqual(o.neighborIDs(ahead: 2), ["d", "c", "b", "a"])
    }

    func testRemoveCommittedIDsKeepsCursorOnCurrent() {
        var s = SwipeSession(assetIDs: ids)
        s.decide(.delete) // a
        s.decide(.hide)   // b
        s.remove(ids: ["a", "b"])
        XCTAssertEqual(s.assetIDs, ["c", "d", "e"])
        XCTAssertEqual(s.currentID, "c")
        XCTAssertEqual(s.pendingCount, 0)
        XCTAssertEqual(s.position, 1)
    }

    func testRemoveWhenFinishedStaysFinished() {
        var s = SwipeSession(assetIDs: ["a", "b"])
        s.decide(.delete); s.decide(.delete)
        s.remove(ids: ["a", "b"])
        XCTAssertTrue(s.isFinished)
        XCTAssertTrue(s.isEmpty)
    }

    func testRebasedKeepsDecisionsAndCursor() {
        var s = SwipeSession(assetIDs: ids)
        s.decide(.delete) // a
        s.decide(.keep)   // b -> now on c
        // New photo "z" arrived, "c" and "a" vanished.
        let r = s.rebased(onto: ["z", "b", "d", "e"])
        XCTAssertEqual(r.currentID, "d", "cursor should skip missing 'c' to the next surviving asset")
        XCTAssertEqual(r.deleteIDs, [], "decision for vanished 'a' is dropped")
        XCTAssertEqual(r.keepCount, 1)
        XCTAssertEqual(r.direction, .newestFirst)
    }

    func testRebasedFinishedStaysFinished() {
        var s = SwipeSession(assetIDs: ["a"])
        s.decide(.keep)
        let r = s.rebased(onto: ["a", "b"])
        XCTAssertTrue(r.isFinished)
    }

    func testCodableRoundTrip() throws {
        var s = SwipeSession(assetIDs: ids, direction: .oldestFirst)
        s.decide(.delete)
        s.decide(.hide)
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(SwipeSession.self, from: data)
        XCTAssertEqual(back, s)
        XCTAssertEqual(back.currentID, "c")
    }
}
