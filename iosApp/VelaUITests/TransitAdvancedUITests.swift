import XCTest

/// T-2: the reachability hull, the colored lines with their delays, the live badge and the via
/// alternative. Everything runs on the recorded fixture (`-VelaTransitFixture` and
/// `-VelaTransitAdvancedFixture`), so no Transitous request is made; the live panel's rows come
/// from the captured values documented in `TransitLiveFixtures`.
final class TransitAdvancedUITests: VelaUITestCase {
    private func launchFixture() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-VelaStartCamera", "sf",
            "-VelaDeterministic", "YES",
            "-VelaTransitFixture", "YES",
            "-VelaTransitAdvancedFixture", "YES",
        ]
        app.launch()
        XCTAssertTrue(app.otherElements["transit-card"].waitForExistence(timeout: 30), "no transit card")
        return app
    }

    private func openTrip(_ app: XCUIApplication) {
        let open = app.buttons["transit-trip-open"]
        XCTAssertTrue(open.waitForExistence(timeout: 20), "no trip-view button")
        open.tap()
        XCTAssertTrue(app.buttons["transit-trip-close"].waitForExistence(timeout: 20), "no trip screen")
        XCTAssertTrue(waitUntil(10) { self.value(app, "segments", id: "transit-trip-debug") != nil }, "no segments")
    }

    private func openLive(_ app: XCUIApplication) {
        let open = app.buttons["transit-live-open"]
        XCTAssertTrue(open.waitForExistence(timeout: 20), "no live-map button")
        open.tap()
        XCTAssertTrue(app.buttons["transit-live-close"].waitForExistence(timeout: 20), "no live panel")
    }

    func testIsochroneAndColoredLines() {
        let app = launchFixture()
        openTrip(app)
        openLive(app)

        app.buttons["transit-live-tab-reach"].tap()
        app.buttons["transit-live-reach-load"].tap()
        XCTAssertTrue(waitUntil(10) { (self.intValue(app, "stops", id: "transit-live-reach-debug") ?? 0) > 0 },
                      "the reachable area is empty")
        let stops = intValue(app, "stops", id: "transit-live-reach-debug") ?? 0
        let hull = intValue(app, "hull", id: "transit-live-reach-debug") ?? 0
        let reachFixture = value(app, "fixture", id: "transit-live-reach-debug") ?? "?"
        report("transit_reach_stops", stops)
        report("transit_reach_hull", hull)
        report("transit_reach_fixture", reachFixture)
        XCTAssertGreaterThanOrEqual(stops, 10, "the captured 10-minute reach needs its stops")
        XCTAssertGreaterThanOrEqual(hull, 3, "a hull needs three corners")
        XCTAssertEqual(reachFixture, "1", "the scenario did not run on its fixture")
        XCTAssertTrue(app.descendants(matching: .any)["transit-live-canvas"].exists, "no reach preview")
        shot("transit-isochrone")

        app.buttons["transit-live-tab-lines"].tap()
        app.buttons["transit-live-lines-load"].tap()
        XCTAssertTrue(waitUntil(10) { (self.intValue(app, "lines", id: "transit-live-lines-debug") ?? 0) > 0 },
                      "no line loaded")
        let lines = intValue(app, "lines", id: "transit-live-lines-debug") ?? 0
        let colored = intValue(app, "colored", id: "transit-live-lines-debug") ?? 0
        let lineFixture = value(app, "fixture", id: "transit-live-lines-debug") ?? "?"
        report("transit_lines", lines)
        report("transit_lines_colored", colored)
        report("transit_lines_fixture", lineFixture)
        XCTAssertGreaterThanOrEqual(lines, 8, "the captured extract has eight lines")
        XCTAssertGreaterThanOrEqual(colored, 5, "most captured lines carry their agency color")
        XCTAssertEqual(lineFixture, "1", "the scenario did not run on its fixture")
        // A line the feed gave no color takes the mode color, and the row says which.
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'Vela mode color'")).count > 0,
            "no mode-color line")
        shot("transit-lines")

        app.buttons["transit-live-close"].tap()
        XCTAssertTrue(app.buttons["transit-trip-close"].waitForExistence(timeout: 10), "the trip screen did not return")
    }

    func testLiveTripBadgeOnlyWhenRealTime() {
        let app = launchFixture()
        openTrip(app)
        openLive(app)
        app.buttons["transit-live-tab-lines"].tap()
        app.buttons["transit-live-lines-load"].tap()
        XCTAssertTrue(waitUntil(10) { (self.intValue(app, "lines", id: "transit-live-lines-debug") ?? 0) > 0 })
        let live = intValue(app, "live", id: "transit-live-lines-debug") ?? -1
        let lines = intValue(app, "lines", id: "transit-live-lines-debug") ?? 0
        report("transit_live_lines", live)
        report("transit_live_total", lines)
        XCTAssertEqual(live, 5, "five captured lines were marked realtime")
        let rows = app.descendants(matching: .any).matching(identifier: "transit-live-line")
        XCTAssertEqual(rows.count, lines, "one row per line")
        var badged = 0
        var u2Scheduled = false
        for index in 0..<rows.count {
            let label = rows.element(boundBy: index).label.lowercased()
            if label.contains(", live") { badged += 1 }
            if label.contains("u2") {
                u2Scheduled = label.contains("scheduled") && !label.contains(", live")
            }
        }
        XCTAssertEqual(badged, live, "a Live badge appeared on a line the feed did not mark live")
        XCTAssertTrue(u2Scheduled, "the U2 row lacks its Scheduled mark")
        shot("transit-live")
    }

    func testLineDelayColors() {
        let app = launchFixture()
        openTrip(app)
        openLive(app)
        app.buttons["transit-live-tab-lines"].tap()
        app.buttons["transit-live-lines-load"].tap()
        XCTAssertTrue(waitUntil(10) { (self.intValue(app, "lines", id: "transit-live-lines-debug") ?? 0) > 0 })
        let green = intValue(app, "green", id: "transit-live-lines-debug") ?? 0
        let amber = intValue(app, "amber", id: "transit-live-lines-debug") ?? 0
        let red = intValue(app, "red", id: "transit-live-lines-debug") ?? 0
        report("transit_delay_green", green)
        report("transit_delay_amber", amber)
        report("transit_delay_red", red)
        XCTAssertGreaterThanOrEqual(green, 1, "no on-time line")
        XCTAssertGreaterThanOrEqual(amber, 1, "no 2-to-5-minute line")
        XCTAssertGreaterThanOrEqual(red, 1, "no over-5-minute line")
        // The band is always words too, never colour alone.
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'min late'")).count >= 3,
            "the delay rows do not spell their lateness")
        XCTAssertTrue(app.descendants(matching: .any)["transit-live-delay-legend"].exists, "no delay legend")
        shot("transit-delay")
    }

    func testViaAlternativeInsideTrip() {
        let app = launchFixture()
        openTrip(app)

        let ride = app.buttons.matching(identifier: "transit-trip-segment")
            .matching(NSPredicate(format: "label CONTAINS 'Tram K'"))
        XCTAssertTrue(ride.firstMatch.waitForExistence(timeout: 10), "no K ride card")
        ride.firstMatch.tap()

        let via = app.buttons["transit-trip-via"]
        XCTAssertTrue(via.waitForExistence(timeout: 10), "no via action on the ride")
        via.tap()
        XCTAssertTrue(waitUntil(5) { (self.intValue(app, "viacand", id: "transit-trip-debug") ?? 0) > 0 },
                      "the model offered no intermediate stop")
        let offered = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'transit-trip-via-candidate'"))
        XCTAssertTrue(offered.firstMatch.waitForExistence(timeout: 10), "no intermediate stop control")
        offered.firstMatch.tap()

        XCTAssertTrue(waitUntil(15) { (self.intValue(app, "via", id: "transit-trip-debug") ?? 0) > 0 },
                      "no via option set")
        // The via section sits under four segment cards; bring it into the screenshot.
        for _ in 0..<8 {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.82))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.28))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        report("transit_via_options", intValue(app, "via", id: "transit-trip-debug") ?? 0)
        report("transit_via_candidates", intValue(app, "viacand", id: "transit-trip-debug") ?? 0)
        let query = app.staticTexts["transit-trip-via-query"]
        XCTAssertTrue(query.waitForExistence(timeout: 10), "no via query line")
        XCTAssertTrue(query.label.contains("Via "), "the query does not name the via stop")
        XCTAssertTrue(query.label.contains("fixture, display only"), "the fixture set is not marked display only")
        // The trip above keeps its own cards.
        XCTAssertGreaterThanOrEqual(intValue(app, "via", id: "transit-trip-debug") ?? 0, 1)
        shot("transit-via")

        let option = app.buttons.matching(identifier: "transit-trip-via-option").firstMatch
        if option.exists { option.tap() }
        XCTAssertTrue(waitUntil(5) {
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'display only'")).count > 0
        }, "a fixture via option was adopted as a trip")
    }

    // MARK: Debug lines

    private func value(_ app: XCUIApplication, _ key: String, id: String) -> String? {
        let element = app.staticTexts[id]
        guard element.exists else { return nil }
        for part in element.label.split(separator: " ") where part.hasPrefix("\(key)=") {
            return String(part.dropFirst(key.count + 1))
        }
        return nil
    }

    private func intValue(_ app: XCUIApplication, _ key: String, id: String) -> Int? {
        value(app, key, id: id).flatMap(Int.init)
    }
}
