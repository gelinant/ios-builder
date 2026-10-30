import XCTest

/// TRANSIT-LINEVIEW: the line sheet and its route ribbon. The scenario runs on the recorded K board
/// and K run at Metro Van Ness Station (`-VelaTransitLineFixture`, see `TransitLineFixtures`), so no
/// Transitous request is made. It proves the feed's color, the full stop sequence, the direction
/// switcher and the estimated vehicle marker.
final class TransitLineViewUITests: VelaUITestCase {
    private func launchLineFixture() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-VelaStartCamera", "sf",
            "-VelaDeterministic", "YES",
            "-VelaTransitFixture", "YES",
            "-VelaTransitLineFixture", "YES",
        ]
        app.launch()
        XCTAssertTrue(app.otherElements["transit-line-sheet"].waitForExistence(timeout: 60),
                      "the line sheet did not open")
        return app
    }

    /// The Debug status line as key/value pairs (`line_stops=20 line_color=437c93 ...`).
    private func debugValues(_ app: XCUIApplication) -> [String: String] {
        let element = app.staticTexts["transit-line-debug"]
        guard element.exists else { return [:] }
        var values: [String: String] = [:]
        for pair in element.label.split(separator: " ") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2 { values[String(parts[0])] = String(parts[1]) }
        }
        return values
    }

    /// Swipes the sheet's scroll view until [element] is on screen.
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        let scroll = app.scrollViews.firstMatch
        var tries = 0
        while !element.isHittable && tries < 10 {
            if scroll.exists { scroll.swipeUp() } else { app.swipeUp() }
            tries += 1
        }
    }

    func testLineRibbonAndColors() {
        let app = launchLineFixture()

        XCTAssertTrue(waitUntil(20) { self.debugValues(app)["line_stops"] != nil },
                      "the line data never arrived")

        let stops = Int(debugValues(app)["line_stops"] ?? "0") ?? 0
        let color = debugValues(app)["line_color"] ?? "?"
        let estimated = debugValues(app)["line_estimated"] ?? "?"
        let source = debugValues(app)["line_source"] ?? "?"
        let fixture = debugValues(app)["line_fixture"] ?? "?"
        report("line_stops", stops)
        report("line_color", color)
        report("line_estimated", estimated)
        report("line_source", source)
        report("line_fixture", fixture)

        XCTAssertEqual(stops, 20, "the captured K run has twenty stops")
        XCTAssertEqual(color, "437c93", "the feed's routeColor is the line color")
        XCTAssertEqual(source, "feed", "a feed color must never be reported as the mode color")
        XCTAssertEqual(estimated, "1", "the captured clock sits inside the run")
        XCTAssertEqual(fixture, "1", "the scenario did not run on its fixture")

        // The line's identity, the agency color note and the two termini.
        XCTAssertTrue(app.descendants(matching: .any)["transit-line-badge"].exists, "no line badge")
        XCTAssertTrue(app.descendants(matching: .any)["transit-line-termini"].exists, "no termini")
        XCTAssertTrue(app.descendants(matching: .any)["transit-line-color-source"].exists,
                      "the sheet does not say where the color came from")
        XCTAssertGreaterThan(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS 'Agency color'")).count, 0,
            "the feed color is not named as the agency's")

        // Next departures first, then the direction switcher.
        let departures = app.descendants(matching: .any).matching(identifier: "transit-line-departure")
        XCTAssertGreaterThanOrEqual(departures.count, 1, "no next departure")
        let directions = app.buttons.matching(identifier: "transit-line-direction-0").count + app.buttons.matching(identifier: "transit-line-direction-1").count
        report("line_directions", directions)
        XCTAssertGreaterThanOrEqual(directions, 2, "the K serves both directions at Van Ness")

        shot("transit-line")

        // The ribbon: one row per stop, passed stops in words, and the estimated marker.
        let stopRows = app.descendants(matching: .any).matching(identifier: "transit-line-stop")
        XCTAssertEqual(stopRows.count, stops, "one ribbon row per stop")
        let vehicle = app.descendants(matching: .any)["transit-line-vehicle"]
        XCTAssertTrue(vehicle.exists, "the estimated vehicle marker is missing")
        // Scroll the sheet until the marker is on screen: an off-screen SwiftUI row already exists,
        // so `exists` alone would not prove it is visible in the screenshot.
        scrollTo(vehicle, in: app)
        XCTAssertTrue(vehicle.isHittable, "the estimated vehicle marker never came on screen")
        XCTAssertTrue(vehicle.label.contains("not GPS"), "the marker must say it is an estimate")
        XCTAssertGreaterThan(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS 'Next stop'")).count, 0,
            "no next stop in the ribbon")
        XCTAssertGreaterThan(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS 'Passed'")).count, 0,
            "passed stops are not said in words")

        // A transfer badge carries the other line's own color and label.
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS 'Transfer to line'")).count > 0,
            "the board's other lines are not shown as transfers")

        shot("transit-line-ribbon")

        // The whole-line action feeds the map hook; the sheet stays open and says it was sent.
        let mapButton = app.buttons["transit-line-map"]
        XCTAssertTrue(mapButton.exists, "no whole-line action")
        scrollTo(mapButton, in: app)
        mapButton.tap()
        XCTAssertTrue(app.staticTexts["transit-line-map-sent"].waitForExistence(timeout: 10),
                      "the whole-line request was not published")

        app.buttons["transit-line-close"].tap()
        XCTAssertTrue(waitUntil(10) { !app.otherElements["transit-line-sheet"].exists },
                      "the sheet did not close")
    }
}
