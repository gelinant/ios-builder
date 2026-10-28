import XCTest

/// MAP-POI over Davis, the only place the bundled Vela pack covers. Proves the three sources
/// (Vela pack, vector tiles, both), that the Vela source draws with no raster request after a
/// pan, and captures the three icon sizes on the same camera.
final class MapPoiUITests: VelaUITestCase {
    func testPoiSourceAndIconSize() {
        let app = launch(
            camera: "38.5449,-121.7405,16",
            arguments: ["-VelaResetSettings", "YES"])

        openSheet(app)
        revealSources(app)
        XCTAssertTrue(app.buttons["poi-source-vela"].waitForExistence(timeout: 10),
                      "no Vela source row")
        XCTAssertTrue(app.buttons["poi-source-tiles"].exists, "no tiles source row")
        XCTAssertTrue(app.buttons["poi-source-both"].exists, "no both source row")

        selectSource(app, "vela")
        closeSheet(app)
        XCTAssertTrue(waitUntil(10) { debugText("layers-debug")?.contains("poi=vela") == true },
                      "vela source: \(debugText("layers-debug") ?? "no line")")

        openSheet(app)
        selectSource(app, "tiles")
        closeSheet(app)
        XCTAssertTrue(waitUntil(10) { debugText("layers-debug")?.contains("poi=tiles") == true },
                      "tiles source: \(debugText("layers-debug") ?? "no line")")
        sleep(2)
        shot("poi-source-tiles")

        openSheet(app)
        selectSource(app, "vela")
        closeSheet(app)
        XCTAssertTrue(waitUntil(10) { debugText("layers-debug")?.contains("poi=vela") == true },
                      "vela source again: \(debugText("layers-debug") ?? "no line")")

        // A pan under the Vela source must send nothing to Google or Esri. The debug line also
        // names the bundled pack, so an empty pack cannot pass as "no request".
        pan(app)
        XCTAssertTrue(waitUntil(15) {
            guard let line = debugText("layers-debug") else { return false }
            return line.contains("poi=vela") && line.contains("tiles=0")
        }, "after the pan: \(debugText("layers-debug") ?? "no line")")
        let line = debugText("layers-debug") ?? ""
        report("poi_source", "vela")
        report("poi_tiles", count(line, "tiles"))
        report("poi_pack", count(line, "pack"))
        XCTAssertEqual(count(line, "tiles"), 0, "the Vela source must not request a raster tile")
        XCTAssertGreaterThan(count(line, "pack"), 0, "the Vela pack is empty")
        sleep(2)
        shot("poi-source-vela")

        let sizes = [("Small", "0.70", "poi-icons-small"),
                     ("Default", "1.00", "poi-icons-default"),
                     ("Large", "1.25", "poi-icons-large")]
        for (label, value, name) in sizes {
            openSheet(app)
            chooseSize(app, label)
            closeSheet(app)
            XCTAssertTrue(waitUntil(10) {
                debugText("layers-debug")?.contains("icon=\(value)") == true
            }, "size \(label): \(debugText("layers-debug") ?? "no line")")
            sleep(2)
            shot(name)
        }
    }

    private func openSheet(_ app: XCUIApplication) {
        let button = app.buttons["layers-button"]
        XCTAssertTrue(button.waitForExistence(timeout: 30), "no layers button")
        button.tap()
        // The Done button lives in the navigation bar, so it proves the sheet opened whatever
        // part of the scrolling form is on screen. The source rows sit under the layer sections
        // and a lazy Form only builds the visible ones.
        XCTAssertTrue(app.buttons["layers-close"].waitForExistence(timeout: 10),
                      "no layers sheet")
    }

    private func revealSources(_ app: XCUIApplication) {
        for _ in 0..<5 where !app.buttons["poi-source-vela"].exists {
            app.swipeUp()
        }
    }

    private func closeSheet(_ app: XCUIApplication) {
        let close = app.buttons["layers-close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
    }

    private func selectSource(_ app: XCUIApplication, _ source: String) {
        let row = app.buttons["poi-source-\(source)"]
        for _ in 0..<6 where !row.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(row.waitForExistence(timeout: 5), "missing poi-source-\(source)")
        if row.value as? String != "on" {
            row.tap()
        }
        XCTAssertTrue(waitUntil(5) { app.buttons["poi-source-\(source)"].value as? String == "on" },
                      "poi-source-\(source) did not switch on")
    }

    private func chooseSize(_ app: XCUIApplication, _ label: String) {
        let picker = app.segmentedControls["poi-icon-size"]
        for _ in 0..<5 where !picker.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "no icon size picker")
        let option = picker.buttons[label]
        if option.waitForExistence(timeout: 5), option.isHittable {
            option.tap()
        } else {
            XCTAssertTrue(app.buttons[label].waitForExistence(timeout: 5), "no \(label) size")
            app.buttons[label].tap()
        }
    }

    private func pan(_ app: XCUIApplication) {
        let map = app.otherElements["map"]
        XCTAssertTrue(map.waitForExistence(timeout: 10), "no map")
        let start = map.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.58))
        let end = map.coordinate(withNormalizedOffset: CGVector(dx: 0.36, dy: 0.58))
        start.press(forDuration: 0.2, thenDragTo: end)
    }

    private func count(_ line: String, _ key: String) -> Int {
        guard let part = line.split(separator: " ").first(where: { $0.hasPrefix("\(key)=") }) else {
            return 0
        }
        let value = part.split(separator: "=").last.map(String.init) ?? ""
        return Int(value) ?? 0
    }
}
