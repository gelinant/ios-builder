import XCTest

/// SHR-PLACE: what a place share and a route share hand to the iOS share sheet, and the sheet
/// itself. The activity sheet is a remote process, so its contents cannot be queried: the test
/// reads the DEBUG payload mirrored on the share button, then checks the system sheet opened and
/// screenshots it.
final class ShareUITests: VelaUITestCase {
    override func setUp() {
        super.setUp()
        // A remote activity sheet must never hang the runner job: bound the scenario so the
        // script still publishes its log and STATUS.
        executionTimeAllowance = 1200
    }

    func testPlaceShareContentsAndRouteText() throws {
        let placeApp = launch(camera: "davis", arguments: ["-VelaResetSettings", "YES"])
        openPlace(placeApp, query: "Davis Food Co-op")

        let placeShare = placeApp.buttons["place-share"]
        XCTAssertTrue(placeShare.waitForExistence(timeout: 10), "no share action on the place sheet")
        let placeDebug = placeApp.staticTexts["place-share-debug"]
        XCTAssertTrue(placeDebug.waitForExistence(timeout: 10), "no shared place payload")
        let placeMirror = placeDebug.label
        XCTAssertTrue(placeMirror.contains("Davis Food Co-op"), placeMirror)
        XCTAssertTrue(placeMirror.contains(","), "the place text carries no address: \(placeMirror)")
        XCTAssertTrue(placeMirror.contains("https://www.google.com/maps"), placeMirror)
        XCTAssertFalse(placeMirror.contains("goo.gl"), "a short link was fabricated: \(placeMirror)")
        report("share_place_text", placeMirror.replacingOccurrences(of: "\n", with: " / "))

        placeShare.tap()
        let placeSheet = placeApp.otherElements["ActivityListView"]
        XCTAssertTrue(placeSheet.waitForExistence(timeout: 15), "the place share sheet did not open")
        report("share_place_sheet", placeSheet.identifier)
        shot("share-place")
        placeApp.terminate()

        let routeApp = launch(camera: "sf", followUser: true, arguments: ["-VelaResetSettings", "YES"])
        openFirstCoffeeDirections(routeApp)

        let routeShare = routeApp.buttons["route-share"]
        XCTAssertTrue(routeShare.waitForExistence(timeout: 10), "no share action on the route picker")
        let routeDebug = routeApp.staticTexts["route-share-debug"]
        XCTAssertTrue(routeDebug.waitForExistence(timeout: 10), "no shared route payload")
        XCTAssertTrue(waitUntil(10) { routeDebug.label.contains("ETA:") },
                      "the route share has no ETA: \(routeDebug.label)")
        let routeMirror = routeDebug.label
        XCTAssertTrue(routeMirror.contains("Directions from"), routeMirror)
        XCTAssertTrue(routeMirror.contains("Mode: Driving"), routeMirror)
        XCTAssertTrue(routeMirror.contains("ETA:"), routeMirror)
        XCTAssertTrue(routeMirror.contains("https://www.google.com/maps/dir/?api=1&destination="),
                      "no Google directions link: \(routeMirror)")
        XCTAssertFalse(routeMirror.contains("goo.gl"), "a short link was fabricated: \(routeMirror)")
        report("share_route_text", routeMirror.replacingOccurrences(of: "\n", with: " / "))

        routeShare.tap()
        let routeSheet = routeApp.otherElements["ActivityListView"]
        XCTAssertTrue(routeSheet.waitForExistence(timeout: 15), "the route share sheet did not open")
        report("share_route_sheet", routeSheet.identifier)
        shot("share-route")
    }

    /// Opens a named place from the search field and waits for its details.
    private func openPlace(_ app: XCUIApplication, query: String) {
        sleep(4)
        let field = app.textFields["search-field"]
        field.tap()
        field.typeText("\(query)\n")
        let rows = app.buttons.matching(identifier: "search-result")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 60), "no result for \(query)")
        sleep(3)
        rows.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["place-name"].waitForExistence(timeout: 15), "no place sheet")
        let debug = app.staticTexts["place-debug"]
        waitUntil(30) { (debug.exists ? debug.label : "").contains("details=done") }
    }

    /// The first coffee result's Directions, waiting for a driving route and its duration.
    private func openFirstCoffeeDirections(_ app: XCUIApplication) {
        let field = app.textFields["search-field"]
        sleep(4)
        field.tap()
        field.typeText("coffee\n")
        let rows = app.buttons.matching(identifier: "search-result")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 60), "no coffee result")
        sleep(3)
        rows.firstMatch.tap()
        let directions = app.buttons["place-directions"]
        XCTAssertTrue(directions.waitForExistence(timeout: 15), "no Directions button")
        directions.tap()
        XCTAssertTrue(app.otherElements["route-sheet"].waitForExistence(timeout: 10)
            || app.buttons["route-mode-DRIVE"].waitForExistence(timeout: 5), "no route chooser")
        if routeValue(app, "mode") != "DRIVE" {
            app.buttons["route-mode-DRIVE"].tap()
        }
        XCTAssertTrue(waitUntil(90) {
            routeValue(app, "loading") == "0" && (Int(routeValue(app, "routes") ?? "") ?? 0) > 0
        }, "no driving route: \(debugText("route-debug") ?? "missing")")
        let seconds = Int(routeValue(app, "seconds") ?? "") ?? 0
        XCTAssertGreaterThan(seconds, 0, "the route has no duration to share")
    }

    /// One `key=value` word of the route debug line.
    private func routeValue(_ app: XCUIApplication, _ key: String) -> String? {
        guard let line = debugText("route-debug") else { return nil }
        for part in line.split(separator: " ") {
            let pair = part.split(separator: "=", maxSplits: 1)
            if pair.count == 2, pair[0] == key { return String(pair[1]) }
        }
        return nil
    }
}
