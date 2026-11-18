import XCTest

/// A-2 over Helsinki with deterministic ships and UKMTO rows (`-VelaMaritimeFixture`). The
/// scenario turns the Ships layer on, moves the camera so the host refreshes it, and checks that
/// the sheet lists ships with their four AIS fields and a UKMTO link list. The PNGs are the
/// visual proof; `maritime_count` and `ukmto_mode` are the machine-checked lines.
final class MaritimeUITests: VelaUITestCase {
    func testShipsAndUkmtoList() {
        let app = launch(
            camera: "60.1200,24.9000,10",
            arguments: ["-VelaResetSettings", "YES", "-VelaMaritimeFixture", "YES"])

        openMapAction("layers-button", in: app)
        XCTAssertTrue(app.buttons["layer-painted"].waitForExistence(timeout: 10), "no layers sheet")

        let toggle = app.buttons["world-layer-maritime"]
        reveal(toggle, in: app)
        XCTAssertTrue(toggle.exists, "no Ships row in World layers")
        XCTAssertTrue(toggle.isEnabled, "A-2 installs Ships, the row must be enabled")
        if toggle.value as? String != "on" {
            toggle.tap()
        }
        XCTAssertTrue(waitUntil(5) { app.buttons["world-layer-maritime"].value as? String == "on" },
                      "the Ships switch did not turn on")

        // WLD-1 refreshes a world layer only when the camera moves. The host also applies the
        // style before the refresh, so the pan produces both the rows and the dots.
        app.buttons["layers-close"].tap()
        pan(app)
        XCTAssertTrue(waitUntil(10) { !app.buttons["layers-close"].exists },
                      "the layers sheet did not close")

        openMapAction("layers-button", in: app)
        XCTAssertTrue(app.buttons["layer-painted"].waitForExistence(timeout: 10), "no sheet on reopen")

        let coverage = app.buttons["world-row-maritime-coverage"]
        reveal(coverage, in: app, requireHittable: false)
        XCTAssertTrue(coverage.exists, "the Finland-only state must be visible")
        XCTAssertTrue(coverage.label.contains("Finland only"))
        XCTAssertTrue(coverage.label.contains("Not for navigation"),
                      "AIS must say it is not for navigation")

        let augusta = app.buttons["world-row-maritime-ship-230713000"]
        reveal(augusta, in: app)
        XCTAssertTrue(augusta.exists, "no ship row after the fixture refresh")
        XCTAssertTrue(augusta.label.contains("AUGUSTA"), "the ship name is missing: \(augusta.label)")
        XCTAssertTrue(augusta.label.contains("Cargo"), "the ship type is missing: \(augusta.label)")
        XCTAssertTrue(augusta.label.contains("kn"), "the speed is missing: \(augusta.label)")
        XCTAssertTrue(augusta.label.contains("course"), "the course is missing: \(augusta.label)")
        XCTAssertTrue(augusta.label.contains("MMSI 230713000"), "the MMSI is missing: \(augusta.label)")
        let count = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "world-row-maritime-ship-")).count
        report("maritime_count", count)
        XCTAssertGreaterThan(count, 0, "the sheet shows no ship row")
        shot("maritime")

        app.buttons["layers-close"].tap()
        XCTAssertTrue(waitUntil(10) { !app.buttons["layers-close"].exists },
                      "the layers sheet did not close for the map shot")
        sleep(1)
        shot("maritime-detail")

        openMapAction("layers-button", in: app)
        XCTAssertTrue(app.buttons["layer-painted"].waitForExistence(timeout: 10), "no sheet")

        let header = app.buttons["world-row-maritime-ukmto-header"]
        reveal(header, in: app, swipes: 24, requireHittable: false)
        XCTAssertTrue(header.exists, "no UKMTO header")
        XCTAssertTrue(header.label.contains("link list only"),
                      "the UKMTO list must call itself a link list: \(header.label)")
        XCTAssertTrue(header.label.contains("Not a live advisory feed"),
                      "the UKMTO list must not claim to be a live feed: \(header.label)")
        shot("ukmto")
        let first = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND identifier != %@",
            "world-row-maritime-ukmto-", "world-row-maritime-ukmto-header")).firstMatch
        XCTAssertTrue(first.exists, "no UKMTO incident row")
        XCTAssertTrue(first.label.contains("Link only"), "the UKMTO row is not a link: \(first.label)")
        XCTAssertTrue(first.label.contains("https://www.ukmto.org/recent-incidents#"),
                      "the incident row must carry its link: \(first.label)")
        report("ukmto_mode", "link_only")
    }

    /// Swipes the sheet until [element] is on screen. The World layers section sits below the
    /// six base toggles, so its rows start off screen.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, swipes: Int = 14,
                        requireHittable: Bool = true) {
        for _ in 0..<swipes {
            if element.exists && onScreen(element, in: app)
                && (!requireHittable || element.isHittable) { return }
            app.swipeUp()
            Thread.sleep(forTimeInterval: 0.25)
        }
    }

    /// A disabled row is a valid target for a capture but `isHittable` is false, so visibility
    /// is read from the frame instead.
    private func onScreen(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        guard element.exists, element.frame.height > 0 else { return false }
        let frame = element.frame
        let window = app.windows.firstMatch.frame
        return frame.minY >= 80 && frame.maxY <= window.maxY - 20
    }

    private func pan(_ app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.62, dy: 0.42))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.44, dy: 0.55))
        start.press(forDuration: 0.05, thenDragTo: end)
    }
}
