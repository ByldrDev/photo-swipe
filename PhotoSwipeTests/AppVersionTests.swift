import XCTest
@testable import PhotoSwipe

final class AppVersionTests: XCTestCase {
    func testParsesTagsAndShortVersions() {
        XCTAssertEqual(AppVersion("v1.0.2"), AppVersion(1, 0, 2))
        XCTAssertEqual(AppVersion("1.0"), AppVersion(1, 0, 0))
        XCTAssertEqual(AppVersion("2"), AppVersion(2, 0, 0))
        XCTAssertEqual(AppVersion(" 1.2.3\n"), AppVersion(1, 2, 3))
    }

    func testRejectsGarbage() {
        XCTAssertNil(AppVersion("1.0.2-beta"))
        XCTAssertNil(AppVersion("1.0.2.4"))
        XCTAssertNil(AppVersion(""))
        XCTAssertNil(AppVersion("a.b"))
    }

    func testOrdering() {
        XCTAssertTrue(AppVersion("1.0.2")! > AppVersion("1.0.1")!)
        XCTAssertTrue(AppVersion("1.0.10")! > AppVersion("1.0.9")!)
        XCTAssertTrue(AppVersion("1.1")! > AppVersion("1.0.99")!)
        XCTAssertTrue(AppVersion("2.0")! > AppVersion("1.9.9")!)
        XCTAssertEqual(AppVersion("1.0")!, AppVersion("1.0.0")!)
        XCTAssertEqual("\(AppVersion("v1.0.2")!)", "1.0.2")
    }
}
