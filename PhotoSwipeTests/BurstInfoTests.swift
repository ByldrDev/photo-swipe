import XCTest
@testable import PhotoSwipe

final class BurstInfoTests: XCTestCase {
    func testAssignsCaptureOrderPositionsWithinABurst() {
        // Snapshot is newest → oldest: c was captured last, a first.
        let index = BurstInfo.index(newestFirst: [
            ("c", "burst1", false),
            ("b", "burst1", true),
            ("a", "burst1", false),
        ])
        XCTAssertEqual(index["a"], BurstInfo(position: 1, count: 3, isPicked: false))
        XCTAssertEqual(index["b"], BurstInfo(position: 2, count: 3, isPicked: true))
        XCTAssertEqual(index["c"], BurstInfo(position: 3, count: 3, isPicked: false))
    }

    func testNonBurstFramesAreIgnored() {
        let index = BurstInfo.index(newestFirst: [
            ("solo", nil, false),
            ("x", "burst1", false),
        ])
        XCTAssertNil(index["solo"])
        XCTAssertEqual(index["x"]?.count, 1)
        XCTAssertEqual(index.count, 1)
    }

    func testBurstsAreCountedIndependently() {
        let index = BurstInfo.index(newestFirst: [
            ("y2", "burstY", false),
            ("photo", nil, false),
            ("y1", "burstY", false),
            ("z1", "burstZ", true),
        ])
        XCTAssertEqual(index["y1"], BurstInfo(position: 1, count: 2, isPicked: false))
        XCTAssertEqual(index["y2"], BurstInfo(position: 2, count: 2, isPicked: false))
        XCTAssertEqual(index["z1"], BurstInfo(position: 1, count: 1, isPicked: true))
    }
}
