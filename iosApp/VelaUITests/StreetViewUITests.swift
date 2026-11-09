import XCTest

/// SV-1: the interactive Street View viewer from the Davis place sheet. Google's datacenter-facing
/// runner sometimes answers no panorama; the scenario then relaunches on the renderer fixture
/// (`-VelaStreetViewFixture YES`) so drag, zoom and close are still proven, and reports which path
/// ran. Screenshots: street-view.png and street-view-zoom.png.
final class StreetViewUITests: VelaUITestCase {
    func testStreetViewFromPlace() throws {
        var app = launch(camera: "davis")
        openDavisPlace(app)

        let scroll = app.scrollViews["place-scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 15), "no place scroll view")
        let thumbnail = app.buttons["place-street-view"]
        var hasThumbnail = reveal(thumbnail, in: scroll)
        if !hasThumbnail {
            // The nearest-pano lookup runs after the details; give it time before settling for
            // the fixture.
            sleep(10)
            hasThumbnail = reveal(thumbnail, in: scroll)
        }
        report("street_view_thumbnail", hasThumbnail ? 1 : 0)

        if hasThumbnail {
            thumbnail.tap()
            if waitUntil(40, { self.hasPano("street-view-debug") }) {
                report("street_view_mode", "live")
                exerciseViewer(app, live: true)
                return
            }
            // The pano lookup failed even though the thumbnail painted: close and use the fixture.
            report("street_view_live_error", value("error", debugID: "street-view-debug") ?? "none")
            if app.buttons["street-view-close"].exists { app.buttons["street-view-close"].tap() }
            sleep(1)
        }

        app.terminate()
        app = launch(camera: "davis", arguments: ["-VelaStreetViewFixture", "YES"])
        XCTAssertTrue(app.staticTexts["street-view-debug"].waitForExistence(timeout: 30),
                      "fixture viewer did not open")
        report("street_view_mode", "fixture")
        exerciseViewer(app, live: false)
    }

    /// Drag around, zoom in, return to north and close. Every check reads the viewer's debug line,
    /// so a screenshot is evidence and never the only assertion.
    private func exerciseViewer(_ app: XCUIApplication, live: Bool) {
        XCTAssertTrue(waitUntil(45) { self.hasPano("street-view-debug") }, "no pano")
        _ = waitUntil(45) { self.intValue("base", debugID: "street-view-debug") == 1 }
        _ = waitUntil(45) { self.intValue("tiles", debugID: "street-view-debug") >= 8 }
        sleep(3)
        shot("street-view")

        // The heading cone sits in the compass dial and turns with the view.
        XCTAssertTrue(waitUntil(5) { self.app.descendants(matching: .any)["street-view-cone"].exists },
                      "no compass heading cone")
        report("street_view_cone", 1)
        shot("street-view-cone")

        exerciseHistory(app)

        let beforeBearing = intValue("bearing", debugID: "street-view-debug")
        let beforeFov = intValue("fov", debugID: "street-view-debug")
        let beforePitch = intValue("pitch", debugID: "street-view-debug")
        report("street_view_pano", panoValue("street-view-debug"))
        report("street_view_neighbors", value("neighbors", debugID: "street-view-debug") ?? "?")

        // Horizontal drag: the world follows the finger and wraps horizontally. Coordinates stay
        // in the middle band, clear of the top bar and the bottom controls.
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.74, dy: 0.38))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.28, dy: 0.62))
        from.press(forDuration: 0.15, thenDragTo: to)
        sleep(1)
        let afterBearing = intValue("bearing", debugID: "street-view-debug")
        let afterPitch = intValue("pitch", debugID: "street-view-debug")
        report("street_view_bearing", afterBearing)
        report("street_view_pitch", afterPitch)
        XCTAssertNotEqual(afterBearing, beforeBearing, "horizontal drag did not rotate the pano")
        XCTAssertNotEqual(afterPitch, beforePitch, "the drag did not tilt the pano")

        // Zoom: the buttons are the deterministic path on the simulator; the pinch gesture is
        // reported when the panorama element answers it.
        app.buttons["street-view-zoom-in"].tap()
        app.buttons["street-view-zoom-in"].tap()
        sleep(1)
        let zoomedFov = intValue("fov", debugID: "street-view-debug")
        report("street_view_fov", zoomedFov)
        XCTAssertLessThan(zoomedFov, beforeFov, "zoom in did not narrow the field of view")
        let panoView = app.otherElements["street-view-pano"]
        if panoView.exists {
            panoView.pinch(withScale: 1.6, velocity: 1)
            sleep(1)
            report("street_view_pinch_fov", intValue("fov", debugID: "street-view-debug"))
        }
        _ = waitUntil(30) { self.intValue("tiles", debugID: "street-view-debug") >= 8 }
        sleep(2)
        report("street_view_tiles", intValue("tiles", debugID: "street-view-debug"))
        report("street_view_base", intValue("base", debugID: "street-view-debug"))
        shot("street-view-zoom")

        // Return to north: the compass bearing must become 0 (or 360).
        app.buttons["street-view-north"].tap()
        sleep(1)
        let north = intValue("bearing", debugID: "street-view-debug")
        report("street_view_north", north)
        XCTAssertTrue(north == 0 || north == 360, "return to north left the bearing at \(north)")

        app.buttons["street-view-close"].tap()
        XCTAssertTrue(waitUntil(10) { !app.buttons["street-view-close"].exists }, "viewer stayed open")
        if live {
            XCTAssertTrue(app.buttons["place-close"].exists, "the place sheet did not return")
        }
        report("street_view_closed", 1)
    }

    /// The time machine: open the date list, pick the second newest capture, check the date, the
    /// historical flag and that the compass bearing did not turn, then go back to the newest.
    private func exerciseHistory(_ app: XCUIApplication) {
        let dates = intValue("dates", debugID: "street-view-debug")
        report("street_view_dates", dates)
        guard dates > 1 else {
            // A live pano at this spot may legitimately have a single capture. The fixture path
            // always has three.
            report("street_view_history_mode", "single")
            return
        }
        let beforeBearing = intValue("bearing", debugID: "street-view-debug")
        let beforeDate = captureDate()
        let chip = app.buttons["street-view-history"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "no history chip")
        chip.tap()
        let date = app.buttons["street-view-history-date-1"]
        XCTAssertTrue(date.waitForExistence(timeout: 5), "history dates did not open")
        shot("street-view-history-list")
        date.tap()
        XCTAssertTrue(waitUntil(45) {
            self.intValue("hist", debugID: "street-view-debug") == 1 &&
                self.intValue("loading", debugID: "street-view-debug") == 0
        }, "older capture did not load")
        let afterBearing = intValue("bearing", debugID: "street-view-debug")
        let afterDate = captureDate()
        report("street_view_history_bearing", afterBearing)
        report("street_view_history_date", afterDate)
        XCTAssertNotEqual(afterDate, beforeDate, "the capture date did not change")
        XCTAssertLessThanOrEqual(abs(afterBearing - beforeBearing), 1,
                                 "switching capture turned the view from \(beforeBearing) to \(afterBearing)")
        _ = waitUntil(45) { self.intValue("base", debugID: "street-view-debug") == 1 }
        sleep(2)
        shot("street-view-history")

        // Back to the newest capture: the base metadata and its walk arrows return.
        chip.tap()
        let newest = app.buttons["street-view-history-date-0"]
        XCTAssertTrue(newest.waitForExistence(timeout: 5), "history dates did not reopen")
        newest.tap()
        XCTAssertTrue(waitUntil(45) {
            self.intValue("hist", debugID: "street-view-debug") == 0 &&
                self.intValue("loading", debugID: "street-view-debug") == 0
        }, "the newest capture did not come back")
        report("street_view_history_back", captureDate())
        XCTAssertEqual(captureDate(), beforeDate,
                       "returning to the newest capture left the old date")
    }

    /// Year and month of the capture on screen, as one comparable number (2026-10 is 202610).
    private func captureDate() -> Int {
        intValue("year", debugID: "street-view-debug") * 100 +
            intValue("month", debugID: "street-view-debug")
    }

    // MARK: Place sheet

    private func openDavisPlace(_ app: XCUIApplication) {
        let searchField = app.textFields["search-field"]
        sleep(4)
        searchField.tap()
        searchField.typeText("Davis Food Co-op\n")
        let rows = app.buttons.matching(identifier: "search-result")
        if !rows.firstMatch.waitForExistence(timeout: 45) {
            searchField.tap()
            searchField.typeText("\n")
        }
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 45), "no result row")
        sleep(3)
        rows.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["place-name"].waitForExistence(timeout: 20), "no place sheet")
    }

    /// Finds the lazy Street View section without jumping past it, as PlaceUITests does.
    private func reveal(_ element: XCUIElement, in scroll: XCUIElement) -> Bool {
        for _ in 0..<4 {
            if element.isHittable { return true }
            scroll.swipeUp()
            sleep(1)
        }
        for _ in 0..<8 {
            if element.isHittable { return true }
            scroll.swipeDown()
            sleep(1)
        }
        return element.isHittable
    }

    // MARK: Debug line

    private func value(_ key: String, debugID: String) -> String? {
        guard let line = debugText(debugID) else { return nil }
        for part in line.split(separator: " ") where part.hasPrefix("\(key)=") {
            return String(part.dropFirst(key.count + 1))
        }
        return nil
    }

    private func intValue(_ key: String, debugID: String) -> Int {
        Int(value(key, debugID: debugID) ?? "") ?? -1
    }

    /// The pano id is 22 characters and may itself start with "pano", so read it as a whole token.
    private func panoValue(_ debugID: String) -> String? { value("pano", debugID: debugID) }

    private func hasPano(_ debugID: String) -> Bool {
        guard let pano = panoValue(debugID) else { return false }
        return pano != "none" && !pano.isEmpty
    }
}
