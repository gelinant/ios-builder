import XCTest

/// M4 end to end: from the San Francisco fixture location (set by ci-ipa.sh), "coffee", the first
/// result's Directions, the driving routes on the map and in the chooser, then walking, then the
/// steps. Needs the network.
final class DirectionsUITests: VelaUITestCase {
    func testDirectionsToTheFirstCoffeeResult() throws {
        let app = launch(camera: "sf", followUser: true, arguments: ["-VelaResetSettings", "YES"])
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
        XCTAssertTrue(waitUntil(10) { !app.buttons["route-close"].exists }, "the route chooser did not close")
        // Closing the route shows the place sheet again; its 55 % panel plus the debug overlay
        // lifts the search bar under the status bar, where taps miss. Close it first.
        if app.buttons["place-close"].exists {
            app.buttons["place-close"].tap()
            sleep(2)
        }
        XCTAssertTrue(waitUntil(10) { app.buttons["search-clear"].isHittable }, "the search bar stayed covered")
        app.buttons["search-clear"].tap()
        sleep(1)
        focus(searchField)
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
        // The picker opens compact: the alternates and the stop editor live in the expanded sheet.
        expandRoute(app)
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

    /// RTE-PICKER: the compact picker and the expanded sheet, in the same order with the same
    /// Start/Steps actions, plus the traffic row that asks Google only after the tap. The JVM
    /// test owns the gate; this scenario proves the two presentations and the on-demand request.
    func testRoutePickerStyleAndTrafficOnDemand() throws {
        let app = launch(camera: "sf", followUser: true, arguments: ["-VelaResetSettings", "YES"])
        openDirections(app, query: "Ferry Building")
        if value("mode") != "DRIVE" {
            app.buttons["route-mode-DRIVE"].tap()
        }
        XCTAssertTrue(waitUntil(120) {
            self.value("mode") == "DRIVE" && self.value("loading") == "0"
                && (Int(self.value("routes") ?? "") ?? 0) >= 1
        }, "no driving route: \(debugText("route-debug") ?? "none")")
        report("picker_traffic_on_tap", value("trafficOnTap") ?? "?")
        report("picker_traffic_requested_before", value("trafficRequested") ?? "?")
        XCTAssertEqual(value("trafficOnTap"), "1", "traffic on demand is off")
        XCTAssertEqual(value("trafficRequested"), "0", "the first drive already asked Google for traffic")

        // Presentation 1: the compact picker over the map. The traffic row is part of it.
        XCTAssertTrue(app.otherElements["route-compact"].waitForExistence(timeout: 10),
                      "no compact picker")
        XCTAssertTrue(app.buttons["route-start"].exists && app.buttons["route-steps"].exists,
                      "the compact picker lost an action")
        let showTraffic = app.buttons["route-traffic-show"]
        XCTAssertTrue(showTraffic.waitForExistence(timeout: 10), "no Show traffic row")
        sleep(2)
        shot("route-picker-compact")

        // "Show traffic" opens the gate and re-plans once; the live claim comes only from Google.
        if !showTraffic.isHittable {
            app.otherElements["route-sheet"].swipeUp()
        }
        showTraffic.tap()
        XCTAssertTrue(waitUntil(90) {
            self.value("trafficRequested") == "1" && self.value("loading") == "0"
                && (Int(self.value("routes") ?? "") ?? 0) >= 1
        }, "Show traffic did not re-plan: \(debugText("route-debug") ?? "none")")
        let live = value("trafficLive") ?? "0"
        report("picker_traffic_live", live)
        if live == "1" {
            XCTAssertTrue(app.staticTexts["route-traffic-live"].exists, "a live time with no live label")
        } else {
            XCTAssertFalse(app.staticTexts["route-traffic-live"].exists,
                           "the picker claimed live traffic without it")
            XCTAssertTrue(app.staticTexts["route-traffic-typical"].exists,
                          "no honest traffic status after the tap")
        }
        XCTAssertFalse(app.buttons["route-traffic-show"].exists, "the traffic offer did not go away")
        sleep(2)
        shot("route-picker-traffic")

        // Presentation 2: the expanded sheet keeps the same order and the same actions.
        app.buttons["route-expand"].tap()
        XCTAssertTrue(app.otherElements["route-expanded"].waitForExistence(timeout: 10),
                      "the expanded sheet did not open")
        XCTAssertTrue(app.buttons["route-start"].exists && app.buttons["route-steps"].exists,
                      "the expanded sheet lost an action")
        XCTAssertTrue(app.buttons["route-avoid-tolls"].waitForExistence(timeout: 5),
                      "the expanded sheet lost the avoid keys")
        let alternatives = app.buttons.matching(identifier: "route-row").count
        report("picker_expanded_alternatives", alternatives)
        if alternatives > 1 {
            XCTAssertTrue(app.staticTexts.matching(identifier: "route-rank").count >= 1,
                          "no fastest/slower label on the alternates")
        }
        sleep(2)
        shot("route-picker-expanded")
        app.buttons["route-expand"].tap()
    }

    /// R-1: add a searched stop, verify the waypointed route, then apply a future driving estimate.
    /// The store tests cover reorder/remove and Transitous depart/arrive request parameters.
    func testWaypointAndDepartureTime() throws {
        let app = launch(camera: "sf", followUser: true, arguments: ["-VelaResetSettings", "YES"])
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

        expandRoute(app)
        if !app.buttons["route-add-stop"].isHittable {
            app.otherElements["route-sheet"].swipeUp()
        }
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

        if !app.buttons["route-time-DEPART"].isHittable {
            app.otherElements["route-sheet"].swipeDown()
        }
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

    /// The compact picker is the default; rows, stops and avoids are in the expanded sheet.
    private func expandRoute(_ app: XCUIApplication) {
        guard !app.otherElements["route-expanded"].exists else { return }
        let toggle = app.buttons["route-expand"]
        guard toggle.waitForExistence(timeout: 5) else { return }
        toggle.tap()
        XCTAssertTrue(app.otherElements["route-expanded"].waitForExistence(timeout: 10),
                      "the route sheet did not expand")
    }

    /// One `key=value` of the chooser's debug line.
    private func value(_ key: String) -> String? {        guard let line = debugText("route-debug") else { return nil }
        for part in line.split(separator: " ") where part.hasPrefix("\(key)=") {
            return String(part.dropFirst(key.count + 1))
        }
        return nil
    }

    /// R-2: bicycle routing reaches the safety-weighted Valhalla profile, shows its chooser note
    /// and comes back with at least one route. The JVM tests own the request body and fallback.
    func testBikeRouteUsesTheSafetyProfile() throws {
        let app = launch(camera: "sf", followUser: true, arguments: ["-VelaResetSettings", "YES"])
        openDirections(app, query: "Ferry Building")
        app.buttons["route-mode-BICYCLE"].tap()
        waitUntil(120) { self.value("mode") == "BICYCLE" && self.value("loading") == "0" }
        let routes = Int(value("routes") ?? "") ?? 0
        report("bike_routes", routes)
        report("bike_seconds", value("seconds") ?? "?")
        report("bike_meters", value("meters") ?? "?")
        report("bike_steps", value("steps") ?? "?")
        report("bike_safe", value("bikeSafe") ?? "?")
        if let note = app.staticTexts["route-bike-safe"].exists ? app.staticTexts["route-bike-safe"].label : nil {
            report("bike_note", note.replacingOccurrences(of: " ", with: "_"))
        }
        sleep(3)
        shot("route-bike")
        XCTAssertGreaterThanOrEqual(routes, 1, "no bicycle route: \(debugText("route-debug") ?? "none")")
        XCTAssertEqual(value("bikeSafe"), "1")
    }

    /// R-2: with "Use Vela without Google" on, a drive routes through the open services and the
    /// debug request counter shows zero Google hosts since the chooser opened.
    func testNoGoogleDriveNeverAsksGoogle() throws {
        let app = launch(camera: "sf", followUser: true, arguments: ["-VelaResetSettings", "YES"])
        openSettings(app)
        setGoogleSwitch(true, in: app)
        app.buttons["settings-done"].tap()
        XCTAssertTrue(app.textFields["search-field"].waitForExistence(timeout: 10), "no map after settings")
        openDirections(app, query: "Ferry Building")
        if value("mode") != "DRIVE" {
            app.buttons["route-mode-DRIVE"].tap()
        }
        waitUntil(120) { self.value("mode") == "DRIVE" && self.value("loading") == "0" }
        let routes = Int(value("routes") ?? "") ?? 0
        let google = Int(value("netGoogle") ?? "-1") ?? -1
        let open = Int(value("netOpen") ?? "0") ?? 0
        report("nogoogle_routes", routes)
        report("nogoogle_google_requests", google)
        report("nogoogle_open_requests", open)
        report("nogoogle_flag", value("googleOff") ?? "?")
        report("nogoogle_seconds", value("seconds") ?? "?")
        sleep(3)
        shot("route-nogoogle")
        XCTAssertEqual(value("googleOff"), "1", "Google switch did not reach the router")
        XCTAssertGreaterThanOrEqual(routes, 1, "no drive route without Google: \(debugText("route-debug") ?? "none")")
        XCTAssertEqual(google, 0, "a Google request was made with NoGoogle on")
        XCTAssertGreaterThan(open, 0, "no open service was asked")
        // Leave the switch off for the scenarios that follow.
        app.buttons["route-close"].tap()
        XCTAssertTrue(waitUntil(10) { !app.buttons["route-close"].exists }, "the route chooser did not close")
        if app.buttons["place-close"].exists {
            app.buttons["place-close"].tap()
            sleep(2)
        }
        openSettings(app)
        setGoogleSwitch(false, in: app)
        app.buttons["settings-done"].tap()
    }

    private func openDirections(_ app: XCUIApplication, query: String) {
        let searchField = app.textFields["search-field"]
        sleep(4)
        focus(searchField)
        searchField.typeText("\(query)\n")
        let rows = app.buttons.matching(identifier: "search-result")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 60), "no result row for \(query)")
        sleep(3)
        rows.firstMatch.tap()
        let directions = app.buttons["place-directions"]
        XCTAssertTrue(directions.waitForExistence(timeout: 15), "no Directions button")
        directions.tap()
        XCTAssertTrue(app.otherElements["route-sheet"].waitForExistence(timeout: 10)
            || app.buttons["route-mode-DRIVE"].waitForExistence(timeout: 5), "no route chooser")
    }

    private func openSettings(_ app: XCUIApplication) {
        XCTAssertTrue(waitUntil(10) { app.buttons["map-overflow"].isHittable }, "the map overflow stayed covered")
        app.buttons["map-overflow"].tap()
        XCTAssertTrue(app.buttons["settings-menu-item"].waitForExistence(timeout: 5))
        app.buttons["settings-menu-item"].tap()
        XCTAssertTrue(app.staticTexts["settings-debug"].waitForExistence(timeout: 15), "settings did not open")
    }

    private func setGoogleSwitch(_ on: Bool, in app: XCUIApplication) {
        let toggle = app.switches["settings-no-google"]
        if !toggle.waitForExistence(timeout: 3) {
            // The Form is lazy: the Privacy section below the voice settings is not in the
            // accessibility tree until it is scrolled into view.
            app.swipeUp()
        }
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "no Google switch: \(debugText("settings-debug") ?? "missing")")
        let target = on ? "1" : "0"
        if !waitUntil(2, { String(describing: toggle.value ?? "") == target }) {
            toggle.tap()
        }
        if !waitUntil(5, { String(describing: toggle.value ?? "") == target }) {
            // Fall back to the knob when the switch accessibility action does not reach SwiftUI.
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)).tap()
        }
        XCTAssertTrue(waitUntil(10, { String(describing: toggle.value ?? "") == target }),
                      "Google switch did not change: \(String(describing: toggle.value ?? "missing"))")
    }

    /// Taps [field] until the software keyboard is up, so `typeText` cannot race a dismissed
    /// search field after a sheet closes.
    private func focus(_ field: XCUIElement) {
        for _ in 0..<3 {
            field.tap()
            if app.keyboards.count > 0 { return }
            sleep(1)
        }
    }
}
