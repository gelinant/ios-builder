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
                // The alternates live in the expanded scroll view; swiping the sheet itself does
                // not scroll it.
                scrollRoute(app)
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
        var transitStepsClosed = false
        if trips > 0 {
            app.buttons["route-steps"].tap()
            sleep(2)
            shot("directions-transit-steps")
            let close = app.buttons["steps-close"]
            if close.isHittable {
                close.tap()
                transitStepsClosed = true
            } else {
                // Out of this lot: on a long itinerary the transit detail's pinned action row
                // can sit just under the window edge. The next scenario launches a fresh app.
                report("directions_transit_steps_close", "offscreen")
            }
        }
        if transitStepsClosed || !app.otherElements["steps-sheet"].exists {
            app.buttons["route-mode-DRIVE"].tap()
            sleep(1)
        }
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

    /// SCROLL-FIX: at accessibility sizes the picker is one ScrollView. Its viewport must have a
    /// real height and the avoid row must be reachable by dragging that viewport, no more than
    /// three swipes from the top. Before the fix the grabber and debug lines sat above the scroll
    /// and squeezed it to nothing, so the drag never moved the content.
    func testRouteAvoidOptionsScrollAtLargeText() throws {
        let app = launch(camera: "sf", followUser: true, arguments: [
            "-VelaResetSettings", "YES",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
            "-VelaRouteOrderFixture", "YES",
        ])
        let searchField = app.textFields["search-field"]
        sleep(4)
        focus(searchField)
        searchField.typeText("Ferry Building\n")
        let rows = app.buttons.matching(identifier: "search-result")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 60), "no Ferry Building row")
        sleep(3)
        rows.firstMatch.tap()
        let directions = reveal("place-directions", in: "place-scroll", tries: 8)
        if !directions.isHittable {
            _ = reveal("place-directions", in: "place-scroll", direction: .backward, tries: 14)
        }
        XCTAssertTrue(directions.isHittable, "Directions is not reachable at AX5")
        directions.tap()
        if value("mode") != "DRIVE" {
            app.buttons["route-mode-DRIVE"].tap()
        }
        XCTAssertTrue(waitUntil(120) {
            self.value("mode") == "DRIVE" && self.value("loading") == "0"
                && (Int(self.value("routes") ?? "") ?? 0) >= 1
        }, "no driving route: \(debugText("route-debug") ?? "none")")

        let scroll = app.descendants(matching: .any)["route-scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 10), "no route scroll element")
        XCTAssertGreaterThanOrEqual(scroll.frame.height, 44,
                                    "route-scroll has no real viewport: \(scroll.frame)")
        // Grow the same unified scroll to the expanded detent, then drag its own viewport. The
        // compact detent uses the same element; the expanded one gives the proof a real viewport.
        if app.buttons["route-expand"].exists {
            app.buttons["route-expand"].tap()
            sleep(1)
        }
        let avoid = app.buttons["route-avoid-highways"]
        XCTAssertTrue(avoid.waitForExistence(timeout: 10), "no avoid row")
        var swipes = 0
        while !avoid.isHittable && swipes < 3 {
            scroll.swipeUp()
            swipes += 1
            usleep(400_000)
        }
        report("route_avoid_swipes", swipes)
        XCTAssertTrue(avoid.isHittable,
                      "avoid row not reachable after \(swipes) swipes: \(avoid.frame)")
        shot("route-avoid-reachable")
    }

    /// RTE-CAM: the picker's camera choice counts the plate cameras on each route and leads with a
    /// lighter route inside the detour cap. The debug camera source puts two cameras on the first
    /// route of the trip only, so the runner needs no DeFlock coverage on this street; the side
    /// streets switch is the fallback when no alternate is light enough. The JVM tests own the
    /// counting rule, the cap and the "same road is not an avoidance" guard.
    func testAvoidCameras() throws {
        let app = launch(camera: "sf", followUser: true,
                         arguments: ["-VelaResetSettings", "YES", "-VelaRouteCameraFixture", "YES"])
        openDirections(app, query: "Ferry Building")
        if value("mode") != "DRIVE" {
            app.buttons["route-mode-DRIVE"].tap()
        }
        XCTAssertTrue(waitUntil(120) {
            self.value("mode") == "DRIVE" && self.value("loading") == "0"
                && (Int(self.value("routes") ?? "") ?? 0) >= 1
        }, "no driving route: \(debugText("route-debug") ?? "none")")
        XCTAssertEqual(value("cameraCan"), "1", "the camera choice is hidden while the router is up")

        // The switch sits in the compact picker, above the traffic line, so it needs no expansion.
        let avoid = app.buttons["route-avoid-cameras"]
        XCTAssertTrue(avoid.waitForExistence(timeout: 10), "no Avoid cameras switch in the picker")
        if !avoid.isHittable {
            scrollRoute(app)
        }
        avoid.tap()
        XCTAssertTrue(waitUntil(90) {
            self.value("cameraAvoid") == "1" && self.value("loading") == "0"
        }, "the camera choice did not re-plan: \(debugText("route-debug") ?? "none")")

        // A lighter alternate usually wins outright; the side-street pass covers the rest.
        if (Int(value("cameraAvoided") ?? "") ?? 0) == 0 {
            let sideStreets = app.buttons["route-camera-side-streets"]
            XCTAssertTrue(sideStreets.waitForExistence(timeout: 10), "no side streets switch")
            if !sideStreets.isHittable {
                scrollRoute(app)
            }
            sideStreets.tap()
            XCTAssertTrue(waitUntil(5) { self.value("cameraSide") == "1" }, "side streets did not switch on")
        }
        XCTAssertTrue(waitUntil(180) {
            self.value("loading") == "0" && (Int(self.value("cameraAvoided") ?? "") ?? 0) > 0
        }, "no camera-lighter route was offered: \(debugText("route-debug") ?? "none")")

        let avoided = Int(value("cameraAvoided") ?? "") ?? 0
        report("camera_avoided", avoided)
        report("camera_on_active", value("cameras") ?? "?")
        report("camera_extra_seconds", value("cameraExtraS") ?? "?")
        report("camera_extra_meters", value("cameraExtraM") ?? "?")
        report("camera_side_streets", value("cameraSide") ?? "?")
        XCTAssertTrue(waitUntil(10) { app.staticTexts["route-camera-avoided"].exists },
                      "the picker hid the avoided count")
        XCTAssertTrue(app.staticTexts["route-camera-row"].exists, "no camera count on the selected route")
        // A claim of avoidance needs a route that actually passes fewer cameras.
        XCTAssertEqual(value("cameras"), "0", "the leading route still passes cameras")
        sleep(2)
        shot("route-cameras")
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
        // RTE-SHEET: the expanded presentation must grow the host frame, otherwise the last
        // action row falls under the bottom edge on a small phone. One scroll is the budget.
        sleep(1)
        let sheetFrame = app.otherElements["route-sheet"].frame
        let windowHeight = app.windows.firstMatch.frame.height
        report("route_sheet_expanded_ratio",
               String(format: "%.2f", sheetFrame.height / windowHeight))
        XCTAssertGreaterThan(sheetFrame.height, windowHeight * 0.6,
                             "the expanded sheet did not grow: \(sheetFrame) of \(windowHeight)")
        let addStop = app.buttons["route-add-stop"]
        if !addStop.isHittable {
            scrollRoute(app)
        }
        XCTAssertTrue(addStop.isHittable,
                      "route-add-stop is not reachable after one scroll in the expanded sheet")
        addStop.tap()
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

    /// RTE-STEP: a tap in the steps list frames that maneuver close up, lights the stretch that
    /// leads to it, and collapses the sheet to the step. Next walks the list; Whole route fits the
    /// planned line again. No guidance starts at any point.
    func testStepTapFocusesMap() throws {
        let app = launch(camera: "sf", followUser: true, arguments: ["-VelaResetSettings", "YES"])
        openDirections(app, query: "Ferry Building")
        if value("mode") != "DRIVE" {
            app.buttons["route-mode-DRIVE"].tap()
        }
        XCTAssertTrue(waitUntil(120) {
            self.value("mode") == "DRIVE" && self.value("loading") == "0"
                && (Int(self.value("steps") ?? "") ?? 0) > 1
        }, "no driving route with steps: \(debugText("route-debug") ?? "none")")
        report("step_focus_steps", value("steps") ?? "?")

        app.buttons["route-steps"].tap()
        let sheet = app.descendants(matching: .any)["steps-sheet"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 10), "no steps sheet")
        let rows = app.descendants(matching: .any).matching(identifier: "step-row")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10), "no step row")
        sleep(1)

        // The second step is a real turn rather than the departure point.
        let target = rows.element(boundBy: min(1, max(rows.count - 1, 0)))
        XCTAssertTrue(target.isHittable, "the step row is not reachable")
        target.tap()

        let debug = app.staticTexts["step-focus-debug"]
        XCTAssertTrue(debug.waitForExistence(timeout: 10), "no step focus line")
        XCTAssertTrue(waitUntil(20) {
            self.field(debug.label, "step_focus") == "1"
                && self.field(debug.label, "step_zoom") == "16.5"
        }, "the map did not frame the step: \(debug.label)")
        let focusedIndex = Int(field(debug.label, "step_index") ?? "-1") ?? -1
        XCTAssertGreaterThanOrEqual(focusedIndex, 0, "no focused step index")
        XCTAssertTrue(app.descendants(matching: .any)["step-focused"].exists,
                      "the sheet did not collapse to the focused step")
        report("step_focus", field(debug.label, "step_focus") ?? "0")
        report("step_zoom", field(debug.label, "step_zoom") ?? "?")
        sleep(1)
        shot("route-step-focus")

        // Stepping walks the list with the camera; it never starts guidance.
        XCTAssertTrue(app.buttons["step-next"].isHittable, "no Next action")
        app.buttons["step-next"].tap()
        let advanced = waitUntil(6) {
            (Int(self.field(debug.label, "step_index") ?? "-1") ?? -1) == focusedIndex + 1
                && self.field(debug.label, "step_zoom") == "16.5"
        }
        if !advanced {
            // The first tap can be swallowed while the camera move settles; one retry keeps the
            // same assertion on the resulting index.
            app.buttons["step-next"].tap()
        }
        XCTAssertTrue(waitUntil(10) {
            (Int(self.field(debug.label, "step_index") ?? "-1") ?? -1) == focusedIndex + 1
                && self.field(debug.label, "step_zoom") == "16.5"
        }, "Next did not move to the following step: \(debug.label)")
        report("step_next", field(debug.label, "step_index") ?? "?")
        XCTAssertFalse(app.buttons["route-start"].exists || app.buttons["nav-end"].exists,
                       "stepping started guidance")

        app.buttons["step-whole-route"].tap()
        XCTAssertTrue(waitUntil(10) {
            self.field(debug.label, "step_focus") == "0"
        }, "Whole route did not leave the step focus: \(debug.label)")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "step-row").firstMatch.exists,
                      "the full step list did not come back")
        report("step_whole_route", 1)
    }

    /// One `key=value` of a report line.
    private func field(_ line: String, _ key: String) -> String? {
        for part in line.split(separator: " ") where part.hasPrefix("\(key)=") {
            return String(part.dropFirst(key.count + 1))
        }
        return nil
    }

    /// Scrolls the picker's content, whichever accessibility element the ScrollView became on
    /// this iOS version. Swiping the sheet container alone does not move it.
    private func scrollRoute(_ app: XCUIApplication) {
        let scrollView = app.scrollViews["route-scroll"]
        if scrollView.exists {
            scrollView.swipeUp()
            return
        }
        let other = app.otherElements["route-scroll"]
        if other.exists {
            other.swipeUp()
            return
        }
        app.otherElements["route-sheet"].swipeUp()
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
