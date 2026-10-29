import XCTest

/// TRANSIT-WIRE: the four hooks of this lot, on the Debug fixtures only. A cached stop board feeds
/// the two board taps, the recorded K line answers every line sheet, the recorded trip feeds the
/// segment and the nearby tab, and the recorded vehicles feed the panel's markers. No Transitous
/// request is possible: the board is served from its cache, the line sheet from its fixture and the
/// vehicles from `TransitVehicleFixtures`.
final class TransitWiredUITests: VelaUITestCase {
    private func launchWired() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-VelaStartCamera", "sf",
            "-VelaDeterministic", "YES",
            "-VelaTransitFixture", "YES",
            "-VelaTransitLineFixture", "YES",
            "-VelaTransitAdvancedFixture", "YES",
            "-VelaTransitVehicleFixture", "YES",
            "-VelaTransitBoardOfflineTest", "YES",
        ]
        app.launch()
        // The line fixture opens its own sheet on a short delay. Dismiss it first so the board
        // underneath is the surface under test.
        let autoLine = app.otherElements["transit-line-sheet"]
        if autoLine.waitForExistence(timeout: 15) {
            app.buttons["transit-line-close"].tap()
            XCTAssertTrue(waitUntil(10) { !autoLine.exists }, "the fixture line sheet did not close")
        }
        XCTAssertTrue(app.descendants(matching: .any)["transit-board"].waitForExistence(timeout: 30),
                      "the cached board never opened")
        XCTAssertTrue(waitUntil(20) { self.intValue(app, "loading", id: "transit-board-debug") == 0 },
                      "the board stayed loading")
        return app
    }

    /// Taps [element] and waits for the one line sheet every surface shares.
    private func openLine(_ app: XCUIApplication, from element: XCUIElement, _ surface: String) {
        element.tap()
        XCTAssertTrue(app.otherElements["transit-line-sheet"].waitForExistence(timeout: 20),
                      "the line sheet did not open from \(surface)")
        XCTAssertTrue(app.descendants(matching: .any)["transit-line-badge"].waitForExistence(timeout: 10),
                      "the line sheet opened without its badge from \(surface)")
    }

    private func closeLine(_ app: XCUIApplication, _ surface: String) {
        app.buttons["transit-line-close"].tap()
        XCTAssertTrue(waitUntil(10) { !app.otherElements["transit-line-sheet"].exists },
                      "the line sheet did not close after \(surface)")
    }

    func testTapTransitEverywhereAndSeeTheLine() {
        let app = launchWired()

        // 1. A board line, then one of its departures: both open the line sheet at that stop.
        XCTAssertTrue(waitUntil(20) { (self.intValue(app, "lines", id: "transit-board-debug") ?? 0) > 0 },
                      "the cached board has no line")
        report("wired_board_lines", intValue(app, "lines", id: "transit-board-debug") ?? 0)
        let rows = app.descendants(matching: .any).matching(identifier: "transit-board-line")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10), "the cached board has no line row")
        openLine(app, from: rows.firstMatch, "a board line")
        // The sheet opens on the line's own stops and colours. Departures come from the feed, and
        // the fixture board carries none, so their presence is reported rather than required.
        report("wired_line_departures",
               app.descendants(matching: .any).matching(identifier: "transit-line-departure").count)
        // The fixture board gives the sheet neither a trip id nor departures, so the stop sequence
        // cannot be fetched. The sheet must then say so rather than open empty.
        let ribbon = app.descendants(matching: .any)["transit-line-ribbon"]
        let noSequence = app.staticTexts["transit-line-no-sequence"]
        let debug = debugText("transit-line-debug") ?? ""
        XCTAssertTrue(waitUntil(15) { ribbon.exists || noSequence.exists },
                      "the line sheet opened with neither a ribbon nor a reason: \(debug)")
        report("wired_line_sequence", debug.contains("line_seq=1") ? "ribbon" : "unavailable")
        shot("transit-wired-line")
        report("wired_line", 1)
        closeLine(app, "a board line")

        let departure = app.descendants(matching: .any)
            .matching(identifier: "transit-board-departure").firstMatch
        XCTAssertTrue(departure.waitForExistence(timeout: 10), "the board has no departure")
        openLine(app, from: departure, "a departure")
        report("wired_departure", 1)
        closeLine(app, "a departure")

        app.buttons["transit-board-close"].tap()
        XCTAssertTrue(app.otherElements["transit-card"].waitForExistence(timeout: 20),
                      "the guidance card did not return")

        // 2. The trip screen: a ride card's own line button, then a nearby line row.
        app.buttons["transit-trip-open"].tap()
        XCTAssertTrue(app.buttons["transit-trip-close"].waitForExistence(timeout: 20), "no trip screen")
        XCTAssertTrue(waitUntil(15) { self.intValue(app, "segments", id: "transit-trip-debug") != nil },
                      "the trip screen kept no segment")

        let lineLink = app.buttons["transit-trip-line-link"].firstMatch
        XCTAssertTrue(lineLink.waitForExistence(timeout: 20), "no line button on a ride card")
        let tripScroll = app.scrollViews["transit-trip-scroll"]
        for _ in 0..<6 where !lineLink.isHittable {
            if tripScroll.exists { tripScroll.swipeUp() } else { app.swipeUp() }
        }
        XCTAssertTrue(lineLink.isHittable, "the ride card's line button never came on screen")
        openLine(app, from: lineLink, "a trip segment")
        report("wired_segment", 1)
        closeLine(app, "a trip segment")

        app.buttons["transit-trip-tab-nearby"].tap()
        let nearby = app.descendants(matching: .any)
            .matching(identifier: "transit-trip-nearby-line").firstMatch
        XCTAssertTrue(nearby.waitForExistence(timeout: 20), "no nearby line row")
        openLine(app, from: nearby, "a nearby line")
        report("wired_nearby", 1)
        closeLine(app, "a nearby line")

        app.buttons["transit-trip-close"].tap()
        XCTAssertTrue(app.otherElements["transit-card"].waitForExistence(timeout: 20),
                      "the guidance card did not return from the trip screen")

        // 3. GO, from the button the card now mounts beside Trip and End.
        let go = app.buttons["transit-go-open"]
        XCTAssertTrue(go.waitForExistence(timeout: 20), "the guidance card has no GO button")
        go.tap()
        XCTAssertTrue(app.descendants(matching: .any)["transit-go-screen"].waitForExistence(timeout: 30),
                      "GO did not open")
        XCTAssertTrue(waitUntil(20) { self.intValue(app, "go_step", id: "transit-go-debug") != nil },
                      "GO never reached a state")
        shot("transit-wired-go")
        report("wired_go", 1)
        app.buttons["transit-go-close"].tap()
        XCTAssertTrue(waitUntil(10) {
            !app.descendants(matching: .any)["transit-go-screen"].exists
        }, "GO did not close")

        // 4. The vehicles tab reports the markers the overlay draws. Its model is the only source of
        // these points; this lot adds no request and no timer.
        XCTAssertTrue(app.otherElements["transit-card"].waitForExistence(timeout: 20),
                      "the guidance card did not return from GO")
        app.buttons["transit-trip-open"].tap()
        XCTAssertTrue(app.buttons["transit-trip-close"].waitForExistence(timeout: 20), "no trip screen")
        app.buttons["transit-live-open"].tap()
        XCTAssertTrue(app.buttons["transit-live-close"].waitForExistence(timeout: 20), "no live panel")
        app.buttons["transit-live-tab-vehicles"].tap()

        let toggle = app.switches["transit-vehicles-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "no vehicles switch")
        if toggle.value as? String != "1" { toggle.tap() }
        XCTAssertTrue(waitUntil(20) {
            (self.intValue(app, "vehicles", id: "transit-vehicles-debug") ?? 0) > 0
        }, "no estimated vehicle was reported")
        let vehicles = intValue(app, "vehicles", id: "transit-vehicles-debug") ?? 0
        let markers = app.descendants(matching: .any).matching(identifier: "transit-vehicle")
        XCTAssertGreaterThanOrEqual(markers.count, 1, "the panel counts vehicles but shows no marker")
        XCTAssertEqual(intValue(app, "estimated", id: "transit-vehicles-debug"), 1,
                       "a vehicle marker is not labelled estimated")
        report("wired_vehicles", vehicles)
        shot("transit-wired-vehicles")

        app.buttons["transit-live-close"].tap()
        XCTAssertTrue(app.buttons["transit-trip-close"].waitForExistence(timeout: 10), "the trip screen did not return")
        app.buttons["transit-trip-close"].tap()
        XCTAssertTrue(app.otherElements["transit-card"].waitForExistence(timeout: 20), "no guidance card at the end")
    }

    private func intValue(_ app: XCUIApplication, _ key: String, id: String) -> Int? {
        let element = app.staticTexts[id]
        guard element.exists else { return nil }
        for part in element.label.split(separator: " ") where part.hasPrefix("\(key)=") {
            return Int(part.dropFirst(key.count + 1))
        }
        return nil
    }
}
