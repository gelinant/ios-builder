import XCTest

/// Saved-place finishing: independent Home and Work shortcuts, stored route lines and Takeout.
final class SavedFinishingUITests: VelaUITestCase {
    func testHomeAndWorkOpenFromSavedAndMap() {
        let app = launch(
            camera: "sf", followUser: true,
            arguments: ["-VelaIntentTestReset", "YES"])
        let name = openFirstCoffeePlace(app)
        app.buttons["place-lists"].tap()
        let setHome = app.buttons["Set as Home"]
        let setWork = app.buttons["Set as Work"]
        XCTAssertTrue(reveal(setHome, in: app), "no Home action")
        setHome.tap()
        XCTAssertTrue(reveal(setWork, in: app), "no Work action")
        setWork.tap()
        app.buttons["Done"].tap()

        app.buttons["saved-open"].tap()
        shot("saved-home")
        XCTAssertTrue(app.navigationBars["Saved"].waitForExistence(timeout: 5), "Saved sheet missing")
        XCTAssertTrue(app.buttons["shortcut-home"].waitForExistence(timeout: 10), "Home row missing")
        XCTAssertTrue(app.buttons["shortcut-work"].exists, "Work row missing")
        app.buttons["shortcut-home"].tap()
        XCTAssertTrue(app.staticTexts["place-name"].waitForExistence(timeout: 15), "Home did not open")
        XCTAssertEqual(app.staticTexts["place-name"].label, name)
        XCTAssertTrue(app.buttons["place-directions"].exists, "opened Home offers no Directions")

        app.buttons["saved-open"].tap()
        app.buttons["shortcut-work"].tap()
        XCTAssertTrue(app.staticTexts["place-name"].waitForExistence(timeout: 15), "Work did not open")
        XCTAssertEqual(app.staticTexts["place-name"].label, name)
        XCTAssertTrue(app.buttons["place-directions"].exists, "opened Work offers no Directions")
        report("saved_shortcuts", "home_and_work_opened")

        app.buttons["place-close"].tap()
        XCTAssertTrue(app.buttons["map-shortcut-home"].waitForExistence(timeout: 10), "map Home missing")
        app.buttons["map-shortcut-home"].tap()
        XCTAssertTrue(app.otherElements["route-sheet"].waitForExistence(timeout: 15), "map Home did not offer routes")
        report("saved_map_home", "directions_opened")

        app.buttons["route-close"].tap()
        app.buttons["saved-open"].tap()
        app.buttons["shortcut-home-clear"].tap()
        app.buttons["shortcut-work-clear"].tap()
        app.buttons["saved-close"].tap()
    }

    func testSavedLineReopensBesideComputedRoutes() {
        let app = launch(
            camera: "sf", followUser: true,
            arguments: ["-VelaIntentTestReset", "YES"])
        _ = openFirstCoffeePlace(app)
        app.buttons["place-directions"].tap()
        XCTAssertTrue(app.buttons["route-mode-DRIVE"].waitForExistence(timeout: 15), "no route chooser")
        if routeValue("mode") != "DRIVE" { app.buttons["route-mode-DRIVE"].tap() }
        XCTAssertTrue(waitUntil(90) {
            self.routeValue("loading") == "0" && self.routeValue("mode") == "DRIVE"
                && (Int(self.routeValue("routes") ?? "") ?? 0) > 0
        }, "no computed route: \(debugText("route-debug") ?? "missing")")

        app.buttons["saved-open"].tap()
        XCTAssertTrue(app.navigationBars["Saved"].waitForExistence(timeout: 5), "Saved sheet missing")
        XCTAssertTrue(app.buttons["route-save"].waitForExistence(timeout: 10), "no Save route action")
        app.buttons["route-save"].tap()
        let field = app.textFields["saved-name-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "no route name field")
        field.tap()
        if let current = field.value as? String, !current.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        field.typeText("UI Saved Line")
        app.buttons["saved-name-save"].tap()
        let savedRoute = app.buttons["UI Saved Line"].firstMatch
        XCTAssertTrue(reveal(savedRoute, in: app), "saved route row missing")
        savedRoute.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.25)).tap()
        sleep(2)
        print("SAVED_ROUTE_DEBUG=\(debugText("route-debug") ?? "missing")")
        shot("saved-route")

        let savedLine = app.buttons["saved-line-route"].firstMatch
        XCTAssertTrue(savedLine.waitForExistence(timeout: 90), "saved line was not offered")
        // A saved line recomputes its route on open, and OSRM on a shared runner can be slow.
        XCTAssertTrue(waitUntil(120) { self.routeValue("loading") == "0" }, "route offer stayed busy")
        XCTAssertGreaterThanOrEqual(Int(routeValue("routes") ?? "") ?? 0, 2)
        XCTAssertGreaterThanOrEqual(app.buttons.matching(identifier: "route-row").count, 1)
        XCTAssertFalse(app.buttons["route-start"].isEnabled, "a line without steps must not start guidance")
        report("saved_line_routes", routeValue("routes") ?? "?")

        app.buttons.matching(identifier: "route-row").firstMatch.tap()
        XCTAssertTrue(waitUntil(5) { app.buttons["route-start"].isEnabled }, "computed route cannot start")
        app.buttons["saved-open"].tap()
        XCTAssertTrue(reveal(savedRoute, in: app), "saved route missing during cleanup")
        savedRoute.swipeLeft()
        app.buttons["Delete"].firstMatch.tap()
        XCTAssertTrue(waitUntil(10) { !savedRoute.exists }, "saved route deletion failed")
        app.buttons["saved-close"].tap()
    }

    func testTakeoutFixtureImportsIntoNamedList() throws {
        let fixture = try XCTUnwrap(
            Bundle(for: SavedFinishingUITests.self).url(forResource: "TakeoutFixture", withExtension: "csv"),
            "Takeout fixture is not in the UI test bundle")
        let fixtureText = try String(contentsOf: fixture, encoding: .utf8)
        let app = launch(arguments: [
            "-VelaIntentTestReset", "YES",
            "-VelaTakeoutFixture", fixture.path,
            "-VelaTakeoutFixtureText", fixtureText,
        ])
        app.buttons["saved-open"].tap()
        let message = app.staticTexts["saved-import-message"]
        XCTAssertTrue(reveal(message, in: app), "Takeout import did not finish")
        XCTAssertTrue(message.label.contains("2 places imported into TakeoutFixture"), message.label)
        let importedList = app.buttons["TakeoutFixture, 2 places"]
        XCTAssertTrue(reveal(importedList, in: app, up: false), "Takeout list or its rows are missing")
        shot("saved-import")
        report("saved_takeout_places", 2)
    }

    func testListEditingSelectionAndSound() throws {
        let app = launch(
            camera: "sf", followUser: true,
            arguments: ["-VelaIntentTestReset", "YES"])
        let placeName = openFirstCoffeePlace(app)
        app.buttons["place-save"].tap()
        XCTAssertTrue(app.buttons["place-lists"].waitForExistence(timeout: 10), "no place list picker")

        app.buttons["saved-open"].tap()
        XCTAssertTrue(app.navigationBars["Saved"].waitForExistence(timeout: 5), "Saved sheet missing")
        createList(app, named: "UI Finish")
        createList(app, named: "UI Second")
        app.buttons["saved-close"].tap()

        app.buttons["place-lists"].tap()
        let finish = app.buttons["UI Finish"]
        XCTAssertTrue(finish.waitForExistence(timeout: 5), "new list missing from the place picker")
        finish.tap()
        app.buttons["Done"].tap()

        app.buttons["saved-open"].tap()
        let finishRow = app.buttons["UI Finish, 1 places"]
        XCTAssertTrue(reveal(finishRow, in: app), "list row or its place count missing")
        finishRow.tap()

        // Selection mode: one tap picks one row, and the bulk bar replaces the title actions.
        let select = app.buttons["saved-select"].firstMatch
        XCTAssertTrue(select.waitForExistence(timeout: 5), "no Select action")
        select.tap()
        let count = app.staticTexts["saved-selected-count"]
        XCTAssertTrue(count.waitForExistence(timeout: 5), "no selection bar")
        XCTAssertEqual(count.label, "0 selected")
        let row = app.buttons["saved-list-place"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "no list entry to select")
        XCTAssertEqual(row.label, placeName)
        row.tap()
        XCTAssertTrue(waitUntil(5) { count.label == "1 selected" }, "row did not enter the selection")
        shot("saved-selection")
        report("saved_selection", count.label)

        // The editor validates the name and previews a tone from the shared table.
        app.buttons["saved-bulk-done"].tap()
        app.buttons["List actions"].tap()
        app.buttons["Edit list"].tap()
        let nameField = app.textFields["saved-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "no list editor")
        // The choices sit in a custom flow layout, so the element type is not always a button.
        let ping = app.descendants(matching: .any)["list-sound-ping"].firstMatch
        // The editor's Form carries its own identifier: swipe it, not the app behind the sheet.
        let form = app.descendants(matching: .any)["list-editor-form"].firstMatch
        for _ in 0..<10 where !ping.exists {
            if form.exists { form.swipeUp() } else { dragScroll(app) }
        }
        XCTAssertTrue(ping.waitForExistence(timeout: 5), "no sound choices in the editor")
        ping.tap()
        let feedback = app.staticTexts["saved-feedback"]
        for _ in 0..<4 where !feedback.exists { dragScroll(app) }
        XCTAssertTrue(feedback.waitForExistence(timeout: 5), "sound pick produced no feedback")
        XCTAssertTrue(feedback.label.contains("sound ping"), feedback.label)
        shot("saved-editor")

        for _ in 0..<6 where !nameField.isHittable { app.swipeDown() }
        replaceText(in: nameField, with: "")
        let problem = app.staticTexts["list-editor-error"]
        XCTAssertTrue(problem.waitForExistence(timeout: 5), "blank list name was not rejected")
        XCTAssertFalse(app.buttons["saved-name-save"].isEnabled, "Save stayed enabled for a blank name")
        replaceText(in: nameField, with: "UI Finish")
        XCTAssertTrue(waitUntil(5) { app.buttons["saved-name-save"].isEnabled }, "a valid name did not enable Save")
        app.buttons["saved-name-save"].tap()

        // Bulk move to the other list in one action.
        let selectAgain = app.buttons["saved-select"].firstMatch
        XCTAssertTrue(selectAgain.waitForExistence(timeout: 5), "no Select after the editor")
        selectAgain.tap()
        app.buttons["saved-list-place"].firstMatch.tap()
        XCTAssertTrue(waitUntil(5) { app.staticTexts["saved-selected-count"].label == "1 selected" }, "second selection failed")
        app.buttons["saved-bulk-move"].tap()
        let target = app.buttons["Move to UI Second"]
        XCTAssertTrue(target.waitForExistence(timeout: 5), "move menu has no target list")
        target.tap()
        XCTAssertTrue(waitUntil(5) { !app.buttons["saved-list-place"].firstMatch.exists }, "moved row stayed in its old list")
        app.navigationBars.buttons.firstMatch.tap()

        let secondRow = app.buttons["UI Second, 1 places"]
        XCTAssertTrue(reveal(secondRow, in: app), "destination list did not receive the entry")
        report("saved_bulk_move", secondRow.label)

        // Adding a place to a list with a sound plays that sound and records it for the check.
        app.buttons["saved-close"].tap()
        XCTAssertTrue(app.buttons["place-lists"].waitForExistence(timeout: 5), "place sheet did not return")
        app.buttons["place-lists"].tap()
        let finishAgain = app.buttons["UI Finish"]
        XCTAssertTrue(finishAgain.waitForExistence(timeout: 5), "sound list missing from the place picker")
        finishAgain.tap()
        let addFeedback = app.staticTexts["saved-feedback"]
        XCTAssertTrue(addFeedback.waitForExistence(timeout: 5), "adding to a list produced no feedback")
        XCTAssertTrue(addFeedback.label.contains("sound=ping"), addFeedback.label)
        app.buttons["Done"].tap()

        // Clean up both lists so a rerun on the same simulator starts from the same state.
        app.buttons["saved-open"].tap()
        for name in ["UI Finish", "UI Second"] {
            let listRow = app.buttons.matching(identifier: "saved-list").matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
            if reveal(listRow, in: app) {
                listRow.swipeLeft()
                let delete = app.buttons["Delete"].firstMatch
                if delete.waitForExistence(timeout: 3) { delete.tap() }
            }
        }
        app.buttons["saved-close"].tap()
    }

    private func createList(_ app: XCUIApplication, named name: String) {
        let newList = app.buttons["saved-create-list"]
        XCTAssertTrue(reveal(newList, in: app), "no New list action")
        newList.tap()
        let field = app.textFields["saved-name-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "no list editor for \(name)")
        replaceText(in: field, with: name)
        app.buttons["saved-name-save"].tap()
        XCTAssertTrue(waitUntil(5) { app.buttons.matching(identifier: "saved-list").matching(
            NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch.exists }, "list \(name) was not created")
    }

    private func replaceText(in field: XCUIElement, with text: String) {
        field.tap()
        if let current = field.value as? String, !current.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        if !text.isEmpty { field.typeText(text) }
    }

    @discardableResult
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

    private func routeValue(_ key: String) -> String? {
        debugText("route-debug")?.split(separator: " ").first { $0.hasPrefix(key + "=") }?
            .split(separator: "=", maxSplits: 1).last.map(String.init)
    }

    /// A drag that starts low in the window and ends high: the only reliable way to scroll a sheet.
    private func dragScroll(_ app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        start.press(forDuration: 0.05, thenDragTo: end)
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
