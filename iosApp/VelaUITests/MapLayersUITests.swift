import XCTest

/// The layers sheet over San Francisco, with deterministic Overpass answers derived from the box.
/// Proves the switches, their loading gates and that each enabled overlay reaches the map style.
final class MapLayersUITests: VelaUITestCase {
    func testLayerSheetLoadsOverlaysAtCloseZoom() {
        let app = launch(
            camera: "37.7749,-122.4194,17",
            arguments: ["-VelaMapLayersFixture", "YES"])

        let button = app.buttons["layers-button"]
        XCTAssertTrue(button.waitForExistence(timeout: 30), "no layers button")
        button.tap()

        let painted = app.buttons["layer-painted"]
        XCTAssertTrue(painted.waitForExistence(timeout: 10), "no layers sheet")
        XCTAssertTrue(app.buttons["layer-traffic"].exists, "the traffic switch must be offered")
        XCTAssertTrue(app.buttons["layer-satellite"].exists, "the satellite switch must be offered")
        shot("layers")

        for id in ["layer-painted", "layer-speed", "layer-alpr", "layer-controls"] {
            let row = app.buttons[id]
            if !row.isHittable { app.swipeUp() }
            XCTAssertTrue(row.waitForExistence(timeout: 5), "missing \(id)")
            row.tap()
            XCTAssertTrue(waitUntil(5) { app.buttons[id].value as? String == "on" },
                          "\(id) did not switch on")
        }
        app.buttons["layers-close"].tap()

        XCTAssertTrue(waitUntil(45) {
            guard let line = debugText("layers-debug") else { return false }
            return line.contains("painted=ready:") && line.contains("speed=ready:")
                && line.contains("alpr=ready:") && line.contains("controls=ready:")
        }, "the four layers never reached ready: \(debugText("layers-debug") ?? "no debug line")")

        let line = debugText("layers-debug") ?? ""
        let paintedCount = count(line, "painted")
        let speedCount = count(line, "speed")
        let alprCount = count(line, "alpr")
        let controlsCount = count(line, "controls")
        report("layers_painted", paintedCount)
        report("layers_speed", speedCount)
        report("layers_alpr", alprCount)
        report("layers_controls", controlsCount)
        XCTAssertGreaterThan(paintedCount, 0, "no painted-road geometry")
        XCTAssertGreaterThan(speedCount, 0, "no speed camera")
        XCTAssertGreaterThan(alprCount, 0, "no ALPR camera")
        XCTAssertGreaterThan(controlsCount, 0, "no traffic control")
        shot("camera-layer")
    }

    /// I-1c: the two keyless rasters over San Francisco, one at a time so each screenshot shows
    /// the layer it names. The map is given time to fetch tiles before each capture. The tiles
    /// themselves are a network service, so the machine-checked part is the switch state; the two
    /// PNGs are the visual proof.
    func testGoogleTrafficAndSatelliteOverSanFrancisco() {
        let app = launch(camera: "37.7749,-122.4194,15.5")

        let button = app.buttons["layers-button"]
        XCTAssertTrue(button.waitForExistence(timeout: 30), "no layers button")
        button.tap()
        XCTAssertTrue(app.buttons["layer-traffic"].waitForExistence(timeout: 10), "no layers sheet")
        toggle(app, id: "layer-traffic", on: true)
        app.buttons["layers-close"].tap()

        XCTAssertTrue(waitUntil(60) {
            guard let line = debugText("layers-debug") else { return false }
            return line.contains("traffic=on") && line.contains("satellite=off")
        }, "traffic never switched on: \(debugText("layers-debug") ?? "no debug line")")
        sleep(20)
        shot("traffic-layer")

        button.tap()
        XCTAssertTrue(app.buttons["layer-satellite"].waitForExistence(timeout: 10))
        toggle(app, id: "layer-traffic", on: false)
        toggle(app, id: "layer-satellite", on: true)
        app.buttons["layers-close"].tap()

        XCTAssertTrue(waitUntil(60) {
            guard let line = debugText("layers-debug") else { return false }
            return line.contains("traffic=off") && line.contains("satellite=on")
        }, "satellite never switched on: \(debugText("layers-debug") ?? "no debug line")")
        sleep(20)
        shot("satellite-layer")
    }

    private func toggle(_ app: XCUIApplication, id: String, on: Bool) {
        let row = app.buttons[id]
        for _ in 0..<3 where !row.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(row.waitForExistence(timeout: 5), "missing \(id)")
        if (row.value as? String == "on") != on {
            row.tap()
        }
        XCTAssertTrue(waitUntil(5) { app.buttons[id].value as? String == (on ? "on" : "off") },
                      "\(id) did not switch \(on ? "on" : "off")")
    }

    private func count(_ line: String, _ key: String) -> Int {
        guard let part = line.split(separator: " ").first(where: { $0.hasPrefix("\(key)=") }) else {
            return 0
        }
        let value = part.split(separator: ":").last.map(String.init) ?? ""
        return Int(value) ?? 0
    }
}
