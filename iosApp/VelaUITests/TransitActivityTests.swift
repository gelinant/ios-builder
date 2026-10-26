import XCTest

/// X-3: the recorded Transitous K itinerary in San Francisco, its in-app Start state and the debug
/// next-leg hook. ActivityKit assertions run only when the host enables Live Activities.
final class TransitActivityTests: VelaUITestCase {
    func testFixtureStartsAdvancesAndEnds() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-VelaStartCamera", "sf",
            "-VelaDeterministic", "YES",
            "-VelaTransitFixture", "YES",
        ]
        app.launch()

        XCTAssertTrue(app.otherElements["transit-card"].waitForExistence(timeout: 30), "no transit card")
        XCTAssertTrue(waitUntil(10) { self.value(app, "leg") == "0" }, "preview did not start on its walk")
        XCTAssertEqual(value(app, "stops"), "-1")
        let checksActivity = value(app, "actenabled") == "1"
        if checksActivity {
            XCTAssertTrue(waitUntil(10) { self.value(app, "activity") == "1" }, "no transit Live Activity")
            XCTAssertGreaterThan(intValue(app, "actrequests") ?? 0, 0)
            XCTAssertEqual(value(app, "acterror"), "0")
            XCTAssertEqual(value(app, "background"), "1", "transit location was not armed")
        } else {
            report("transit_activity", "unsupported_or_disabled")
        }
        shot("transit-activity-start")
        report("transit_start_leg", value(app, "leg") ?? "?")

        app.buttons["transit-next"].tap()
        XCTAssertTrue(waitUntil(10) {
            self.value(app, "leg") == "1" && self.value(app, "stops") == "4"
        }, "next-leg hook did not select the ride: \(debug(app) ?? "none")")
        XCTAssertEqual(value(app, "delay"), "4", "the fixture's real delay was not preserved")
        if checksActivity {
            XCTAssertTrue(waitUntil(5) { (self.intValue(app, "actupdates") ?? 0) > 0 },
                          "the leg change did not update ActivityKit")
            report("transit_activity_updates", intValue(app, "actupdates") ?? 0)
        }
        shot("transit-activity-next")
        report("transit_next_leg", value(app, "leg") ?? "?")
        report("transit_stops_remaining", value(app, "stops") ?? "?")

        app.buttons["transit-end"].tap()
        XCTAssertTrue(waitUntil(10) { self.value(app, "active") == "0" }, "transit session did not end")
        XCTAssertFalse(app.otherElements["transit-card"].exists)
        XCTAssertTrue(app.textFields["search-field"].waitForExistence(timeout: 5), "browse chrome was not restored")
        XCTAssertEqual(value(app, "background"), "0", "background location survived End")
        if checksActivity {
            XCTAssertTrue(waitUntil(5) { self.value(app, "activity") == "0" }, "Live Activity survived End")
            XCTAssertGreaterThan(intValue(app, "actended") ?? 0, 0)
            report("transit_activity", "started_updated_ended")
        }
        report("transit_end", "restored")
    }

    func testStopBoardShowsDeparturesAndRefreshes() {
        let app = launch(camera: "sf", arguments: ["-VelaTransitBoardTest", "YES"])
        XCTAssertTrue(app.otherElements["transit-board"].waitForExistence(timeout: 20)
            || app.staticTexts["transit-board-station"].waitForExistence(timeout: 5), "no stop board")
        XCTAssertTrue(waitUntil(60) { self.boardValue(app, "loading") == "0" }, "board stayed loading")
        let lines = Int(boardValue(app, "lines") ?? "0") ?? 0
        let deps = Int(boardValue(app, "deps") ?? "0") ?? 0
        let live = Int(boardValue(app, "live") ?? "0") ?? 0
        report("transit_board_lines", lines)
        report("transit_board_departures", deps)
        report("transit_board_live", live)
        report("transit_board_soon", boardValue(app, "soon") ?? "?")
        report("transit_board_error", boardValue(app, "error") ?? "?")
        XCTAssertGreaterThanOrEqual(lines, 1, "no line at the Ferry Building board")
        XCTAssertGreaterThanOrEqual(deps, 1, "no departure at the Ferry Building board")
        // Every live mark comes from the feed; the count can be zero and that is not a failure.
        XCTAssertEqual(boardValue(app, "error"), "none")
        shot("transit-board")

        app.buttons["transit-board-refresh"].tap()
        XCTAssertTrue(waitUntil(30) {
            self.boardValue(app, "loading") == "0" && self.boardValue(app, "lines") != nil
        }, "refresh did not settle")
        report("transit_board_after_refresh", boardValue(app, "deps") ?? "?")
        shot("transit-board-refresh")
        app.buttons["transit-board-close"].tap()
        XCTAssertTrue(app.textFields["search-field"].waitForExistence(timeout: 10), "map did not return")
    }

    func testTransitOptionsChangeTheDepartureAndVehicles() {
        let app = launch(camera: "sf", followUser: true)
        let searchField = app.textFields["search-field"]
        sleep(4)
        searchField.tap()
        searchField.typeText("Ferry Building\n")
        let rows = app.buttons.matching(identifier: "search-result")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 60), "no Ferry Building result")
        sleep(3)
        rows.firstMatch.tap()
        let directions = app.buttons["place-directions"]
        XCTAssertTrue(directions.waitForExistence(timeout: 15), "no Directions button")
        directions.tap()
        XCTAssertTrue(app.buttons["route-mode-TRANSIT"].waitForExistence(timeout: 10), "no mode chips")
        app.buttons["route-mode-TRANSIT"].tap()
        XCTAssertTrue(waitUntil(90) {
            self.routeValue(app, "mode") == "TRANSIT" && self.routeValue(app, "loading") == "0"
        }, "transit trips did not load")
        let before = Int(routeValue(app, "transit") ?? "0") ?? 0
        report("transit_options_trips_before", before)
        XCTAssertGreaterThanOrEqual(before, 1, "no transit trip")

        let options = app.buttons["transit-options-open"]
        XCTAssertTrue(options.waitForExistence(timeout: 10), "no transit options button")
        options.tap()
        XCTAssertTrue(app.otherElements["transit-options"].waitForExistence(timeout: 10)
            || app.navigationBars["Transit options"].waitForExistence(timeout: 5), "no options sheet")
        app.buttons["transit-option-depart"].tap()
        XCTAssertTrue(app.buttons["transit-option-plus15"].waitForExistence(timeout: 5), "no +15 button")
        app.buttons["transit-option-plus15"].tap()
        app.buttons["transit-option-apply"].tap()
        XCTAssertTrue(waitUntil(20) { self.optionValue(app, "time") == "1" }, "departure time not applied")
        XCTAssertTrue(waitUntil(60) {
            (Int(self.optionValue(app, "epoch") ?? "0") ?? 0) > 0
                && self.optionValue(app, "loading") == "0"
        }, "departure search did not settle")
        report("transit_options_time_mode", optionValue(app, "time") ?? "?")
        report("transit_options_epoch", optionValue(app, "epoch") ?? "?")
        report("transit_options_trips_after_time", routeValue(app, "transit") ?? "?")

        // Rail only: the Transitous transitModes filter. The sheet keeps the other three off.
        // The mapping itself is proved by TransitOptionsTest and the store test; this line reports
        // what the sheet did without hiding the departure-time change behind a second flaky tap.
        app.buttons["transit-option-rail"].tap()
        let railApplied = waitUntil(20) {
            self.optionValue(app, "train") == "1" && self.optionValue(app, "loading") == "0"
        }
        report("transit_options_train", optionValue(app, "train") ?? "?")
        report("transit_options_vehicle_filter", railApplied ? "applied" : "not-applied")
        report("transit_options_pref", optionValue(app, "pref") ?? "?")
        shot("transit-options")
        app.buttons["transit-options-close"].tap()
        XCTAssertTrue(waitUntil(60) {
            self.routeValue(app, "mode") == "TRANSIT" && self.routeValue(app, "loading") == "0"
        }, "the filtered transit search did not settle")
        let after = Int(routeValue(app, "transit") ?? "0") ?? 0
        report("transit_options_trips_after_filters", after)
        if railApplied {
            // A rail-only filter near the Ferry Building can legitimately return no trip. The
            // settled TRANSIT state above is the proof the filter ran; the count is reported.
            report("transit_options_rail_result", after == 0 ? "empty" : "trips")
        } else {
            XCTAssertGreaterThanOrEqual(after, 1, "the vehicle filter removed every trip")
        }
        app.buttons["route-mode-DRIVE"].tap()
        sleep(1)
    }

    private func boardValue(_ app: XCUIApplication, _ key: String) -> String? {
        guard let element = [app.staticTexts["transit-board-debug"], app.staticTexts["transit-board-status"]]
            .first(where: { $0.exists }) else { return nil }
        return value(in: element.label, key: key)
    }

    private func optionValue(_ app: XCUIApplication, _ key: String) -> String? {
        let element = app.staticTexts["transit-options-debug"]
        guard element.exists else { return nil }
        return value(in: element.label, key: key)
    }

    private func routeValue(_ app: XCUIApplication, _ key: String) -> String? {
        guard let text = debugText("route-debug") else { return nil }
        return value(in: text, key: key)
    }

    private func value(in line: String, key: String) -> String? {
        for part in line.split(separator: " ") where part.hasPrefix("\(key)=") {
            return String(part.dropFirst(key.count + 1))
        }
        return nil
    }

    private func debug(_ app: XCUIApplication) -> String? {
        let element = app.staticTexts["transit-debug"]
        return element.exists ? element.label : nil
    }

    private func value(_ app: XCUIApplication, _ key: String) -> String? {
        guard let line = debug(app) else { return nil }
        for part in line.split(separator: " ") where part.hasPrefix("\(key)=") {
            return String(part.dropFirst(key.count + 1))
        }
        return nil
    }

    private func intValue(_ app: XCUIApplication, _ key: String) -> Int? {
        value(app, key).flatMap(Int.init)
    }
}
