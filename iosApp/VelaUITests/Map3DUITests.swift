import XCTest

/// M-1: the sheet's 3D switch, the extruded buildings at a tilted close zoom, the shaded relief
/// from AWS Terrain Tiles, and the 60 degree pitch ceiling. Chamonix is used because the valley
/// carries both buildings at z17 and a real elevation range the hillshade can show.
final class Map3DUITests: VelaUITestCase {
    func testBuildingsPitchAndRelief() {
        let app = launch(camera: "45.9237,6.8694,17.0",
                         arguments: ["-VelaResetSettings", "YES"])

        openLayers(app)
        let toggle = app.buttons["layer-3d"]
        XCTAssertTrue(revealInSheet(toggle, in: app), "no 3D switch")
        XCTAssertEqual(toggle.value as? String, "off", "3D must start off")
        toggle.tap()
        XCTAssertTrue(waitUntil(10) { app.buttons["layer-3d"].value as? String == "on" },
                      "the 3D switch did not turn on")

        XCTAssertTrue(waitUntil(20) {
            let line = debugText("map-3d-debug") ?? ""
            return line.contains("3d=on") && line.contains("relief=1")
                && line.contains("buildings=1")
        }, "3D never reached relief and buildings: \(debugText("map-3d-debug") ?? "no line")")

        let first = debugText("map-3d-debug") ?? ""
        let firstPitch = number("pitch", in: first)
        report("map_3d", 1)
        report("map_relief", 1)
        report("map_pitch", firstPitch)
        XCTAssertGreaterThanOrEqual(firstPitch, 20, "turning 3D on did not tilt the camera")
        XCTAssertLessThanOrEqual(firstPitch, 60, "pitch left the 60 degree ceiling")

        app.buttons["layers-close"].tap()
        sleep(6)
        shot("map-3d")

        // A mountain view without extrusions: the relief is the only new drawing.
        app.terminate()
        let relief = launch(camera: "45.9237,6.8694,14.2",
                            arguments: ["-VelaMapPitch", "55"])
        openLayers(relief)
        XCTAssertTrue(revealInSheet(relief.buttons["layer-3d"], in: relief),
                      "the 3D switch did not persist")
        XCTAssertEqual(relief.buttons["layer-3d"].value as? String, "on",
                       "3D must persist across launches")
        XCTAssertTrue(waitUntil(20) {
            (debugText("map-3d-debug") ?? "").contains("relief=1")
        }, "relief was not installed on the second launch: \(debugText("map-3d-debug") ?? "no line")")
        let reliefLine = debugText("map-3d-debug") ?? ""
        XCTAssertEqual(number("pitch", in: reliefLine), 55, "the launch pitch did not apply")
        XCTAssertEqual(number("buildings", in: reliefLine), 0,
                       "no extrusion should be drawn at zoom 14.2")
        relief.buttons["layers-close"].tap()
        sleep(6)
        shot("map-hillshade")

        // The ceiling itself: 60 degrees, extrusions still drawn, relief still installed.
        relief.terminate()
        let pitch = launch(camera: "45.9237,6.8694,17.0",
                           arguments: ["-VelaMapPitch", "60"])
        openLayers(pitch)
        XCTAssertTrue(revealInSheet(pitch.buttons["layer-3d"], in: pitch), "no 3D switch")
        XCTAssertTrue(waitUntil(20) {
            let line = debugText("map-3d-debug") ?? ""
            return line.contains("relief=1") && line.contains("buildings=1")
        }, "the pitch ceiling view never drew: \(debugText("map-3d-debug") ?? "no line")")
        let ceiling = debugText("map-3d-debug") ?? ""
        XCTAssertEqual(number("pitch", in: ceiling), 60, "the pitch exceeded or missed 60")
        report("map_pitch", number("pitch", in: ceiling))
        pitch.buttons["layers-close"].tap()
        sleep(5)
        shot("map-3d-pitch")

        // Leave the shared settings suite flat for the MapLayers scenarios.
        openLayers(pitch)
        XCTAssertTrue(revealInSheet(pitch.buttons["layer-3d"], in: pitch), "no 3D switch")
        if pitch.buttons["layer-3d"].value as? String == "on" {
            pitch.buttons["layer-3d"].tap()
        }
        pitch.buttons["layers-close"].tap()
    }

    private func openLayers(_ app: XCUIApplication) {
        let button = app.buttons["layers-button"]
        XCTAssertTrue(button.waitForExistence(timeout: 30), "no layers button")
        button.tap()
    }

    private func number(_ key: String, in line: String) -> Int {
        guard let token = line.split(separator: " ").first(where: { $0.hasPrefix("\(key)=") }),
              let value = token.split(separator: "=").last else { return 0 }
        return Int(value) ?? 0
    }
}
