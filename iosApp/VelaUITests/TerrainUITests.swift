import XCTest

/// M-2: the separate Relief screen in MapLibre GL JS. The test opens the Debug-only launch
/// fixture, waits for the bundled document and the DEM source, captures the tilted terrain and
/// the sky, and checks that closing the screen returns to the native map.
final class TerrainUITests: VelaUITestCase {
    func testTerrainScreenRenders() {
        let app = launch(camera: "45.9237,6.8694,13.0",
                         arguments: ["-VelaResetSettings", "YES", "-VelaTerrainFixture", "YES"])

        XCTAssertTrue(app.buttons["terrain-close"].waitForExistence(timeout: 40),
                      "the terrain screen did not open")
        XCTAssertTrue(app.staticTexts["terrain-attribution"].exists,
                      "the terrain and OpenFreeMap attribution is missing")

        let ready = waitUntil(90) {
            let line = debugText("terrain-debug") ?? ""
            return line.contains("terrain_web=1") && line.contains("terrain_dem=1")
        }
        XCTAssertTrue(ready, "terrain never reported the web document and the DEM: "
                      + (debugText("terrain-debug") ?? "no line"))
        XCTAssertFalse(debugText("terrain-debug")?.contains("terrain_state=unavailable") ?? false,
                       "terrain reported unavailable while online")
        XCTAssertFalse(app.staticTexts["terrain-status"].label.contains("Unavailable"),
                       "the status line says the terrain is unavailable")

        report("terrain_web", 1)
        report("terrain_dem", 1)
        report("terrain_state", "ready")

        sleep(8)
        shot("terrain-screen")

        // Pull back to show the horizon, the sky and the distance fog over the same relief.
        app.pinch(withScale: 0.55, velocity: -1)
        sleep(6)
        shot("terrain-atmosphere")

        app.buttons["terrain-close"].tap()
        XCTAssertTrue(app.textFields["search-field"].waitForExistence(timeout: 30),
                      "closing the terrain screen did not return to the map")
        report("terrain_return", 1)
    }
}
