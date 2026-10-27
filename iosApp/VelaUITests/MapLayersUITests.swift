import XCTest

/// The layers sheet over San Francisco, with deterministic Overpass answers derived from the box.
/// Proves the switches, their loading gates, that each enabled overlay reaches the map style, and
/// that the local style variants, name modes, house numbers and exits render.
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

    func testStyleVariantsRender() {
        let variants = [("vela", "light"), ("vela", "dark"), ("bright", "light"),
                        ("positron", "light"), ("fiord", "light"), ("black", "light")]
        for (look, appearance) in variants {
            // Reset first: I-1c's raster switches persist in the settings suite, so a satellite
            // left on by an earlier scenario would cover the style this capture is meant to show.
            let app = launch(
                camera: "sf",
                arguments: ["-VelaResetSettings", "YES",
                            "-VelaMapLook", look, "-VelaMapAppearance", appearance])
            XCTAssertTrue(app.otherElements["map"].waitForExistence(timeout: 60),
                          "no map for \(look) \(appearance)")
            sleep(8)
            let name = look == "vela" ? "style-vela-\(appearance)" : "style-\(look)"
            shot(name)

            XCTAssertTrue(waitUntil(15) {
                guard let line = debugText("layers-debug") else { return false }
                return line.contains("look=\(look)") && line.contains("appearance=\(appearance)")
            }, "\(name) did not select its style: \(debugText("layers-debug") ?? "no line")")
        }
    }

    func testNamesModesHouseNumbersAndExits() {
        // Chinatown carries name, name:en and a local script, so the three name modes differ.
        for (mode, name) in [("english_latin", "names-english"),
                             ("local", "names-local"),
                             ("local_english", "names-local-english")] {
            let app = launch(
                camera: "37.7941,-122.4078,16",
                arguments: ["-VelaResetSettings", "YES", "-VelaMapNames", mode])
            XCTAssertTrue(app.otherElements["map"].waitForExistence(timeout: 60),
                          "no map for names \(mode)")
            sleep(8)
            shot(name)
            XCTAssertTrue(waitUntil(15) {
                debugText("layers-debug")?.contains("names=\(mode)") == true
            }, "names \(mode): \(debugText("layers-debug") ?? "no line")")
        }

        // House numbers on a residential block at z18, and the I-80 exits at z15.
        let houses = launch(
            camera: "37.7599,-122.4148,18",
            arguments: ["-VelaResetSettings", "YES", "-VelaMapHouseNumbers", "far"])
        XCTAssertTrue(houses.otherElements["map"].waitForExistence(timeout: 60),
                      "no map for house numbers")
        sleep(10)
        shot("map-house-numbers")

        let exits = launch(
            camera: "38.5930,-121.4800,15",
            arguments: ["-VelaResetSettings", "YES"])
        XCTAssertTrue(exits.otherElements["map"].waitForExistence(timeout: 60),
                      "no map for exit numbers")
        sleep(10)
        shot("map-exit-numbers")
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
