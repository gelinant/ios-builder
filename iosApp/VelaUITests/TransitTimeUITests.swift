import XCTest

/// TIME-1: the one time control in the surfaces a traveller meets. The first launch drives the
/// recorded transit fixtures, so the board and the trip screen need no feed; the second launch
/// searches a real place for the route sheet and the transit options, as the Directions and
/// Transit scenarios already do on the runner.
///
/// Each phase proves three things: the control is the shared one, Apply changes the query, and the
/// line under the buttons names the moment the query was sent.
final class TransitTimeUITests: VelaUITestCase {
    private func value(in line: String?, _ key: String) -> String? {
        guard let line else { return nil }
        for part in line.split(separator: " ") {
            let pair = part.split(separator: "=", maxSplits: 1)
            if pair.count == 2 && pair[0] == Substring(key) { return String(pair[1]) }
        }
        return nil
    }

    private func routeValue(_ app: XCUIApplication, _ key: String) -> String? {
        value(in: app.staticTexts["route-debug"].exists ? app.staticTexts["route-debug"].label : nil, key)
    }

    func testTimeEverywhere() {
        let app = XCUIApplication()

        // 1. The stop board, on the cached fixture so the phased board is deterministic.
        app.launchArguments = [
            "-VelaStartCamera", "sf",
            "-VelaDeterministic", "YES",
            "-VelaTransitFixture", "YES",
            "-VelaTransitBoardOfflineTest", "YES",
        ]
        app.launch()
        // The board sheet is published as a container, so match it by identifier whatever its type.
        let board = app.descendants(matching: .any)["transit-board"]
        XCTAssertTrue(board.waitForExistence(timeout: 40)
            || app.staticTexts["transit-board-station"].waitForExistence(timeout: 5),
                      "the cached board never opened")
        let boardDepart = app.buttons["transit-board-time-depart"]
        XCTAssertTrue(boardDepart.waitForExistence(timeout: 20), "the board has no time control")
        boardDepart.tap()
        XCTAssertTrue(app.buttons["transit-board-time-plus"].waitForExistence(timeout: 5),
                      "the board control has no +15")
        app.buttons["transit-board-time-plus"].tap()
        app.buttons["transit-board-time-apply"].tap()
        let boardQuery = app.staticTexts["transit-board-time-query"]
        XCTAssertTrue(boardQuery.waitForExistence(timeout: 10), "the board names no query time")
        XCTAssertTrue(boardQuery.label.contains("Depart at"), "the board query is not a departure")
        report("time_board_query", boardQuery.label.replacingOccurrences(of: " ", with: "_"))
        shot("time-board")
        app.buttons["transit-board-close"].tap()
        XCTAssertTrue(app.otherElements["transit-card"].waitForExistence(timeout: 20),
                      "the guidance card did not return")

        // 2. The trip screen on the recorded fixture: the segment's Leave later and then the
        // shared control at the top. Both answer above the cards.
        app.buttons["transit-trip-open"].tap()
        XCTAssertTrue(app.buttons["transit-trip-close"].waitForExistence(timeout: 20), "no trip screen")
        let ride = app.buttons.matching(identifier: "transit-trip-segment")
            .matching(NSPredicate(format: "label CONTAINS 'Tram K'"))
        XCTAssertTrue(ride.firstMatch.waitForExistence(timeout: 10), "no K ride card")
        let tripScroll = app.scrollViews["transit-trip-scroll"]
        for _ in 0..<6 where !ride.firstMatch.isHittable {
            if tripScroll.exists { tripScroll.swipeUp() } else { app.swipeUp() }
        }
        XCTAssertTrue(ride.firstMatch.isHittable, "the K ride card never came on screen")
        ride.firstMatch.tap()
        let leaveLater = app.buttons["transit-trip-leave-later"]
        for _ in 0..<6 where !leaveLater.isHittable {
            if tripScroll.exists { tripScroll.swipeUp() } else { app.swipeUp() }
        }
        XCTAssertTrue(leaveLater.isHittable, "the segment actions never came on screen")
        leaveLater.tap()
        app.buttons["transit-trip-later-15"].tap()
        let segmentQuery = app.staticTexts["transit-trip-options-query"]
        XCTAssertTrue(segmentQuery.waitForExistence(timeout: 10),
                      "the segment answer is not above the cards")
        XCTAssertTrue(segmentQuery.label.contains("Depart at"), "the segment answer is not a departure")
        report("time_segment_query", segmentQuery.label.replacingOccurrences(of: " ", with: "_"))
        shot("time-segment")

        let tripDepart = app.buttons["transit-trip-time-depart"]
        XCTAssertTrue(tripDepart.waitForExistence(timeout: 10), "the trip has no time control")
        tripDepart.tap()
        app.buttons["transit-trip-time-plus"].tap()
        app.buttons["transit-trip-time-apply"].tap()
        let tripQuery = app.staticTexts["transit-trip-time-query"]
        XCTAssertTrue(tripQuery.waitForExistence(timeout: 10), "the trip names no query time")
        XCTAssertTrue(tripQuery.label.contains("Depart at"), "the trip query is not a departure")
        report("time_trip_query", tripQuery.label.replacingOccurrences(of: " ", with: "_"))
        app.buttons["transit-trip-close"].tap()
        XCTAssertTrue(app.otherElements["transit-card"].waitForExistence(timeout: 20),
                      "the guidance card did not return after the trip")
        app.terminate()

        // 3. The route sheet and the transit options, on a real search like the Directions run.
        app.launchArguments = [
            "-VelaStartCamera", "sf",
            "-VelaDeterministic", "YES",
            "-VelaFollowUser", "YES",
            "-VelaResetSettings", "YES",
        ]
        app.launch()
        let searchField = app.textFields["search-field"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 60), "no map screen")
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
        XCTAssertTrue(app.buttons["route-mode-TRANSIT"].waitForExistence(timeout: 15), "no mode chips")
        app.buttons["route-mode-TRANSIT"].tap()
        XCTAssertTrue(waitUntil(90) {
            self.routeValue(app, "mode") == "TRANSIT" && self.routeValue(app, "loading") == "0"
        }, "the transit trips did not load")

        let expand = app.buttons["route-expand"]
        XCTAssertTrue(expand.waitForExistence(timeout: 10), "no route expand button")
        expand.tap()
        sleep(1)
        let routeDepart = app.buttons["route-time-DEPART"]
        XCTAssertTrue(routeDepart.waitForExistence(timeout: 10), "the route sheet has no time control")
        if !routeDepart.isHittable { app.otherElements["route-sheet"].swipeDown() }
        routeDepart.tap()
        XCTAssertTrue(app.buttons["route-time-plus"].waitForExistence(timeout: 5), "no route +15")
        app.buttons["route-time-plus"].tap()
        app.buttons["route-time-apply"].tap()
        let routeQuery = app.staticTexts["route-time-query"]
        XCTAssertTrue(routeQuery.waitForExistence(timeout: 10), "the route sheet names no query time")
        XCTAssertTrue(routeQuery.label.contains("Depart at"), "the route query is not a departure")
        XCTAssertTrue(waitUntil(90) { self.routeValue(app, "loading") == "0" },
                      "the timed transit search did not settle")
        report("time_route_query", routeQuery.label.replacingOccurrences(of: " ", with: "_"))
        report("time_route_mode", routeValue(app, "timeMode") ?? "?")
        shot("time-route")

        // The expanded chooser covers the map action column, so a transit plan carries its own
        // Options entry in the pinned header. Touch that entry directly, without collapsing the
        // chooser first: it is the path the product now offers from inside the route list.
        let options = app.buttons["transit-options-open"]
        XCTAssertTrue(options.waitForExistence(timeout: 10), "no transit options button")
        XCTAssertTrue(waitUntil(5) { options.isHittable },
                      "transit-options-open has no hit point: \(debugText("route-debug") ?? "none")")
        report("transit_options_hittable", options.isHittable ? "1" : "0")
        report("transit_options_from_chooser", (expand.value as? String) == "expanded" ? "1" : "0")
        options.tap()
        XCTAssertTrue(app.otherElements["transit-options"].waitForExistence(timeout: 10)
            || app.navigationBars["Transit options"].waitForExistence(timeout: 5), "no options sheet")
        shot("route-transit-options")
        let optionDepart = app.buttons["transit-option-depart"]
        XCTAssertTrue(optionDepart.waitForExistence(timeout: 10), "the options have no time control")
        optionDepart.tap()
        app.buttons["transit-option-plus15"].tap()
        app.buttons["transit-option-apply"].tap()
        let optionQuery = app.staticTexts["transit-option-query"]
        XCTAssertTrue(optionQuery.waitForExistence(timeout: 10), "the options name no query time")
        XCTAssertTrue(optionQuery.label.contains("Depart at"), "the options query is not a departure")
        report("time_transit_query", optionQuery.label.replacingOccurrences(of: " ", with: "_"))
        shot("time-transit")
        app.buttons["transit-options-close"].tap()
        report("time_surfaces", 4)
    }
}
