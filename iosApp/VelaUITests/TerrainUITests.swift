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

        // A slow first frame is loading, not a failure. Wait for the explicit ready state with a
        // generous deadline; the state line is the contract, not a fixed sleep.
        let ready = waitUntil(120) {
            (debugText("terrain-debug") ?? "").contains("terrain_state=ready")
        }
        let line = debugText("terrain-debug") ?? "no line"
        XCTAssertTrue(ready, "terrain never reached ready: \(line)")
        XCTAssertTrue(line.contains("terrain_webgl=1"), "WebGL did not start: \(line)")
        XCTAssertTrue(line.contains("terrain_dem=1"), "the DEM source never delivered: \(line)")
        XCTAssertTrue(line.contains("terrain_frame=1"), "the document never drew a frame: \(line)")
        XCTAssertFalse(line.contains("terrain_state=unavailable"), "terrain reported unavailable: \(line)")
        XCTAssertFalse(line.contains("terrain_state=offline"), "terrain reported offline while online: \(line)")
        XCTAssertFalse(app.staticTexts["terrain-status"].label.contains("Unavailable"),
                       "the status line says the terrain is unavailable")

        let retry = line.contains("terrain_retry=1") ? 1 : 0
        report("terrain_web", 1)
        report("terrain_dem", 1)
        report("terrain_state", "ready")
        report("terrain_webgl", 1)
        report("terrain_frame", 1)
        report("terrain_retry", retry)

        sleep(8)
        shot("terrain-screen")

        // Pull back to show the horizon, the sky and the distance fog over the same relief.
        app.pinch(withScale: 0.55, velocity: -1)
        sleep(6)
        shot("terrain-atmosphere")

        let afterGesture = debugText("terrain-debug") ?? ""
        XCTAssertTrue(afterGesture.contains("terrain_state=ready"),
                      "the terrain left the ready state during the gesture: \(afterGesture)")

        app.buttons["terrain-close"].tap()
        XCTAssertTrue(app.textFields["search-field"].waitForExistence(timeout: 30),
                      "closing the terrain screen did not return to the map")
        report("terrain_return", 1)
    }
}
