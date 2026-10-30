import XCTest

/// G-3 over the G-2 globe at z1 with a CelesTrak snapshot propagated at a fixed instant
/// (`-VelaSatelliteFixture`). The scenario turns the globe on, turns Satellites on, moves the
/// camera so the host refreshes the layer, checks the rows, opens HST's card for its altitude,
/// velocity and next pass, and captures the dots, the card and the orbit track.
///
/// `sat_count`, `sat_projection` and `sat_next_pass_min` are the machine-checked lines; the three
/// PNGs are the visual proof.
final class SatelliteUITests: VelaUITestCase {
    func testSatellitesOverGlobe() {
        let app = launch(
            camera: "0,0,1",
            arguments: ["-VelaResetSettings", "YES", "-VelaSatelliteFixture", "YES"])

        openLayers(app)
        let globe = app.buttons["layer-globe"]
        reveal(globe, app)
        XCTAssertTrue(globe.exists, "no Globe control in the layers sheet")
        if globe.value as? String != "on" { globe.tap() }
        XCTAssertTrue(waitUntil(30) {
            (debugText("globe-debug") ?? "").contains("globe_projection=globe")
        }, "the globe never drew: \(debugText("globe-debug") ?? "no line")")
        report("sat_projection", "globe")

        let toggle = app.buttons["world-layer-satellite"]
        reveal(toggle, app)
        XCTAssertTrue(toggle.exists, "no Satellites row")
        XCTAssertTrue(toggle.isEnabled, "G-3 installs Satellites, the row must be enabled")
        if toggle.value as? String != "on" { toggle.tap() }
        XCTAssertTrue(waitUntil(5) {
            app.buttons["world-layer-satellite"].value as? String == "on"
        }, "the Satellites switch did not turn on")

        // WLD-1 refreshes a world layer only when the camera moves. A short drag is enough, and
        // the fixture's observer stays at (0, 0) so the rows do not depend on the camera.
        app.buttons["layers-close"].tap()
        pan(app)
        sleep(4)
        openLayers(app)

        let status = app.buttons["world-row-sat-status"]
        XCTAssertTrue(revealInSheet(status, in: app, tries: 20), "no satellite status row")
        XCTAssertTrue(status.label.contains("above the horizon"),
                      "the status row must count the visible sky: \(status.label)")

        let hst = app.buttons["world-row-satellite-20580"]
        reveal(hst, app)
        XCTAssertTrue(hst.exists, "no HST row after the fixture refresh")
        XCTAssertTrue(hst.label.contains("HST"), "the satellite name is missing: \(hst.label)")
        XCTAssertTrue(hst.label.contains("km/s"), "the velocity is missing: \(hst.label)")
        XCTAssertTrue(hst.label.contains("elev"), "the elevation is missing: \(hst.label)")

        let count = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "world-row-satellite-")).count
        report("sat_count", count)
        XCTAssertGreaterThan(count, 0, "the sheet shows no satellite row")

        // Deep space is now drawn by SDP4: the fixture carries a geostationary object.
        let geo = app.buttons["world-row-satellite-28912"]
        let hasDeep = revealInSheet(geo, in: app, tries: 20)
        report("sat_deep", hasDeep ? 1 : 0)
        XCTAssertTrue(hasDeep, "the deep-space geostationary fixture is missing from the sheet")
        XCTAssertTrue(geo.label.contains("Alt 35"), "no geostationary altitude: \(geo.label)")

        // The dots over the globe, without the sheet.
        app.buttons["layers-close"].tap()
        XCTAssertTrue(waitUntil(10) { !app.buttons["layers-close"].exists })
        sleep(4)
        shot("satellites")

        // HST's card: altitude, velocity, next pass, and the debug line the summary reads.
        openLayers(app)
        let hstAgain = app.buttons["world-row-satellite-20580"]
        reveal(hstAgain, app)
        XCTAssertTrue(hstAgain.exists, "no HST row on reopen")
        hstAgain.tap()
        let card = app.descendants(matching: .any)["satellite-detail-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 15), "no satellite card")

        let debug = debugText("satellite-debug") ?? ""
        let next = number("sat_next_pass_min", in: debug)
        report("sat_next_pass_min", next)
        XCTAssertGreaterThan(next, 0, "no next pass in the card: \(debug)")
        XCTAssertTrue(debug.contains("sat_projection=globe"), debug)
        XCTAssertTrue(debug.contains("sat_source=fixture"), debug)
        XCTAssertGreaterThan(number("sat_count", in: debug), 0, debug)

        let altitude = app.staticTexts["satellite-detail-altitude"]
        XCTAssertTrue(altitude.exists && altitude.label.contains("km"), "no altitude in the card")
        let velocity = app.staticTexts["satellite-detail-velocity"]
        XCTAssertTrue(velocity.exists && velocity.label.contains("km/s"),
                      "no velocity in the card")
        let pass = app.staticTexts["satellite-detail-pass"]
        XCTAssertTrue(pass.exists && pass.label.contains("Next pass"),
                      "no next pass line in the card")
        shot("satellite-pass")

        app.buttons["satellite-detail-close"].tap()
        if app.buttons["layers-close"].exists { app.buttons["layers-close"].tap() }
        XCTAssertTrue(waitUntil(10) { !app.buttons["layers-close"].exists },
                      "the layers sheet did not close for the orbit shot")
        sleep(4)
        shot("satellite-orbit")
    }

    private func openLayers(_ app: XCUIApplication) {
        let button = app.buttons["layers-button"]
        XCTAssertTrue(button.waitForExistence(timeout: 30), "no layers button")
        button.tap()
        XCTAssertTrue(app.buttons["layer-painted"].waitForExistence(timeout: 10), "no layers sheet")
    }

    /// Swipes the sheet until [element] exists and can be tapped.
    private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<18 where !(element.exists && element.isHittable) {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 0.2)
        }
    }

    private func pan(_ app: XCUIApplication) {
        let map = app.otherElements["map"]
        XCTAssertTrue(map.waitForExistence(timeout: 10), "no map")
        let start = map.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.50))
        let end = map.coordinate(withNormalizedOffset: CGVector(dx: 0.44, dy: 0.50))
        start.press(forDuration: 0.2, thenDragTo: end)
    }

    private func number(_ key: String, in line: String) -> Int {
        for part in line.split(separator: " ") {
            let pair = part.split(separator: "=", maxSplits: 1)
            if pair.count == 2, pair[0] == key, let value = Int(pair[1]) { return value }
        }
        return -1
    }
}
