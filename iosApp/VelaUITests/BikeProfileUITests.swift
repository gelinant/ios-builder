import XCTest

/// RTE-BIKE: the bike profile is a real preference (Android's `bike_safe` key), it applies before
/// the next route request, and the chooser's profile step replans the ride without changing the
/// travel mode. The open router's unsupported knobs are named as such in both places.
final class BikeProfileUITests: VelaUITestCase {
    func testBikePreferencesChangeTheRoute() throws {
        let app = launch(camera: "sf", followUser: true,
                         arguments: ["-VelaResetSettings", "YES", "-VelaBikeProfileFixture", "YES"])

        openSettings(app)
        let toggle = app.switches["settings-bike-safe"]
        scrollTo(toggle, in: app)
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "no bike profile switch")
        XCTAssertEqual(String(describing: toggle.value ?? ""), "1", "the safety profile is not the default")
        XCTAssertTrue(element("settings-bike-hills-row", in: app).exists, "no unsupported hills row")
        XCTAssertTrue(element("settings-bike-steps-row", in: app).exists, "no unsupported steps row")
        XCTAssertTrue(element("settings-bike-unpaved-row", in: app).exists, "no unsupported unpaved row")
        report("bike_settings_default", toggle.value ?? "?")
        shot("bike-settings")

        setSwitch(toggle, on: false)
        XCTAssertEqual(String(describing: toggle.value ?? ""), "0", "the bike switch did not turn off")
        app.buttons["settings-done"].tap()
        XCTAssertTrue(app.textFields["search-field"].waitForExistence(timeout: 10), "no map after settings")

        openDirections(app, query: "Ferry Building")
        app.buttons["route-mode-BICYCLE"].tap()
        XCTAssertTrue(waitUntil(120) { self.value(app, "mode") == "BICYCLE" && self.value(app, "loading") == "0" },
                      "no bicycle route: \(debugText("route-debug") ?? "none")")
        let fastSeconds = Int(value(app, "seconds") ?? "") ?? -1
        report("bike_fast_seconds", fastSeconds)
        report("bike_fast_meters", value(app, "meters") ?? "?")
        report("bike_fast_profile", value(app, "bikeSafe") ?? "?")
        XCTAssertGreaterThan(fastSeconds, 0, "no fastest bicycle route")
        XCTAssertEqual(value(app, "bikeSafe"), "0")

        expandRoute(app)
        XCTAssertTrue(app.otherElements["route-bike-profile"].waitForExistence(timeout: 5)
            || element("route-bike-profile", in: app).exists, "no bike profile step")
        let safe = app.buttons["route-bike-profile-safe"]
        XCTAssertTrue(safe.waitForExistence(timeout: 5), "no safety profile button")
        scrollRouteTo(safe, in: app)
        safe.tap()
        XCTAssertTrue(waitUntil(120) {
            self.value(app, "bikeSafe") == "1" && self.value(app, "loading") == "0"
                && self.value(app, "seconds") == "900"
        }, "the profile did not replan the ride: \(debugText("route-debug") ?? "none")")
        let safeSeconds = Int(value(app, "seconds") ?? "") ?? -1
        report("bike_safe_seconds", safeSeconds)
        report("bike_safe_meters", value(app, "meters") ?? "?")
        report("bike_safe_profile", value(app, "bikeSafe") ?? "?")
        report("bike_mode_after_profile", value(app, "mode") ?? "?")
        XCTAssertEqual(value(app, "mode"), "BICYCLE", "the profile changed the travel mode")
        XCTAssertNotEqual(fastSeconds, safeSeconds, "the profile did not change the route")
        XCTAssertTrue(element("route-bike-unsupported", in: app).exists, "the unsupported knobs are not named")
        sleep(3)
        shot("bike-profile-route")
    }

    private func openSettings(_ app: XCUIApplication) {
        XCTAssertTrue(waitUntil(10) { app.buttons["map-overflow"].isHittable }, "the map overflow stayed covered")
        app.buttons["map-overflow"].tap()
        XCTAssertTrue(app.buttons["settings-menu-item"].waitForExistence(timeout: 5))
        app.buttons["settings-menu-item"].tap()
        XCTAssertTrue(app.staticTexts["settings-debug"].waitForExistence(timeout: 15), "settings did not open")
    }

    private func openDirections(_ app: XCUIApplication, query: String) {
        let searchField = app.textFields["search-field"]
        sleep(4)
        focus(searchField)
        searchField.typeText("\(query)\n")
        let rows = app.buttons.matching(identifier: "search-result")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 60), "no result row for \(query)")
        sleep(3)
        rows.firstMatch.tap()
        let directions = app.buttons["place-directions"]
        XCTAssertTrue(directions.waitForExistence(timeout: 15), "no Directions button")
        directions.tap()
        XCTAssertTrue(app.otherElements["route-sheet"].waitForExistence(timeout: 10)
            || app.buttons["route-mode-DRIVE"].waitForExistence(timeout: 5), "no route chooser")
    }

    /// The Form is lazy: the bike section below Privacy is not in the tree until it is scrolled to.
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
    }

    private func expandRoute(_ app: XCUIApplication) {
        if element("route-expanded", in: app).exists { return }
        let toggle = app.buttons["route-expand"]
        guard toggle.waitForExistence(timeout: 5) else { return }
        toggle.tap()
        XCTAssertTrue(waitUntil(10) { self.element("route-expanded", in: app).exists },
                      "the route sheet did not expand")
    }

    /// The expanded chooser has its own scroll view; the profile step sits above the route rows
    /// and can start behind the fixed Start and Steps actions.
    private func scrollRouteTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<4 {
            if element.exists && element.isHittable { return }
            let scrollView = app.scrollViews["route-scroll"]
            if scrollView.exists {
                scrollView.swipeUp()
            } else {
                app.otherElements["route-sheet"].swipeUp()
            }
        }
    }

    private func setSwitch(_ toggle: XCUIElement, on: Bool) {
        let target = on ? "1" : "0"
        if String(describing: toggle.value ?? "") == target { return }
        toggle.tap()
        if !waitUntil(5, { String(describing: toggle.value ?? "") == target }) {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)).tap()
        }
        XCTAssertTrue(waitUntil(5, { String(describing: toggle.value ?? "") == target }),
                      "switch did not reach \(target): \(String(describing: toggle.value ?? "missing"))")
    }

    /// Form rows and combined accessibility labels surface as different element types; match any.
    private func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func value(_ app: XCUIApplication, _ key: String) -> String? {
        guard let line = debugText("route-debug") else { return nil }
        for part in line.split(separator: " ") where part.hasPrefix("\(key)=") {
            return String(part.dropFirst(key.count + 1))
        }
        return nil
    }

    private func focus(_ field: XCUIElement) {
        for _ in 0..<3 {
            field.tap()
            if app.keyboards.count > 0 { return }
            usleep(300_000)
        }
    }
}
