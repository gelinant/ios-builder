import XCTest

/// G-2: the style-level globe, the z1 zoom-out floor, the camera across the switch, and the same
/// map over a downloaded PMTiles region. The three PNGs are the visual proof.
final class GlobeUITests: VelaUITestCase {
    func testSwitchToGlobeAndBack() {
        let app = launch(camera: "37.7749,-122.4194,12",
                         arguments: ["-VelaResetSettings", "YES"])

        openLayers(app)
        let globe = app.buttons["layer-globe"]
        XCTAssertTrue(revealInSheet(globe, in: app), "no Globe control in the layers sheet")
        XCTAssertEqual(globe.value as? String, "off", "the map must start in Mercator")
        globe.tap()

        XCTAssertTrue(waitUntil(30) {
            let line = debugText("globe-debug") ?? ""
            return line.contains("globe_projection=globe")
                && line.contains("globe_zoom_clamp=1")
                && line.contains("globe_camera_kept=1")
        }, "the globe never drew or kept the camera: \(debugText("globe-debug") ?? "no line")")

        let switched = debugText("globe-debug") ?? ""
        XCTAssertEqual(number("globe_zoom_clamp", in: switched), 1)
        XCTAssertEqual(number("globe_camera_kept", in: switched), 1)
        report("globe_projection", "globe")
        report("globe_zoom_clamp", 1)
        report("globe_camera_kept", 1)

        app.buttons["layers-close"].tap()
        sleep(8)
        shot("globe-in-app")

        // The globe floor: repeated pinch-out requests must stop at z1, not at MapLibre's z0.
        let map = app.otherElements["map"]
        XCTAssertTrue(map.waitForExistence(timeout: 10), "no map element")
        for _ in 0..<6 { map.pinch(withScale: 0.2, velocity: -1) }
        openLayers(app)
        XCTAssertTrue(revealInSheet(globe, in: app), "the Globe row disappeared")
        XCTAssertTrue(waitUntil(15) {
            (debugText("globe-debug") ?? "").contains("globe_zoom=1.00")
        }, "zoom-out left the globe below z1: \(debugText("globe-debug") ?? "no line")")
        report("globe_zoom_clamp", 1)
        app.buttons["layers-close"].tap()
        sleep(3)
        shot("globe-z1")
        openLayers(app)
        XCTAssertTrue(revealInSheet(globe, in: app), "the Globe row disappeared")

        // Back to Mercator with the same camera path, then leave the shared settings suite clean.
        globe.tap()
        XCTAssertTrue(waitUntil(30) {
            (debugText("globe-debug") ?? "").contains("globe_projection=mercator")
        }, "the map did not return to Mercator: \(debugText("globe-debug") ?? "no line")")
        report("globe_projection_back", "mercator")
        app.buttons["layers-close"].tap()
        sleep(6)
        shot("globe-back")

        // Offline: the fixture downloads Monaco's PMTiles basemap, then the globe must draw it
        // with no remote style URL.
        app.terminate()
        XCTAssertTrue(waitUntil(15) { app.state == .notRunning }, "the app did not stop")
        app.launchArguments = [
            "-VelaOfflineTest", "YES", "-VelaOfflineFixture", "YES",
            "-VelaStartCamera", "43.7391,7.4280,14", "-VelaDeterministic", "YES",
        ]
        app.launch()
        XCTAssertTrue(app.textFields["search-field"].waitForExistence(timeout: 60), "no map screen")

        downloadMonacoFixture(app)
        XCTAssertTrue(app.staticTexts["offline-installed-monaco"].waitForExistence(timeout: 180),
                      "the Monaco fixture region did not install")
        XCTAssertTrue(app.staticTexts["offline-ready"].waitForExistence(timeout: 60),
                      "the fixture region did not settle")
        XCTAssertTrue(waitUntil(30) { !app.progressIndicators["offline-progress"].exists })

        // Cut the network so the capture proves the local archive, not a remote style.
        let block = app.buttons["offline-test-block"]
        if block.waitForExistence(timeout: 5) {
            _ = revealInSheet(block, in: app)
            block.tap()
        }
        app.buttons["offline-done"].tap()

        XCTAssertTrue(waitUntil(60) {
            (self.debugText("offline-map-debug") ?? "").contains("archive=monaco.pmtiles remote=0")
        }, "the downloaded region did not mount: \(debugText("offline-map-debug") ?? "none")")

        openLayers(app)
        XCTAssertTrue(revealInSheet(globe, in: app), "no Globe row over the offline region")
        globe.tap()
        XCTAssertTrue(waitUntil(60) {
            let globeLine = self.debugText("globe-debug") ?? ""
            return globeLine.contains("globe_projection=globe")
                && globeLine.contains("globe_camera_kept=1")
        }, "the globe did not switch over the offline region: \(debugText("globe-debug") ?? "no line")")
        app.buttons["layers-close"].tap()
        XCTAssertTrue(waitUntil(60) {
            (self.debugText("offline-map-debug") ?? "").contains("archive=monaco.pmtiles remote=0")
        }, "the globe lost the offline archive: \(debugText("offline-map-debug") ?? "none")")
        report("globe_offline", 1)
        report("globe_offline_remote", 0)
        sleep(8)
        shot("globe-offline")

        // Leave the shared projection at Mercator for the rest of the suite.
        openLayers(app)
        XCTAssertTrue(revealInSheet(globe, in: app), "no Globe row")
        if globe.value as? String == "on" { globe.tap() }
        app.buttons["layers-close"].tap()
    }

    private func openLayers(_ app: XCUIApplication) {
        let button = app.buttons["layers-button"]
        XCTAssertTrue(button.waitForExistence(timeout: 30), "no layers button")
        button.tap()
    }

    private func downloadMonacoFixture(_ app: XCUIApplication) {
        app.buttons["map-overflow"].tap()
        XCTAssertTrue(app.buttons["offline-menu-item"].waitForExistence(timeout: 10),
                      "no offline menu")
        app.buttons["offline-menu-item"].tap()
        let reset = app.buttons["offline-test-reset"]
        XCTAssertTrue(reset.waitForExistence(timeout: 15), "no fixture reset")
        reset.tap()
        let filter = app.textFields["offline-filter"]
        XCTAssertTrue(revealInSheet(filter, in: app), "no region filter")
        filter.tap()
        filter.typeText("Monaco")
        if app.keyboards.buttons["return"].exists { app.keyboards.buttons["return"].tap() }
        let download = app.buttons["offline-download-monaco"]
        XCTAssertTrue(revealInSheet(download, in: app), "Monaco is missing from the catalog")
        download.tap()
    }

    private func number(_ key: String, in line: String) -> Int {
        for part in line.split(separator: " ") {
            let pair = part.split(separator: "=", maxSplits: 1)
            if pair.count == 2, pair[0] == key, let value = Int(pair[1]) { return value }
        }
        return -1
    }
}
