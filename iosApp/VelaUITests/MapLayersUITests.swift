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

    /// OFF-CAM: with the network cut and the camera source pinned to the pack, both camera shapes
    /// must come from the bundled file alone. The debug token names the pack and its date, and the
    /// count comes from the pack selection, not from an Overpass answer.
    func testOfflineCameraPackDraws() {
        let app = launch(
            camera: "37.7749,-122.4194,15.5",
            arguments: ["-VelaResetSettings", "YES", "-VelaCameraSource", "pack",
                        "-VelaOfflineTest", "YES"])

        // Cut every HTTP(S) request after the first tiles have rendered, then draw the cameras.
        app.buttons["map-overflow"].tap()
        XCTAssertTrue(app.buttons["offline-menu-item"].waitForExistence(timeout: 10), "no offline menu")
        app.buttons["offline-menu-item"].tap()
        let block = app.buttons["offline-test-block"]
        XCTAssertTrue(block.waitForExistence(timeout: 10), "no test network switch")
        for _ in 0..<4 where !block.isHittable {
            if app.scrollViews.firstMatch.exists { app.scrollViews.firstMatch.swipeDown() } else { app.swipeDown() }
        }
        block.tap()
        app.buttons["offline-done"].tap()

        let button = app.buttons["layers-button"]
        XCTAssertTrue(button.waitForExistence(timeout: 30), "no layers button")
        button.tap()
        for id in ["layer-speed", "layer-alpr"] {
            toggle(app, id: id, on: true)
        }
        // The camera source rows sit at the bottom of the sheet, after the style choices. Swiping
        // up keeps the sheet open; a downward swipe at the top would dismiss it.
        let pack = app.buttons["camera-source-pack"]
        for _ in 0..<10 where !(pack.exists && pack.isHittable) { app.swipeUp() }
        XCTAssertTrue(pack.waitForExistence(timeout: 10), "no camera source rows")
        XCTAssertEqual(pack.value as? String, "on", "the launch argument did not select the pack")
        shot("offline-camera-source")
        app.buttons["layers-close"].tap()

        XCTAssertTrue(waitUntil(45) {
            guard let line = self.debugText("layers-debug") else { return false }
            return line.contains("cam=pack:camera-pack-2026-07-21:")
        }, "the pack source never reached the map: \(debugText("layers-debug") ?? "no debug line")")

        let line = debugText("layers-debug") ?? ""
        let packed = count(line, "cam")
        report("cameras_pack", "camera-pack-2026-07-21")
        report("cameras_pack_date", "2026-07-21")
        report("cameras_pack_count", packed)
        XCTAssertGreaterThan(packed, 0, "the pack drew no camera: \(line)")
        sleep(2)
        shot("offline-camera-pack")
    }

    /// MAP-CAM: one tagged head and one untagged camera over San Francisco. The debug line says
    /// how many drawn cameras carry a bearing, and the second capture is taken after a two-finger
    /// map rotation: the world-space wedges turn with the map instead of staying screen-north.
    func testCameraConesFollowTheMap() {
        let app = launch(
            camera: "37.7749,-122.4194,17",
            arguments: ["-VelaResetSettings", "YES", "-VelaMapLayersFixture", "YES"])

        let button = app.buttons["layers-button"]
        XCTAssertTrue(button.waitForExistence(timeout: 30), "no layers button")
        button.tap()
        toggle(app, id: "layer-alpr", on: true)
        app.buttons["layers-close"].tap()

        XCTAssertTrue(waitUntil(45) {
            guard let line = self.debugText("layers-debug") else { return false }
            return line.contains("alpr=ready:2") && line.contains("oriented=1 unoriented=1")
        }, "the fixture cameras never reached the map: \(debugText("layers-debug") ?? "no debug line")")

        let line = debugText("layers-debug") ?? ""
        let oriented = camCount(line, "oriented")
        let unoriented = camCount(line, "unoriented")
        report("cameras_oriented", oriented)
        report("cameras_unoriented", unoriented)
        XCTAssertEqual(oriented, 1, "the direction-tagged camera must keep its bearing: \(line)")
        XCTAssertEqual(unoriented, 1, "the untagged camera must stay a bare dot: \(line)")
        shot("camera-cones")

        let map = app.otherElements["map"]
        XCTAssertTrue(map.waitForExistence(timeout: 10), "no map to rotate")
        map.rotate(CGFloat.pi / 5, withVelocity: 1)
        sleep(2)
        shot("camera-cones-rotated")

        // Leave the switch off: this scenario sorts before the overlay scenario, whose toggle
        // helper expects to start from the default off state.
        button.tap()
        XCTAssertTrue(app.buttons["layer-alpr"].waitForExistence(timeout: 10), "no layers sheet")
        toggle(app, id: "layer-alpr", on: false)
        app.buttons["layers-close"].tap()
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

    private func camCount(_ line: String, _ key: String) -> Int {
        guard let part = line.split(separator: " ").first(where: { $0.hasPrefix("\(key)=") }) else {
            return 0
        }
        return Int(part.split(separator: "=").last.map(String.init) ?? "") ?? 0
    }
}
