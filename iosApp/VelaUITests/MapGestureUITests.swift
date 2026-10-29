import XCTest

/// MAP-GESTE (L16-L18, L38-L40, L264): rotation and north, the north lock across a relaunch, the
/// start-position choice, the scale bar, square map buttons and the long-press pin.
final class MapGestureUITests: VelaUITestCase {
    private let centerLatitude = 37.7749
    private let centerLongitude = -122.4194

    func testRotationReturnsNorth() {
        let app = launch(camera: "37.7749,-122.4194,17",
                         arguments: ["-VelaResetSettings", "YES"])
        let map = app.descendants(matching: .any)["map"]
        XCTAssertTrue(map.waitForExistence(timeout: 20), "no map")
        sleep(2)

        map.rotate(1.0, withVelocity: 0.6)
        XCTAssertTrue(waitUntil(10) { bearing(app) > 5 },
                      "the two-finger rotation did not turn the map: \(gestureLine(app))")
        let turned = bearing(app)
        app.buttons["map-compass"].tap()
        XCTAssertTrue(waitUntil(10) { bearing(app) <= 1 },
                      "the compass did not return the map to north: \(gestureLine(app))")
        shot("north")
        report("gesture_bearing", turned)
        report("gesture_north", 1)
    }

    func testKeepNorthUp() {
        let first = launch(camera: "37.7749,-122.4194,17",
                           arguments: ["-VelaResetSettings", "YES"])
        toggle(first, "settings-keep-north-up")
        first.terminate()

        // No reset on this launch: the choice must survive the relaunch.
        let app = launch(camera: "37.7749,-122.4194,17")
        let map = app.descendants(matching: .any)["map"]
        XCTAssertTrue(map.waitForExistence(timeout: 20), "no map")
        XCTAssertTrue(waitUntil(10) { debug(app, "gesture-debug") != nil },
                      "no gesture debug line after the relaunch")
        map.rotate(1.0, withVelocity: 0.6)
        sleep(2)
        XCTAssertLessThanOrEqual(bearing(app), 1,
                                 "the north lock let the map turn: \(gestureLine(app))")
        sleep(2)
        XCTAssertLessThanOrEqual(bearing(app), 1,
                                 "the north lock lost its bearing: \(gestureLine(app))")
        shot("north-locked")
        report("gesture_north", 1)
        report("keep_north_up", 1)
    }

    func testStartPosition() {
        let first = launch(camera: "37.7749,-122.4194,17",
                           arguments: ["-VelaResetSettings", "YES"])
        setStartView(first, "A city view")
        setMapButtons(first, "Square")
        shot("gesture-settings")
        first.terminate()

        // No start camera: the city choice must beat both the position and the last camera.
        let app = XCUIApplication()
        app.launchArguments = ["-VelaDeterministic", "YES"]
        app.launch()
        XCTAssertTrue(app.textFields["search-field"].waitForExistence(timeout: 60), "no map screen")
        XCTAssertTrue(waitUntil(20) { startLine(app).contains("start_center=") },
                      "the map never settled: \(startLine(app))")
        XCTAssertTrue(startLine(app).contains("start_camera=default"),
                      "the city choice did not open on the default camera: \(startLine(app))")
        let center = startCenter(app)
        XCTAssertEqual(center.latitude, centerLatitude, accuracy: 0.01)
        XCTAssertEqual(center.longitude, centerLongitude, accuracy: 0.01)
        XCTAssertEqual(center.zoom, 12, accuracy: 0.6,
                       "a city view opens at the configured zoom, not the position zoom")
        XCTAssertLessThanOrEqual(bearing(app), 1, "the map does not open north-up")

        let scale = scaleText(app)
        XCTAssertFalse(scale.isEmpty, "no scale bar: \(gestureLine(app))")
        shot("scale")
        report("gesture_scale", scale)
        report("gesture_north", bearing(app) <= 1 ? 1 : 0)
        report("gesture_start_zoom", String(format: "%.1f", center.zoom))
    }

    func testLongPressDropsPin() {
        let app = launch(camera: "37.7749,-122.4194,15",
                         arguments: ["-VelaResetSettings", "YES"])
        let map = app.descendants(matching: .any)["map"]
        XCTAssertTrue(map.waitForExistence(timeout: 20), "no map")
        sleep(2)
        map.press(forDuration: 1.2)
        XCTAssertTrue(app.otherElements["dropped-pin-card"].waitForExistence(timeout: 10)
                        || app.descendants(matching: .any)["dropped-pin-card"]
                            .waitForExistence(timeout: 2),
                      "a long press opened no dropped-pin card")
        let coordinates = app.staticTexts["dropped-pin-coordinates"]
        XCTAssertTrue(coordinates.exists, "the card shows no coordinate")
        XCTAssertTrue(app.buttons["dropped-pin-directions"].exists,
                      "the card has no Directions action")
        shot("long-press")
        report("dropped_pin", coordinates.label.replacingOccurrences(of: ", ", with: ","))
    }

    // MARK: - Helpers

    private func openSettings(_ app: XCUIApplication) {
        let overflow = app.buttons["map-overflow"]
        XCTAssertTrue(overflow.waitForExistence(timeout: 20), "no overflow button")
        // The search chrome is rebuilt when a sheet closes; a tap that lands during that rebuild
        // does not open the menu, so the tap is retried once.
        let item = app.buttons["settings-menu-item"]
        overflow.tap()
        if !item.waitForExistence(timeout: 6) {
            overflow.tap()
        }
        XCTAssertTrue(item.waitForExistence(timeout: 10), "no Settings item")
        item.tap()
        XCTAssertTrue(app.descendants(matching: .any)["settings-screen"]
                        .waitForExistence(timeout: 15), "no settings screen")
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        var tries = 0
        while !element.exists && tries < 8 {
            app.swipeUp()
            tries += 1
        }
    }

    private func toggle(_ app: XCUIApplication, _ id: String) {
        openSettings(app)
        let control = app.switches[id]
        reveal(control, in: app)
        XCTAssertTrue(control.waitForExistence(timeout: 10), "no \(id) switch")
        if control.value as? String != "1" { control.tap() }
        XCTAssertTrue(waitUntil(5) { control.value as? String == "1" },
                      "\(id) did not stay on")
        closeSettings(app)
    }

    private func setStartView(_ app: XCUIApplication, _ title: String) {
        openSettings(app)
        let menu = app.descendants(matching: .any)["settings-start-view"]
        reveal(menu, in: app)
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "no start view menu")
        menu.tap()
        let option = app.buttons[title]
        if option.waitForExistence(timeout: 8) {
            option.tap()
        } else {
            let text = app.staticTexts[title]
            XCTAssertTrue(text.waitForExistence(timeout: 5), "no \(title) option")
            text.tap()
        }
        closeSettings(app)
    }

    private func setMapButtons(_ app: XCUIApplication, _ title: String) {
        openSettings(app)
        let menu = app.descendants(matching: .any)["settings-map-buttons"]
        reveal(menu, in: app)
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "no map buttons menu")
        menu.tap()
        let option = app.buttons[title]
        if option.waitForExistence(timeout: 8) {
            option.tap()
        } else {
            let text = app.staticTexts[title]
            XCTAssertTrue(text.waitForExistence(timeout: 5), "no \(title) option")
            text.tap()
        }
        closeSettings(app)
    }

    private func closeSettings(_ app: XCUIApplication) {
        let done = app.buttons["settings-done"]
        if done.exists { done.tap() }
        XCTAssertTrue(app.textFields["search-field"].waitForExistence(timeout: 15),
                      "settings did not close")
    }

    /// A Debug status line of the launched app. The base class keeps `app` private, so a relaunch
    /// passes its own application instead of replacing the base one.
    private func debug(_ app: XCUIApplication, _ id: String) -> String? {
        let element = app.staticTexts[id]
        return element.exists ? element.label : nil
    }

    private func gestureLine(_ app: XCUIApplication) -> String {
        debug(app, "gesture-debug") ?? ""
    }

    /// The value after `key=` up to the next space.
    private func number(_ line: String, _ key: String) -> Double {
        guard let range = line.range(of: key + "=") else { return -1 }
        let rest = line[range.upperBound...]
        let value = rest.prefix { $0 != " " }
        return Double(value) ?? -1
    }

    private func bearing(_ app: XCUIApplication) -> Double {
        number(gestureLine(app), "gesture_bearing")
    }

    /// `gesture_scale=200 m` runs to the end of the line: the label itself may contain a space.
    private func scaleText(_ app: XCUIApplication) -> String {
        let line = gestureLine(app)
        guard let range = line.range(of: "gesture_scale=") else { return "" }
        return String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
    }

    private func startLine(_ app: XCUIApplication) -> String {
        debug(app, "start-debug") ?? ""
    }

    /// `start_center=lat,lng,zoom` as written by MapScreen.
    private func startCenter(_ app: XCUIApplication) -> (latitude: Double, longitude: Double, zoom: Double) {
        let line = startLine(app)
        guard let range = line.range(of: "start_center=") else { return (0, 0, 0) }
        let parts = line[range.upperBound...].split(separator: ",")
        guard parts.count == 3, let latitude = Double(parts[0]),
              let longitude = Double(parts[1]), let zoom = Double(parts[2]) else {
            return (0, 0, 0)
        }
        return (latitude, longitude, zoom)
    }
}
