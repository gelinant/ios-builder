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
        XCTAssertTrue(waitUntil(30) { self.routeValue("loading") == "0" }, "route offer stayed busy")
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

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, up: Bool = true) -> Bool {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return true }
            if up { app.swipeUp() } else { app.swipeDown() }
            usleep(300_000)
        }
        return element.exists
    }
}
