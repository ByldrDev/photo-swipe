import XCTest

/// Drives the real app against the simulator's photo library. Requires at
/// least 3 photos in the library (the simulator ships with several).
final class PhotoSwipeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        grantPhotoAccessIfAsked()
        // Fresh state for every test.
        if app.buttons["discardButton"].waitForExistence(timeout: 2) {
            app.buttons["discardButton"].tap()
        }
        XCTAssertTrue(app.buttons["startButton"].waitForExistence(timeout: 10), "home should show the start button once the library is loaded")
    }

    /// Taps through the system photo permission alert on first run.
    /// `simctl privacy grant photos` does not cover PhotoKit read-write access on
    /// recent simulators, so the alert has to be answered for real.
    private func grantPhotoAccessIfAsked() {
        let allow = app.buttons["allowAccessButton"]
        guard allow.waitForExistence(timeout: 3) else { return }
        allow.tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        guard alert.waitForExistence(timeout: 5) else { return }
        let labels = alert.buttons.allElementsBoundByIndex.map(\.label)
        NSLog("Photo permission alert buttons: \(labels)")
        let preferred = ["Allow Full Access", "Allow Access to All Photos", "Allow"]
        if let match = preferred.first(where: { alert.buttons[$0].exists }) {
            alert.buttons[match].tap()
        } else if let fallback = alert.buttons.allElementsBoundByIndex.first(where: {
            $0.label.localizedCaseInsensitiveContains("allow")
                && !$0.label.localizedCaseInsensitiveContains("don")
                && !$0.label.localizedCaseInsensitiveContains("limit")
        }) {
            fallback.tap()
        }
    }

    private func saveScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private var progress: String { app.staticTexts["progressLabel"].label }

    func testHomeShowsLibraryCount() {
        let count = app.staticTexts["libraryCount"]
        XCTAssertTrue(count.exists)
        XCTAssertGreaterThan(Int(count.label.filter(\.isNumber)) ?? 0, 0)
        saveScreenshot("home")
    }

    func testSwipeGesturesRecordDecisionsAndUndo() {
        app.buttons["startButton"].tap()
        let card = app.otherElements["swipeCard"].firstMatch.exists ? app.otherElements["swipeCard"].firstMatch : app.images["swipeCard"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(progress.hasPrefix("1 /"))
        saveScreenshot("swipe-1")

        card.swipeRight()            // keep
        XCTAssertTrue(waitForProgress(prefix: "2 /"))

        card.swipeLeft()             // delete
        XCTAssertTrue(waitForProgress(prefix: "3 /"))
        XCTAssertEqual(app.staticTexts["pendingCount"].label, "1")

        card.swipeUp()               // hide
        XCTAssertTrue(waitForProgress(prefix: "4 /") || app.staticTexts["finishedSummary"].exists)
        XCTAssertEqual(app.staticTexts["pendingCount"].label, "2")
        saveScreenshot("swipe-after-3")

        // Undo steps back onto the hidden photo and drops its verdict.
        app.buttons["undoButton"].tap()
        XCTAssertTrue(waitForProgress(prefix: "3 /"))
        XCTAssertEqual(app.staticTexts["pendingCount"].label, "1")

        app.buttons["undoButton"].tap()
        XCTAssertTrue(waitForProgress(prefix: "2 /"))
        XCTAssertFalse(app.staticTexts["pendingCount"].exists, "no pending changes after undoing the delete")
    }

    func testButtonsAndReviewRescue() {
        app.buttons["startButton"].tap()
        XCTAssertTrue(app.buttons["deleteButton"].waitForExistence(timeout: 5))
        app.buttons["deleteButton"].tap()
        XCTAssertTrue(waitForProgress(prefix: "2 /"))
        app.buttons["hideButton"].tap()
        XCTAssertTrue(waitForProgress(prefix: "3 /"))
        app.buttons["keepButton"].tap()
        XCTAssertEqual(app.staticTexts["pendingCount"].label, "2")

        app.buttons["reviewButton"].tap()
        XCTAssertTrue(app.staticTexts["deleteSectionHeader"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["hideSectionHeader"].exists)
        XCTAssertEqual(app.buttons.matching(identifier: "reviewTile").count, 2)
        XCTAssertTrue(app.buttons["commitButton"].label.contains("Delete 1 & hide 1"))
        saveScreenshot("review")

        // Rescue the delete: the delete section disappears, commit button updates.
        app.buttons["reviewTile"].firstMatch.tap()
        XCTAssertFalse(app.staticTexts["deleteSectionHeader"].waitForExistence(timeout: 1))
        XCTAssertTrue(app.buttons["commitButton"].label.contains("Hide 1"))
        app.buttons["reviewDoneButton"].tap()
        XCTAssertEqual(app.staticTexts["pendingCount"].label, "1")
    }

    func testSessionPersistsAcrossRelaunch() {
        app.buttons["startButton"].tap()
        XCTAssertTrue(app.buttons["deleteButton"].waitForExistence(timeout: 5))
        app.buttons["deleteButton"].tap()
        XCTAssertTrue(waitForProgress(prefix: "2 /"))

        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["resumeButton"].waitForExistence(timeout: 10), "home should offer to resume")
        saveScreenshot("home-resume")
        app.buttons["resumeButton"].tap()
        XCTAssertTrue(waitForProgress(prefix: "2 /"))
        XCTAssertEqual(app.staticTexts["pendingCount"].label, "1")
    }

    func testOldestFirstDirection() {
        app.buttons["Oldest → newest"].firstMatch.tap()
        app.buttons["startButton"].tap()
        XCTAssertTrue(waitForProgress(prefix: "1 /"))
        app.buttons["keepButton"].tap()
        XCTAssertTrue(waitForProgress(prefix: "2 /"))
    }

    /// End-to-end commit: queues one delete and one hide, confirms the system
    /// dialog, and checks the library count on Home drops by two (hidden assets
    /// are excluded from the fetch). Mutates the simulator library on purpose.
    func testCommitDeletesAndHidesAssets() {
        let before = Int(app.staticTexts["libraryCount"].label.filter(\.isNumber)) ?? 0
        XCTAssertGreaterThanOrEqual(before, 3, "need at least 3 photos in the simulator library")

        app.buttons["startButton"].tap()
        XCTAssertTrue(app.buttons["deleteButton"].waitForExistence(timeout: 5))
        app.buttons["deleteButton"].tap()
        XCTAssertTrue(waitForProgress(prefix: "2 /"))
        app.buttons["hideButton"].tap()
        XCTAssertTrue(waitForProgress(prefix: "3 /"))

        app.buttons["reviewButton"].tap()
        XCTAssertTrue(app.buttons["commitButton"].waitForExistence(timeout: 5))
        app.buttons["commitButton"].tap()

        // iOS confirms hides ("Hide" / "Don't Allow") and deletes ("Delete") with
        // separate system alerts, even inside one performChanges. Accept each.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        var confirmed = 0
        while confirmed < 2 {
            let alert = springboard.alerts.firstMatch
            guard alert.waitForExistence(timeout: 5) else { break }
            let labels = alert.buttons.allElementsBoundByIndex.map(\.label)
            NSLog("System confirmation buttons: \(labels)")
            guard let confirm = alert.buttons.allElementsBoundByIndex.first(where: {
                $0.label.localizedCaseInsensitiveContains("delete") || $0.label == "Hide"
            }) else { XCTFail("unexpected system alert: \(labels)"); break }
            confirm.tap()
            confirmed += 1
        }
        XCTAssertGreaterThan(confirmed, 0, "expected at least one system confirmation")

        let done = app.alerts.firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 10), "result alert should appear after commit")
        XCTAssertTrue(done.staticTexts.allElementsBoundByIndex.contains { $0.label.contains("Deleted 1 and hid 1") },
                      "result alert should report 1 deleted and 1 hidden")
        saveScreenshot("commit-result")
        done.buttons["OK"].tap()

        // Back on the deck; close it and check Home's count.
        app.buttons["closeButton"].tap()
        let count = app.staticTexts["libraryCount"]
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", (before - 2).formatted()), object: count)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 10), .completed,
                       "library count should drop from \(before) to \(before - 2), was \(count.label)")
    }

    private func waitForProgress(prefix: String, timeout: TimeInterval = 3) -> Bool {
        let label = app.staticTexts["progressLabel"]
        let predicate = NSPredicate(format: "label BEGINSWITH %@", prefix)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: label)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
