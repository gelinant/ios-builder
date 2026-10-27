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
            let alternate = app.buttons.matching(identifier: "route-row").element(boundBy: 1)
            if !alternate.isHittable {
                app.otherElements["route-sheet"].swipeUp()
            }
            alternate.tap()
            sleep(2)
            report("directions_far_selected", value("active") ?? "?")
            shot("directions-far-alt")
        }
        let farSteps = Int(value("steps") ?? "") ?? 0
        app.buttons["route-steps"].tap()
        sleep(2)
        shot("directions-far-steps")
        app.buttons["steps-close"].tap()
        sleep(1)
        // The open router's steps (the hybrid), not Google's one or two abbreviated ones.
        XCTAssertGreaterThan(farSteps, 1, "the drive has \(farSteps) step(s)")

        app.buttons["route-mode-TRANSIT"].tap()
        waitUntil(60) { self.value("mode") == "TRANSIT" && self.value("loading") == "0" }
        let trips = Int(value("transit") ?? "") ?? 0
        report("directions_transit_itineraries", trips)
        report("directions_transit_legs", value("legs") ?? "?")
        print("ROUTE_DEBUG=\(debugText("route-debug") ?? "none")")
        sleep(3)
        shot("directions-transit")
        if trips > 0 {
            app.buttons["route-steps"].tap()
            sleep(2)
            shot("directions-transit-steps")
            app.buttons["steps-close"].tap()
        }
        app.buttons["route-mode-DRIVE"].tap()
        sleep(1)
        XCTAssertGreaterThanOrEqual(trips, 1, "no transit itinerary")
    }

    /// R-1: add a searched stop, verify the waypointed route, then apply a future driving estimate.
    /// The store tests cover reorder/remove and Transitous depart/arrive request parameters.
    func testWaypointAndDepartureTime() throws {
        let app = launch(camera: "sf", followUser: true)
        let searchField = app.textFields["search-field"]
        sleep(4)
        searchField.tap()
        searchField.typeText("Ferry Building\n")
        let rows = app.buttons.matching(identifier: "search-result")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 60), "no Ferry Building row")
        sleep(3)
        rows.firstMatch.tap()
        let directions = app.buttons["place-directions"]
        XCTAssertTrue(directions.waitForExistence(timeout: 15), "no Directions button")
        directions.tap()
        if value("mode") != "DRIVE" {
            app.buttons["route-mode-DRIVE"].tap()
        }
        waitUntil(90) { self.value("loading") == "0" && self.value("mode") == "DRIVE" }
        XCTAssertGreaterThanOrEqual(Int(value("routes") ?? "") ?? 0, 1, "no direct driving route")

        app.buttons["route-add-stop"].tap()
        let placeField = app.textFields["route-place-search-field"]
        XCTAssertTrue(placeField.waitForExistence(timeout: 10), "no stop search field")
        placeField.tap()
        placeField.typeText("Embarcadero Station\n")
        let placeRows = app.buttons.matching(identifier: "route-place-result")
        XCTAssertTrue(placeRows.firstMatch.waitForExistence(timeout: 60), "no stop search result")
        placeRows.firstMatch.tap()
        waitUntil(90) {
            self.value("stops") == "1" && self.value("loading") == "0" && self.value("mode") == "DRIVE"
        }
        let waypointRoutes = Int(value("routes") ?? "") ?? 0
        report("route_waypoints", value("stops") ?? "?")
        report("route_waypoint_routes", waypointRoutes)
        sleep(2)
        shot("route-waypoint")
        XCTAssertGreaterThanOrEqual(waypointRoutes, 1, "no route through the stop")

        app.buttons["route-time-DEPART"].tap()
        XCTAssertTrue(app.buttons["route-time-plus"].waitForExistence(timeout: 5), "no time editor")
        app.buttons["route-time-plus"].tap()
        app.buttons["route-time-apply"].tap()
        waitUntil(10) { self.value("timeMode") == "1" && (Int64(self.value("timeEpoch") ?? "") ?? 0) > 0 }
        report("route_time_mode", value("timeMode") ?? "?")
        report("route_time_epoch", value("timeEpoch") ?? "?")
        if let note = app.staticTexts["route-time-note"].exists ? app.staticTexts["route-time-note"].label : nil {
            report("route_time_note", note.replacingOccurrences(of: " ", with: "_"))
        }
        sleep(2)
        shot("route-depart")
        XCTAssertEqual(value("timeMode"), "1")
        XCTAssertEqual(value("stops"), "1", "the time edit lost the stop")
        app.buttons["route-time-NOW"].tap()
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
