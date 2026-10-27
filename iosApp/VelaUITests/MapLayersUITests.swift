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
        XCTAssertTrue(app.staticTexts["Not in this build"].firstMatch.exists,
                      "the absent Google traffic and satellite layers must be visible")
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

    func testStyleVariantsRender() {
        let variants = [("vela", "light"), ("vela", "dark"), ("bright", "light"),
                        ("positron", "light"), ("fiord", "light"), ("black", "light")]
        for (look, appearance) in variants {
            let app = launch(
                camera: "sf",
                arguments: ["-VelaMapLook", look, "-VelaMapAppearance", appearance])
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
                arguments: ["-VelaMapNames", mode])
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
            arguments: ["-VelaMapHouseNumbers", "far"])
        XCTAssertTrue(houses.otherElements["map"].waitForExistence(timeout: 60),
                      "no map for house numbers")
        sleep(10)
        shot("map-house-numbers")

        let exits = launch(camera: "38.5930,-121.4800,15")
        XCTAssertTrue(exits.otherElements["map"].waitForExistence(timeout: 60),
                      "no map for exit numbers")
        sleep(10)
        shot("map-exit-numbers")
    }

    private func count(_ line: String, _ key: String) -> Int {
        guard let part = line.split(separator: " ").first(where: { $0.hasPrefix("\(key)=") }) else {
            return 0
        }
        let value = part.split(separator: ":").last.map(String.init) ?? ""
        return Int(value) ?? 0
    }
}
