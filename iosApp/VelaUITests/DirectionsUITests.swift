import XCTest

/// M4 end to end: from the San Francisco fixture location (set by ci-ipa.sh), "coffee", the first
/// result's Directions, the driving routes on the map and in the chooser, then walking, then the
/// steps. Needs the network.
final class DirectionsUITests: VelaUITestCase {
    func testDirectionsToTheFirstCoffeeResult() throws {
        let app = launch(camera: "sf", followUser: true)
        let searchField = app.textFields["search-field"]
        sleep(4)
        searchField.tap()
        searchField.typeText("coffee\n")

        let rows = app.buttons.matching(identifier: "search-result")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 60), "no result row")
        sleep(3)
        rows.firstMatch.tap()
        let directions = app.buttons["place-directions"]
        XCTAssertTrue(directions.waitForExistence(timeout: 15), "no Directions button")
        directions.tap()
        XCTAssertTrue(app.otherElements["route-sheet"].waitForExistence(timeout: 10)
            || app.buttons["route-mode-DRIVE"].waitForExistence(timeout: 5), "no route chooser")

        // The mode is sticky across launches: start from driving.
        if value("mode") != "DRIVE" {
            app.buttons["route-mode-DRIVE"].tap()
        }
        waitUntil(90) { self.value("loading") == "0" && self.value("mode") == "DRIVE" }
        let driveRoutes = Int(value("routes") ?? "") ?? 0
        report("directions_center", value("center") ?? "?")
        report("directions_drive_routes", driveRoutes)
        report("directions_drive_seconds", value("seconds") ?? "?")
        report("directions_drive_meters", value("meters") ?? "?")
        report("directions_drive_steps", value("steps") ?? "?")
        report("directions_drive_traffic_spans", value("traffic") ?? "?")
        if let message = app.staticTexts["route-message"].exists ? app.staticTexts["route-message"].label : nil {
            report("directions_message", message.replacingOccurrences(of: " ", with: "_"))
        }
        print("ROUTE_DEBUG=\(debugText("route-debug") ?? "none")")
        sleep(3)
        shot("directions-drive")
        XCTAssertGreaterThanOrEqual(driveRoutes, 1, "no driving route")

        app.buttons["route-mode-WALK"].tap()
        waitUntil(90) { self.value("mode") == "WALK" && self.value("loading") == "0" }
        let walkRoutes = Int(value("routes") ?? "") ?? 0
        report("directions_walk_routes", walkRoutes)
        report("directions_walk_seconds", value("seconds") ?? "?")
        report("directions_walk_meters", value("meters") ?? "?")
        sleep(3)
        shot("directions-walk")

        if walkRoutes > 0 {
            app.buttons["route-steps"].tap()
            XCTAssertTrue(app.otherElements["steps-sheet"].waitForExistence(timeout: 10)
                || app.buttons["steps-close"].waitForExistence(timeout: 5), "no steps sheet")
            sleep(2)
            report("directions_walk_steps", app.descendants(matching: .any).matching(identifier: "step-row").count)
            shot("directions-steps")
            app.buttons["steps-close"].tap()
        }
        XCTAssertGreaterThanOrEqual(walkRoutes, 1, "no walking route")
        // Back to driving so the next launch starts there too.
        app.buttons["route-mode-DRIVE"].tap()
        sleep(1)

        // The nearest coffee can be across the street: a longer drive, to the Ferry Building.
        app.buttons["route-close"].tap()
        sleep(1)
        app.buttons["search-clear"].tap()
        sleep(1)
        searchField.tap()
        searchField.typeText("Ferry Building\n")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 60), "no Ferry Building row")
        sleep(3)
        rows.firstMatch.tap()
        XCTAssertTrue(directions.waitForExistence(timeout: 15), "no Directions button")
        directions.tap()
        waitUntil(90) { self.value("loading") == "0" && self.value("mode") == "DRIVE" }
        report("directions_far_routes", value("routes") ?? "?")
        report("directions_far_seconds", value("seconds") ?? "?")
        report("directions_far_meters", value("meters") ?? "?")
        report("directions_far_steps", value("steps") ?? "?")
        report("directions_far_traffic_spans", value("traffic") ?? "?")
        sleep(3)
        shot("directions-far")
        if Int(value("routes") ?? "") ?? 0 > 1 {
            app.buttons.matching(identifier: "route-row").element(boundBy: 1).tap()
            sleep(2)
            report("directions_far_selected", value("active") ?? "?")
            shot("directions-far-alt")
        }
        app.buttons["route-steps"].tap()
        sleep(2)
        shot("directions-far-steps")
    }

    /// One `key=value` of the chooser's debug line.
    private func value(_ key: String) -> String? {
        guard let line = debugText("route-debug") else { return nil }
        for part in line.split(separator: " ") where part.hasPrefix("\(key)=") {
            return String(part.dropFirst(key.count + 1))
        }
        return nil
    }
}
