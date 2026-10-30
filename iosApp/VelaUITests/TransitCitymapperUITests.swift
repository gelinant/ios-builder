import XCTest

/// T-3: the Citymapper-style trip screen. The first scenarios run on the recorded San Francisco
/// fixture (`-VelaTransitFixture`) so they need no live feed; the last one reports whether the
/// production Transitous board answered and is skipped when it did not.
final class TransitCitymapperUITests: VelaUITestCase {
    /// The fixture hides the browse chrome, so `launch()` (which waits for the search field) is not
    /// used here; the transit card is the proof that the fixture started.
    private func launchFixture() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-VelaStartCamera", "sf",
            "-VelaDeterministic", "YES",
            "-VelaTransitFixture", "YES",
        ]
        app.launch()
        XCTAssertTrue(app.otherElements["transit-card"].waitForExistence(timeout: 30), "no transit card")
        return app
    }

    private func openTrip(_ app: XCUIApplication) {
        let open = app.buttons["transit-trip-open"]
        XCTAssertTrue(open.waitForExistence(timeout: 20), "no trip-view button on the guidance card")
        // The action row must stay inside the card and the window, not only exist in the tree.
        XCTAssertTrue(open.isHittable, "the trip-view button is outside the guidance card")
        XCTAssertTrue(app.buttons["transit-go-open"].exists, "the guidance card lost GO")
        XCTAssertTrue(app.buttons["transit-end"].exists, "the guidance card lost End")
        open.tap()
        XCTAssertTrue(app.buttons["transit-trip-close"].waitForExistence(timeout: 20), "no trip screen")
        XCTAssertTrue(waitUntil(10) { self.debugValue(app, "segments") != nil }, "no trip segments")
    }

    func testTripScreenShowsSegmentCardsAndNextDepartures() {
        let app = launchFixture()
        openTrip(app)

        shot("transit-trip")
        let segments = intValue(app, "segments") ?? 0
        let rides = intValue(app, "rides") ?? 0
        let header = intValue(app, "header") ?? -1
        report("transit_trip_segments", segments)
        report("transit_trip_rides", rides)
        report("transit_trip_header", header)
        report("transit_trip_fixture", value(app, "fixture") ?? "?")
        XCTAssertGreaterThanOrEqual(segments, 4, "the fixture trip needs walk, wait, ride and walk cards")
        XCTAssertGreaterThanOrEqual(rides, 1, "no ride card")
        XCTAssertGreaterThanOrEqual(header, 1, "no next departure for the chosen leg")
        XCTAssertEqual(value(app, "available"), "1", "the fixture board was not read")
        XCTAssertEqual(value(app, "fixture"), "1", "the scenario did not run on its fixture")

        let cards = app.buttons.matching(identifier: "transit-trip-segment")
        XCTAssertEqual(cards.count, segments, "one card per segment")
        XCTAssertTrue(app.staticTexts["Next departures"].exists
            || app.descendants(matching: .any)["transit-trip-header"].exists,
            "no departures header")
        // Live and scheduled are words in the cards' labels, never colour alone.
        XCTAssertGreaterThan(cards.matching(NSPredicate(format: "label CONTAINS 'Live'")).count, 0,
                             "no live mark on the fixture's live run")
        XCTAssertGreaterThan(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS[c] 'scheduled'")).count, 0,
            "no scheduled mark")
        report("transit_trip", "segments_and_header")

        app.buttons["transit-trip-close"].tap()
        XCTAssertTrue(app.otherElements["transit-card"].waitForExistence(timeout: 20), "guidance did not return")
        let cardDebug = app.staticTexts["transit-debug"]
        XCTAssertTrue(cardDebug.waitForExistence(timeout: 10), "no guidance debug line")
        XCTAssertTrue(cardDebug.label.contains("active=1"), "closing the trip screen ended the session")
    }

    func testSegmentTimeChangeShowsANewOptionSet() {
        let app = launchFixture()
        openTrip(app)

        let ride = app.buttons.matching(identifier: "transit-trip-segment")
            .matching(NSPredicate(format: "label CONTAINS 'Tram K'"))
        XCTAssertTrue(ride.firstMatch.waitForExistence(timeout: 10), "no K ride card")
        // The time control sits above the cards, so the ride card is reached like any other row.
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
        let later = app.buttons["transit-trip-later-15"]
        XCTAssertTrue(later.waitForExistence(timeout: 10), "no +15 choice")
        later.tap()
        XCTAssertTrue(waitUntil(15) { self.value(app, "shift") == "1" }, "no shifted query")
        XCTAssertTrue(waitUntil(15) { (self.intValue(app, "options") ?? 0) > 0 }, "no new option set")
        let options = intValue(app, "options") ?? 0
        report("transit_trip_shift_options", options)
        // The time control and the option set it produced sit above the cards, and the screen
        // scrolls them back to the top after a shift: the query label is reachable as it is.
        let query = app.staticTexts["transit-trip-options-query"]
        XCTAssertTrue(query.waitForExistence(timeout: 10),
                      "the shifted query label is not above the cards")
        report("transit_trip_shift_query", query.label)
        XCTAssertTrue(query.label.contains("Depart at"), "the shifted query is not a departure")
        let optionRows = app.buttons.matching(identifier: "transit-trip-option")
        XCTAssertTrue(waitUntil(10) { optionRows.count > 0 }, "the new option set has no reachable row")
        report("transit_trip_option_rows", String(optionRows.count))
        // The trip above keeps its own times: only the option set changed.
        XCTAssertGreaterThanOrEqual(intValue(app, "segments") ?? 0, 4, "the trip was replaced by the option set")
        shot("transit-trip-shift")

        // The fixture set is display only; picking it must not rewrite the trip with fixture times.
        optionRows.element(boundBy: 0).tap()
        XCTAssertTrue(waitUntil(5) {
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'display only'")).count > 0
        }, "a fixture option was adopted as a trip")
        app.buttons["transit-trip-close"].tap()
        XCTAssertTrue(app.otherElements["transit-card"].waitForExistence(timeout: 20), "guidance did not return")
    }

    func testSkipLetsTheRunPassAndAdvancesTheHeader() {
        let app = launchFixture()
        openTrip(app)
        let before = intValue(app, "header") ?? 0
        XCTAssertGreaterThanOrEqual(before, 2, "the fixture board needs a later run to skip to")

        let ride = app.buttons.matching(identifier: "transit-trip-segment")
            .matching(NSPredicate(format: "label CONTAINS 'Tram K'"))
        XCTAssertTrue(ride.firstMatch.waitForExistence(timeout: 10), "no K ride card")
        ride.firstMatch.tap()
        app.buttons["transit-trip-skip"].tap()
        XCTAssertTrue(waitUntil(15) { self.value(app, "skipped") == "1" }, "the run was not let pass")
        let after = intValue(app, "header") ?? 0
        report("transit_trip_header_before_skip", before)
        report("transit_trip_header_after_skip", after)
        report("transit_trip_skip_options", intValue(app, "options") ?? 0)
        XCTAssertEqual(after, before - 1, "the header did not advance to the next departure")
        let cards = app.buttons.matching(identifier: "transit-trip-segment")
        XCTAssertEqual(cards.count, intValue(app, "segments") ?? 0, "the trip was lost")
        XCTAssertGreaterThanOrEqual(cards.count, 4, "the trip lost its cards")
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'Let K pass'")).count > 0, "no pass notice")
        XCTAssertTrue(waitUntil(15) { (self.intValue(app, "options") ?? 0) > 0 },
                      "no option set for the next run")
        shot("transit-trip-skip")
        app.buttons["transit-trip-close"].tap()
    }

    func testNearbyLinesTabListsTheStopsLines() {
        let app = launchFixture()
        openTrip(app)

        app.buttons["transit-trip-tab-nearby"].tap()
        XCTAssertTrue(waitUntil(20) { (self.intValue(app, "nearby") ?? 0) > 0 }, "no nearby lines")
        let lines = intValue(app, "nearby") ?? 0
        report("transit_trip_nearby_lines", lines)
        XCTAssertGreaterThanOrEqual(lines, 1, "no line around the trip origin")
        let rows = app.descendants(matching: .any)
            .matching(identifier: "transit-trip-nearby-line").count
        report("transit_trip_nearby_rows", rows)
        XCTAssertGreaterThanOrEqual(rows, 1, "no nearby line row")
        XCTAssertGreaterThan(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS[c] 'live'")).count, 0,
            "no live mark on a live nearby run")
        shot("transit-trip-nearby")

        app.buttons["transit-trip-tab-trip"].tap()
        XCTAssertTrue(app.buttons["transit-trip-tab-nearby"].waitForExistence(timeout: 10), "tabs gone")
        app.buttons["transit-trip-close"].tap()
    }

    /// Production path: the real Ferry Building search, the real detail sheet and the screen's own
    /// Transitous board. It is skipped, not failed, when the live planner returns no trip.
    func testLiveTripScreenWhenTheFeedAnswers() throws {
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
            guard let line = self.debugText("route-debug") else { return false }
            return self.value(in: line, key: "mode") == "TRANSIT"
                && self.value(in: line, key: "loading") == "0"
        }, "transit trips did not load")
        let steps = app.buttons["route-steps"]
        guard steps.waitForExistence(timeout: 20), steps.isEnabled else {
            throw XCTSkip("live planner returned no trip; fixture scenarios covered the screen")
        }
        steps.tap()
        let open = app.buttons["transit-trip-open"]
        guard open.waitForExistence(timeout: 20) else {
            throw XCTSkip("the detail sheet did not show a trip; fixture scenarios covered the screen")
        }
        open.tap()
        XCTAssertTrue(app.buttons["transit-trip-close"].waitForExistence(timeout: 20), "no trip screen")
        XCTAssertTrue(waitUntil(30) { self.debugValue(app, "segments") != nil }, "no live segments")
        report("transit_trip_live_segments", intValue(app, "segments") ?? 0)
        report("transit_trip_live_header", intValue(app, "header") ?? -1)
        report("transit_trip_live_available", value(app, "available") ?? "?")
        XCTAssertGreaterThanOrEqual(intValue(app, "segments") ?? 0, 2, "no live trip cards")
        shot("transit-trip-live")
        app.buttons["transit-trip-close"].tap()
    }

    // MARK: Debug line

    private func debugValue(_ app: XCUIApplication, _ key: String) -> String? {
        let element = app.staticTexts["transit-trip-debug"]
        guard element.exists else { return nil }
        return value(in: element.label, key: key)
    }

    private func value(_ app: XCUIApplication, _ key: String) -> String? {
        debugValue(app, key)
    }

    private func intValue(_ app: XCUIApplication, _ key: String) -> Int? {
        value(app, key).flatMap(Int.init)
    }

    private func value(in line: String, key: String) -> String? {
        for part in line.split(separator: " ") where part.hasPrefix("\(key)=") {
            return String(part.dropFirst(key.count + 1))
        }
        return nil
    }
}
