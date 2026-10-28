import XCTest

/// IMP-GOOGLE on the simulator: a shared Google list through the hidden page (replayed from a
/// captured reply), a My Maps KML with folders, the merge/replace offer on a second import, and
/// the NoGoogle refusal while the file path keeps working.
final class SavedImportUITests: VelaUITestCase {
    private let link = "https://www.google.com/maps/placelists/list/IP3Ygq3G8_vrjzxUTTtMspZKVmNcrQ"

    func testGoogleListAndMyMaps() throws {
        let google = try XCTUnwrap(
            Bundle(for: SavedImportUITests.self).url(forResource: "GoogleListFixture", withExtension: "txt"),
            "Google list fixture is not in the UI test bundle")
        let kml = try XCTUnwrap(
            Bundle(for: SavedImportUITests.self).url(forResource: "MyMapsFixture", withExtension: "kml"),
            "My Maps fixture is not in the UI test bundle")

        // 1. A KML file with two folders: each folder is a list, places keep their notes and order.
        var app = launch(camera: "davis", arguments: [
            "-VelaIntentTestReset", "YES",
            "-VelaSavedGoogleFixture", google.path,
            "-VelaSavedKmlFixture", kml.path,
        ])
        app.buttons["saved-open"].tap()
        XCTAssertTrue(app.navigationBars["Saved"].waitForExistence(timeout: 10), "Saved sheet missing")
        resolveDuplicateIfPresent(app)
        let food = app.buttons["Food, 2 places"]
        let sights = app.buttons["Sights, 1 places"]
        XCTAssertTrue(reveal(food, in: app), "KML folder list Food is missing")
        XCTAssertTrue(reveal(sights, in: app), "KML folder list Sights is missing")
        shot("saved-import-mymaps")
        report("saved_kml_lists", 2)

        food.tap()
        XCTAssertTrue(app.navigationBars["Food"].waitForExistence(timeout: 5), "Food list did not open")
        let note = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Bulk bins")).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 5), "the KML note was not kept")
        report("saved_kml_note", "kept")
        app.navigationBars["Food"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Saved"].waitForExistence(timeout: 5), "back to Saved failed")

        // 2. A shared Google list: the hidden page replays the captured reply, order and note kept.
        runGoogleLinkImport(app)
        // A stale list from an interrupted run turns the first import into a replace.
        if app.buttons["saved-import-replace"].waitForExistence(timeout: 3) {
            app.buttons["saved-import-replace"].tap()
        }
        let message = app.staticTexts["saved-import-message"]
        XCTAssertTrue(reveal(message, in: app), "Google import did not finish")
        XCTAssertTrue(message.label.contains("2 places imported into Import Me to Vela!"), message.label)
        let googleRow = app.buttons["Import Me to Vela!, 2 places"]
        XCTAssertTrue(reveal(googleRow, in: app, up: false), "the Google list is missing")
        shot("saved-import-google")
        report("saved_google_places", 2)

        // 3. Importing it again offers merge or replace instead of doubling the list.
        runGoogleLinkImport(app)
        let merge = app.buttons["saved-import-merge"]
        XCTAssertTrue(merge.waitForExistence(timeout: 10), "a duplicate import was not offered a choice")
        let replace = app.buttons["saved-import-replace"]
        XCTAssertTrue(replace.exists, "the choice has no Replace")
        shot("saved-import-merge")
        report("saved_google_duplicate", "merge_or_replace")
        merge.tap()
        XCTAssertTrue(waitUntil(10) { message.exists && message.label.contains("Nothing new") }, message.label)
        XCTAssertTrue(app.buttons["Import Me to Vela!, 2 places"].exists, "Merge doubled the list")
        report("saved_google_merge", "unchanged")

        runGoogleLinkImport(app)
        XCTAssertTrue(replace.waitForExistence(timeout: 10), "no replace offer on the third import")
        replace.tap()
        XCTAssertTrue(waitUntil(10) { app.buttons["Import Me to Vela!, 2 places"].exists },
                      "Replace changed the list count")
        report("saved_google_idempotent", 2)

        // 4. The same KML again asks the same question, and merging keeps both lists as they were.
        app.terminate()
        app = launch(camera: "davis", arguments: [
            "-VelaIntentTestReset", "YES",
            "-VelaSavedKmlFixture", kml.path,
        ])
        app.buttons["saved-open"].tap()
        let kmlMerge = app.buttons["saved-import-merge"]
        XCTAssertTrue(kmlMerge.waitForExistence(timeout: 10), "a duplicate KML import was not offered a choice")
        kmlMerge.tap()
        XCTAssertTrue(app.buttons["Food, 2 places"].waitForExistence(timeout: 10), "Food list changed")
        XCTAssertTrue(app.buttons["Sights, 1 places"].exists, "Sights list changed")
        report("saved_kml_duplicate", "merge_unchanged")
        app.terminate()

        // 5. NoGoogle: the link path explains itself and makes no request; the KML path still works.
        app = launch(camera: "davis", arguments: [
            "-VelaSavedNoGoogle", "YES",
            "-VelaSavedKmlFixture", kml.path,
        ])
        app.buttons["saved-open"].tap()
        XCTAssertTrue(app.buttons["Food, 2 places"].waitForExistence(timeout: 10),
                      "the KML import must work without Google")
        resolveDuplicateIfPresent(app)
        openGoogleLinkSheet(app)
        let blocked = app.staticTexts["saved-import-google-blocked"]
        XCTAssertTrue(blocked.waitForExistence(timeout: 5), "no honest NoGoogle explanation")
        XCTAssertFalse(app.textFields["saved-import-link"].exists, "the link field is offered with Google off")
        shot("saved-import-nogoogle")
        report("saved_nogoogle", "blocked")
        app.buttons["saved-import-link-cancel"].tap()
        let offMessage = app.staticTexts["saved-import-message"]
        XCTAssertTrue(reveal(offMessage, in: app), "the NoGoogle message is missing from Saved")
        XCTAssertTrue(offMessage.label.contains("needs Google"), offMessage.label)

        // Leave the simulator library as the scenario found it.
        for name in ["Import Me to Vela", "Food", "Sights"] { deleteList(app, named: name) }
        app.terminate()
    }

    private func openGoogleLinkSheet(_ app: XCUIApplication) {
        app.buttons["saved-import"].tap()
        let item = app.buttons["saved-import-google"]
        if item.waitForExistence(timeout: 5) {
            item.tap()
        } else {
            app.menuItems["Google Maps list link"].tap()
        }
        XCTAssertTrue(app.textFields["saved-import-link"].waitForExistence(timeout: 5)
                        || app.staticTexts["saved-import-google-blocked"].waitForExistence(timeout: 5),
                      "the link sheet did not open")
    }

    /// Pastes the link and runs it. The import starts from the sheet's onDismiss, so the sheet must
    /// be gone before a merge/replace prompt can appear.
    private func runGoogleLinkImport(_ app: XCUIApplication) {
        openGoogleLinkSheet(app)
        let field = app.textFields["saved-import-link"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "no link field")
        field.tap()
        field.typeText(link)
        app.buttons["saved-import-link-run"].tap()
        XCTAssertTrue(waitUntil(5) { !field.exists }, "the link sheet did not close")
    }

    private func resolveDuplicateIfPresent(_ app: XCUIApplication) {
        let merge = app.buttons["saved-import-merge"]
        guard merge.waitForExistence(timeout: 3) else { return }
        merge.tap()
    }

    /// Scrolls [element] into view; lists in Saved start above the fold on a phone.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, up: Bool = true) -> Bool {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return true }
            if up { app.swipeUp() } else { app.swipeDown() }
            usleep(300_000)
        }
        return element.exists
    }

    private func deleteList(_ app: XCUIApplication, named name: String) {
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "\(name),")).firstMatch
        guard row.exists || reveal(row, in: app, up: false) else { return }
        row.swipeLeft()
        if app.buttons["Delete"].waitForExistence(timeout: 3) { app.buttons["Delete"].tap() }
    }
}
