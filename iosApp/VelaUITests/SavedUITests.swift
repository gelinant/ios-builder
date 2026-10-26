import XCTest

/// Saved places, list membership and recents, including a second process launch over UserDefaults.
/// The search needs the network; everything after the first result is local.
final class SavedUITests: VelaUITestCase {
    func testSavedPlaceListAndRecentsPersist() throws {
        var app = launch(camera: "sf")
        let field = app.textFields["search-field"]
        field.tap()
        field.typeText("coffee\n")
        let results = app.buttons.matching(identifier: "search-result")
        XCTAssertTrue(results.firstMatch.waitForExistence(timeout: 60), "no search result")
        results.firstMatch.tap()
        let placeName = app.staticTexts["place-name"]
        XCTAssertTrue(placeName.waitForExistence(timeout: 15), "no place sheet")
        let name = placeName.label

        let save = app.buttons["place-save"]
        XCTAssertTrue(save.waitForExistence(timeout: 10), "no Save button")
        save.tap()
        shot("place-save")

        app.buttons["saved-open"].tap()
        let savedRows = app.buttons.matching(identifier: "saved-place")
        XCTAssertTrue(savedRows.firstMatch.waitForExistence(timeout: 10), "saved place missing")
        XCTAssertTrue(app.buttons[name].waitForExistence(timeout: 5), "wrong saved place")

        app.buttons["saved-create-list"].tap()
        let listNameField = app.textFields["saved-name-field"]
        XCTAssertTrue(listNameField.waitForExistence(timeout: 5), "no list name field")
        listNameField.tap()
        listNameField.typeText("UI Test List")
        app.buttons["saved-name-save"].tap()
        XCTAssertTrue(app.buttons["saved-list"].firstMatch.waitForExistence(timeout: 5), "list not created")
        app.buttons["saved-close"].tap()

        app.buttons["place-lists"].tap()
        let listButton = app.buttons["UI Test List"]
        XCTAssertTrue(listButton.waitForExistence(timeout: 5), "new list missing from place picker")
        listButton.tap()
        app.buttons["Done"].tap()

        app.buttons["saved-open"].tap()
        XCTAssertTrue(waitUntil(10) {
            app.buttons["UI Test List, 1 places"].exists || app.buttons["UI Test List, 1 place"].exists
        }, "place not added to list")
        shot("saved-list")
        report("saved_lists", app.buttons.matching(identifier: "saved-list").count)
        app.buttons["saved-close"].tap()

        let clear = app.buttons["search-clear"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5), "no clear search button")
        clear.tap()
        let recentRows = app.buttons.matching(identifier: "search-recent")
        XCTAssertTrue(recentRows.firstMatch.waitForExistence(timeout: 10), "recents missing after clear")
        XCTAssertTrue(app.buttons["coffee"].waitForExistence(timeout: 5), "recent search missing")

        // Give UserDefaults' asynchronous apply a moment to reach disk before killing the app.
        sleep(2)
        app.terminate()
        app = launch(camera: "sf")
        app.buttons["saved-open"].tap()
        let persistedSavedRows = app.buttons.matching(identifier: "saved-place")
        XCTAssertTrue(persistedSavedRows.firstMatch.waitForExistence(timeout: 10), "saved place lost on restart")
        XCTAssertTrue(app.buttons[name].exists, "wrong place after restart")
        XCTAssertTrue(app.buttons["UI Test List, 1 places"].exists || app.buttons["UI Test List, 1 place"].exists,
                      "list membership lost on restart")
        let persistedSavedCount = persistedSavedRows.count
        report("saved_places", persistedSavedCount)
        report("saved_lists_after_restart", app.buttons.matching(identifier: "saved-list").count)
        app.buttons["saved-close"].tap()

        app.textFields["search-field"].tap()
        let persistedRecentRows = app.buttons.matching(identifier: "search-recent")
        XCTAssertTrue(persistedRecentRows.firstMatch.waitForExistence(timeout: 10), "recents lost on restart")
        XCTAssertTrue(app.buttons["coffee"].exists, "recent search lost on restart")
        report("saved_recents_after_restart", persistedRecentRows.count)
        XCTAssertGreaterThanOrEqual(persistedSavedCount, 1)
        XCTAssertGreaterThanOrEqual(persistedRecentRows.count, 1)
    }
}
