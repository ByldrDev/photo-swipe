import XCTest

final class PhotoSwipeUITests: XCTestCase {
    func testLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["PhotoSwipe"].waitForExistence(timeout: 5))
    }
}
