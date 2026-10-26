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

        let painted = app.switches["layer-painted"]
        XCTAssertTrue(painted.waitForExistence(timeout: 10), "no layers sheet")
        XCTAssertTrue(app.staticTexts["layer-traffic-unavailable"].exists,
                      "the absent Google traffic layer must be visible")
        shot("layers")

        for id in ["layer-painted", "layer-speed", "layer-alpr", "layer-controls"] {
            let toggle = app.switches[id]
            if !toggle.isHittable { app.swipeUp() }
            XCTAssertTrue(toggle.waitForExistence(timeout: 5), "missing \(id)")
            toggle.tap()
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

    private func count(_ line: String, _ key: String) -> Int {
        guard let part = line.split(separator: " ").first(where: { $0.hasPrefix("\(key)=") }) else {
            return 0
        }
        let value = part.split(separator: ":").last.map(String.init) ?? ""
        return Int(value) ?? 0
    }
}
