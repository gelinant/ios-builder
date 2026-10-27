import XCTest

/// DG-1 end to end: opt in, record the shared Market Street drive, end it, open the saved trip and
/// its speed profile, then export and diagnostics reach their screens. Screenshots: trips-list.png,
/// trip-detail.png and diagnostics.png.
final class TripsUITests: VelaUITestCase {
    func testRecordDriveAndOpenTrip() throws {
        let app = launch(camera: "sf", followUser: true)

        // Opt in from the trips sheet. The switch is off by default.
        app.buttons["trips-open"].tap()
        let toggle = app.switches["trips-recording-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "no recording switch")
        if (toggle.value as? String) != "1" {
            toggle.tap()
        }
        XCTAssertEqual(toggle.value as? String, "1", "trip recording did not turn on")
        app.buttons["trips-done"].tap()

        // A coffee stop on the Market Street fixture, then Start as in NavUITests.
        let field = app.textFields["search-field"]
        field.tap()
        field.typeText("coffee\n")
        let rows = app.buttons.matching(identifier: "search-result")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 60), "no coffee result")
        sleep(3)
        rows.firstMatch.tap()
        let directions = app.buttons["place-directions"]
        XCTAssertTrue(directions.waitForExistence(timeout: 15), "no Directions button")
        directions.tap()
        if routeValue("mode") != "DRIVE" {
            app.buttons["route-mode-DRIVE"].tap()
        }
        XCTAssertTrue(waitUntil(90) { self.routeValue("loading") == "0" && (Int(self.routeValue("routes") ?? "") ?? 0) > 0 },
                      "no driving route")
        app.buttons["route-start"].tap()
        XCTAssertTrue(waitUntil(15) { self.navValue("nav") == "1" }, "navigation did not start")

        // ci-ipa.sh arms sf-market when nav starts. Let five fixes land so the trip is kept.
        let before = navInt("left") ?? 0
        XCTAssertTrue(waitUntil(25) { (self.navInt("left") ?? before) < before }, "no movement")
        sleep(9)

        app.buttons["nav-end"].tap()
        let confirm = app.buttons["nav-end-confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "no End confirmation")
        confirm.tap()
        XCTAssertTrue(waitUntil(10) { self.navValue("nav") == "0" })

        // The trip is now in the list, named after the destination and dated locally.
        app.buttons["trips-open"].tap()
        let tripRow = element("trip-row")
        XCTAssertTrue(tripRow.waitForExistence(timeout: 15), "no recorded trip in the list")
        XCTAssertFalse(app.staticTexts["trips-empty"].exists)
        shot("trips-list")

        tripRow.tap()
        let detail = element("trip-detail")
        XCTAssertTrue(detail.waitForExistence(timeout: 10), "trip detail did not open")
        let profile = element("trip-speed-profile")
        XCTAssertTrue(profile.waitForExistence(timeout: 10), "no speed profile")
        let fixes = element("trip-fixes")
        XCTAssertTrue(fixes.waitForExistence(timeout: 5), "no fix count")
        report("trip_fixes", fixes.label)
        XCTAssertTrue(element("trip-share-gpx").exists, "no GPX share button")
        XCTAssertTrue(element("trip-trim").exists, "no trim control")
        sleep(5) // let the static map style and the line finish drawing
        shot("trip-detail")

        // Diagnostics is reachable from the same sheet and exports plain text.
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["trips-diagnostics"].tap()
        let diagnostics = app.staticTexts["diagnostics-text"]
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 10), "no diagnostics text")
        XCTAssertTrue(diagnostics.label.contains("Vela diagnostics"))
        XCTAssertTrue(diagnostics.label.contains("calibration "))
        XCTAssertTrue(diagnostics.label.contains("nav sessions "))
        report("diagnostics_lines", diagnostics.label.split(separator: "\n").count)
        shot("diagnostics")
        app.buttons["diagnostics-done"].tap()

        // Leave the simulator clean for the next run.
        let row = element("trip-row")
        if row.exists {
            row.swipeLeft()
            let delete = app.buttons["Delete"].firstMatch
            if delete.waitForExistence(timeout: 5) { delete.tap() }
        }
        report("trips_flow", "recorded_opened_exportable")
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }

    private func routeValue(_ key: String) -> String? {
        guard let line = debugText("route-debug") else { return nil }
        for part in line.split(separator: " ") where part.hasPrefix("\(key)=") {
            return String(part.dropFirst(key.count + 1))
        }
        return nil
    }

    private func navValue(_ key: String) -> String? {
        guard let line = debugText("nav-debug") else { return nil }
        for part in line.split(separator: " ") where part.hasPrefix("\(key)=") {
            return String(part.dropFirst(key.count + 1))
        }
        return nil
    }

    private func navInt(_ key: String) -> Int? {
        navValue(key).flatMap(Int.init)
    }
}
