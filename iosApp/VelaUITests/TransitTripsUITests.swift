import XCTest

/// TRANSIT-TRIPS: a transit plan lists several itineraries, each with its line badges, and the
/// one the user picks is drawn, refitted and handed to GO. The planner answer is the recorded
/// San Francisco reply (`-VelaTransitTripsFixture`, six itineraries from 24th Street / Mission to
/// the Ferry Building); the search for the destination still needs the network.
final class TransitTripsUITests: VelaUITestCase {
    func testSeveralTripsAndTheSecondFeedsGo() {
        let app = launch(camera: "sf", followUser: true,
                         arguments: ["-VelaResetSettings", "YES", "-VelaTransitTripsFixture", "YES"])
        openDirections(app, query: "Ferry Building")
        XCTAssertTrue(app.buttons["route-mode-TRANSIT"].waitForExistence(timeout: 15), "no mode chips")
        app.buttons["route-mode-TRANSIT"].tap()
        XCTAssertTrue(waitUntil(90) {
            self.routeValue("mode") == "TRANSIT" && self.routeValue("loading") == "0"
                && self.routeValue("transit") == "5"
        }, "the five trips were not listed: \(debugText("route-debug") ?? "none")")

        // Five rows out of six answers, earliest arrival first, every ride in its feed color.
        let rows = app.buttons.matching(identifier: "transit-row")
        XCTAssertTrue(waitUntil(10) { rows.count == 5 }, "the chooser shows \(rows.count) rows")
        XCTAssertTrue(rows.element(boundBy: 0).label.contains("Green-N"), rows.element(boundBy: 0).label)
        XCTAssertTrue(rows.element(boundBy: 1).label.contains("Yellow-N"), rows.element(boundBy: 1).label)
        XCTAssertTrue(rows.element(boundBy: 1).label.contains("14R"), rows.element(boundBy: 1).label)
        let rides = Int(routeValue("transitRides") ?? "") ?? -1
        report("trips_rows", rows.count)
        report("trips_rides", rides)
        report("trips_feed_colors", routeValue("transitFeedColors") ?? "?")
        report("trips_live", routeValue("transitLive") ?? "?")
        XCTAssertEqual(rides, 8, "line badges: \(debugText("route-debug") ?? "none")")
        XCTAssertEqual(routeValue("transitFeedColors"), "8", "a ride lost its agency color")
        XCTAssertEqual(routeValue("transitLive"), "2", "Live is claimed for a timetable-only ride")
        XCTAssertEqual(routeValue("active"), "0")
        XCTAssertTrue(rows.element(boundBy: 0).isSelected, "the first trip is not marked selected")
        // The list opens the sheet tall, right under the mode chips: two whole rows show before any
        // scroll (Debug lines take some of the height Release gives them), the fifth after one.
        XCTAssertTrue(waitUntil(10) { app.buttons["route-expand"].value as? String == "expanded" },
                      "the sheet did not open tall for the trips")
        let viewport = app.descendants(matching: .any)["route-scroll"].firstMatch.frame
        let frames = (0..<5).map { rows.element(boundBy: $0).frame }
        let whole = frames.filter { viewport.contains($0) }.count
        report("trips_whole_rows", whole)
        XCTAssertGreaterThanOrEqual(whole, 2, "only \(whole) whole trip rows before scrolling, viewport \(viewport)")
        let last = rows.element(boundBy: 4)
        revealInSheet(last, in: app, sheet: "route-scroll", requireHittable: true)
        XCTAssertTrue(last.isHittable, "the fifth trip row cannot be scrolled to")
        revealInSheet(rows.element(boundBy: 0), in: app, sheet: "route-scroll", requireHittable: true, up: false)
        sleep(2)
        shot("transit-trips")

        // The second trip: selected, drawn and framed again.
        let fitsBefore = number(debugValue("camera-fit-debug") ?? "", "fit_count")
        let second = rows.element(boundBy: 1)
        revealInSheet(second, in: app, sheet: "route-scroll", requireHittable: true)
        second.tap()
        XCTAssertTrue(waitUntil(15) {
            self.routeValue("active") == "1" && self.routeValue("activeLines") == "Yellow-N,14R"
        }, "the second trip was not selected: \(debugText("route-debug") ?? "none")")
        XCTAssertEqual(routeValue("transfers"), "1")
        XCTAssertTrue(waitUntil(10) { rows.element(boundBy: 1).isSelected }, "the second row is not marked selected")
        let refit = waitUntil(15) { self.number(self.debugValue("camera-fit-debug") ?? "", "fit_count") > fitsBefore }
        report("trips_refit", refit ? 1 : 0)
        XCTAssertTrue(refit, "the map did not frame the picked trip: \(debugValue("camera-fit-debug") ?? "none")")
        let fitZoom = number(debugValue("camera-fit-debug") ?? "", "fit_zoom")
        report("trips_fit_zoom", fitZoom)
        XCTAssertGreaterThan(fitZoom, 10, "the picked trip is framed at zoom \(fitZoom), not the city")

        // Its legs unfold under the row.
        let expand = app.buttons.matching(identifier: "transit-row-expand").element(boundBy: 1)
        revealInSheet(expand, in: app, sheet: "route-scroll", requireHittable: true)
        expand.tap()
        let legs = app.descendants(matching: .any).matching(identifier: "transit-row-leg")
        XCTAssertTrue(waitUntil(10) { legs.count == 5 }, "the second trip unfolds \(legs.count) legs")
        let metro = legs.element(boundBy: 1).label
        report("trips_leg", metro.replacingOccurrences(of: " ", with: "_"))
        XCTAssertTrue(metro.contains("Antioch"), "no direction: \(metro)")
        XCTAssertTrue(metro.contains("24th Street / Mission"), "no boarding stop: \(metro)")
        XCTAssertTrue(metro.contains("Embarcadero BART"), "no alighting stop: \(metro)")
        XCTAssertTrue(metro.contains("5 stops"), "no stop count: \(metro)")
        XCTAssertTrue(metro.contains("Scheduled"), "the BART ride is not called Scheduled: \(metro)")
        sleep(1)
        shot("transit-trips-legs")

        // Start, then GO: the guidance follows the second trip, not the first one.
        app.buttons["route-start"].tap()
        let go = app.buttons["transit-go-open"]
        XCTAssertTrue(go.waitForExistence(timeout: 20), "no GO on the guidance card")
        go.tap()
        XCTAssertTrue(app.descendants(matching: .any)["transit-go-screen"].waitForExistence(timeout: 20),
                      "the GO screen was not presented")
        let goLines = { () -> String? in
            guard let line = self.debugText("transit-go-debug") else { return nil }
            return self.field(line, "go_lines")
        }
        XCTAssertTrue(waitUntil(15) { goLines() == "Yellow-N,14R" },
                      "GO runs another trip: \(debugText("transit-go-debug") ?? "none")")
        report("trips_go_lines", goLines() ?? "?")
        shot("transit-trips-go")
    }

    private func openDirections(_ app: XCUIApplication, query: String) {
        let searchField = app.textFields["search-field"]
        sleep(4)
        searchField.tap()
        searchField.typeText("\(query)\n")
        let directions = app.buttons["place-directions"]
        if !directions.waitForExistence(timeout: 10) {
            let rows = app.buttons.matching(identifier: "search-result")
            XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 60), "no result row for \(query)")
            sleep(3)
            rows.firstMatch.tap()
        }
        XCTAssertTrue(directions.waitForExistence(timeout: 15), "no Directions button")
        directions.tap()
    }

    private func field(_ line: String, _ key: String) -> String? {
        line.split(separator: " ").first { $0.hasPrefix("\(key)=") }.map { String($0.dropFirst(key.count + 1)) }
    }

    private func number(_ line: String, _ key: String) -> Double {
        Double(field(line, key) ?? "") ?? 0
    }

    private func routeValue(_ key: String) -> String? {
        guard let line = debugText("route-debug") else { return nil }
        return field(line, key)
    }
}
