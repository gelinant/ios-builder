import XCTest

/// M2 end to end: the app searches "coffee" over the San Francisco start camera and shows the
/// results as a list and as pins. Needs the network. Screenshots go to the folder in SHOT_DIR
/// (set by scripts/ios/ci-ipa.sh through TEST_RUNNER_SHOT_DIR) and to the test result.
final class SearchUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testCoffeeSearchShowsResultsAndPins() throws {
        let app = XCUIApplication()
        app.launch()

        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 60), "no search field")
        // Lets the first tiles land, for the screenshots.
        sleep(6)
        field.tap()
        field.typeText("coffee\n")

        let rows = app.buttons.matching(identifier: "search-result")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 60), "no result row: \(messageText(app))")
        // The later pages arrive with the first; wait for the list to settle.
        var count = rows.count
        let settle = Date().addingTimeInterval(10)
        while Date() < settle {
            sleep(1)
            let now = rows.count
            if now == count && now >= 5 { break }
            count = now
        }
        count = rows.count
        print("SEARCH_ROWS=\(count)")
        sleep(3)
        save(app, "search-list")
        XCTAssertGreaterThanOrEqual(count, 5, "fewer than 5 results")

        let toggle = app.buttons["search-panel-toggle"]
        XCTAssertTrue(toggle.exists)
        toggle.tap()
        sleep(3)
        save(app, "search-map")

        toggle.tap()
        let first = rows.firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        first.tap()
        sleep(4)
        save(app, "search-centered")
    }

    private func messageText(_ app: XCUIApplication) -> String {
        let message = app.staticTexts["search-message"]
        return message.exists ? message.label : "no message"
    }

    private func save(_ app: XCUIApplication, _ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SHOT_DIR"], !dir.isEmpty {
            let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).png")
            do {
                try shot.pngRepresentation.write(to: url)
            } catch {
                print("SCREENSHOT_WRITE_FAILED \(name): \(error)")
            }
        }
    }
}
