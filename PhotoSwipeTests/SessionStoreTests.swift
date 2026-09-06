import XCTest
@testable import PhotoSwipe

final class SessionStoreTests: XCTestCase {
    func testSaveLoadClear() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = SessionStore(directory: dir)
        XCTAssertNil(store.load())
        var session = SwipeSession(assetIDs: ["a", "b", "c"])
        session.decide(.delete)
        store.save(session)
        XCTAssertEqual(store.load(), session)
        store.clear()
        XCTAssertNil(store.load())
    }
}
