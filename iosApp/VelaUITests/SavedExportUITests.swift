import XCTest

/// Export and sharing finishing for saved content: a whole list leaves through the share sheet
/// and comes back through the document picker, and the parked car opens from Saved.
final class SavedExportUITests: VelaUITestCase {
    func testListExportImportsBackFromTheShareSheet() throws {
        let app = launch(camera: "sf", arguments: ["-VelaSavedExportRoundtrip", "YES"])
        let name = openFirstCoffeePlace(app)
        app.buttons["place-save"].tap()

        app.buttons["place-lists"].tap()
        app.buttons["save-create-list"].tap()
        let field = app.textFields["saved-name-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "no list name field")
        field.tap()
        field.typeText("UI Export List")
        app.buttons["saved-name-save"].tap()
        app.buttons["Done"].tap()
        app.buttons["place-close"].tap()

        app.buttons["saved-open"].tap()
        XCTAssertTrue(app.navigationBars["Saved"].waitForExistence(timeout: 5), "Saved sheet missing")
        XCTAssertTrue(app.buttons["saved-list"].firstMatch.waitForExistence(timeout: 5), "list not created")
        let listRow = app.buttons["UI Export List, 1 places"]
        XCTAssertTrue(listRow.waitForExistence(timeout: 10), "place not added to the list")
        listRow.tap()
        XCTAssertTrue(app.navigationBars["UI Export List"].waitForExistence(timeout: 5), "list detail missing")

        app.buttons["List actions"].tap()
        let share = app.buttons["Share list (JSON)"]
        XCTAssertTrue(share.waitForExistence(timeout: 5), "no share action")
        share.tap()
        // The sheet is hosted by another process, so its contents are not queryable here; its
        // ActivityListView placeholder is, and that is what proves the system sheet opened.
        let activity = app.otherElements["ActivityListView"]
        XCTAssertTrue(activity.waitForExistence(timeout: 15), "share sheet did not open")
        shot("saved-export")
        report("saved_export_sheet", "opened")
        // The share sheet is hosted by another process: leaving it open and terminating the app
        // is more reliable than driving its remote buttons.
        app.terminate()

        // Delete the list so a successful import has something visible to bring back.
        var cleanup = launch()
        cleanup.buttons["saved-open"].tap()
        let row = cleanup.buttons["UI Export List, 1 places"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "list row missing after export")
        row.swipeLeft()
        if cleanup.buttons["Delete"].waitForExistence(timeout: 5) { cleanup.buttons["Delete"].tap() }
        XCTAssertTrue(waitUntil(10) { !row.exists }, "list was not deleted before the import")
        cleanup.terminate()

        // The export wrote the exact document; this launch hands it to the same importer the
        // document picker uses. The picker itself is covered by the L-1 scenario and the reader
        // tests, and its remote Files view cannot select an app's temporary file in XCUITest.
        var importer = launch(arguments: ["-VelaSavedImportRoundtrip", "YES"])
        importer.buttons["saved-open"].tap()
        let message = importer.staticTexts["saved-import-message"]
        XCTAssertTrue(message.waitForExistence(timeout: 20), "import did not finish")
        XCTAssertTrue(message.label.contains("imported"), message.label)
        let importedRow = importer.buttons["UI Export List, 1 places"]
        XCTAssertTrue(importedRow.waitForExistence(timeout: 10), "list did not come back")
        shot("saved-import-back")
        report("saved_export_roundtrip", "1 place")

        importedRow.swipeLeft()
        if importer.buttons["Delete"].waitForExistence(timeout: 5) { importer.buttons["Delete"].tap() }
        importer.buttons["saved-close"].tap()
        print("ROUNDTRIP_PLACE=\(name)")
    }

    func testFindMyCarOpensTheSpotWithDirections() {
        let app = launch(
            camera: "sf", followUser: true,
            arguments: ["-VelaIntentTestFixture", "parking"])
        app.buttons["saved-open"].tap()
        XCTAssertTrue(app.navigationBars["Saved"].waitForExistence(timeout: 5), "Saved sheet missing")
        var find = app.buttons["parking-find"]
        if !reveal(find, in: app) {
            find = app.buttons["Find my car"]
        }
        XCTAssertTrue(reveal(find, in: app), "no Find my car action")
        find.tap()
        let placeName = app.staticTexts["place-name"]
        XCTAssertTrue(placeName.waitForExistence(timeout: 15), "parked car did not open")
        XCTAssertEqual(placeName.label, "Parked car")
        XCTAssertTrue(app.buttons["place-directions"].exists, "parked car offers no Directions")
        shot("saved-find-my-car")
        report("saved_find_my_car", "opened")
        app.buttons["place-close"].tap()
    }

    private func openFirstCoffeePlace(_ app: XCUIApplication) -> String {
        sleep(3)
        let field = app.textFields["search-field"]
        field.tap()
        field.typeText("coffee\n")
        let results = app.buttons.matching(identifier: "search-result")
        XCTAssertTrue(results.firstMatch.waitForExistence(timeout: 60), "no search result")
        results.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["place-name"].waitForExistence(timeout: 15), "no place sheet")
        return app.staticTexts["place-name"].label
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, up: Bool = true) -> Bool {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return true }
            if up { app.swipeUp() } else { app.swipeDown() }
            usleep(300_000)
        }
        return element.exists
    }

}
