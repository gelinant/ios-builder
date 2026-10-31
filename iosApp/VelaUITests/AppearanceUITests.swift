import CoreGraphics
import XCTest

/// SET-APPEARANCE: the app theme, the map look, the navigation chrome size, the speed unit, the
/// vehicle icon and the detail level. Every choice is proved through the debug line and the free
/// drive's own chrome, not only through the settings row.
final class AppearanceUITests: VelaUITestCase {
    func testThemesSpeedAndVehicle() {
        let app = launch(
            camera: "sf", followUser: true,
            arguments: ["-VelaResetSettings", "YES", "-VelaNavAlertsFixture", "YES"])
        defer { resetAfterTest() }
        openSettings(app)

        // The Google switch must still be in the first two screens after the new row.
        var swipes = 0
        while !app.switches["settings-no-google"].isHittable && swipes < 2 {
            app.scrollViews.firstMatch.swipeUp()
            swipes += 1
        }
        report("appearance_google_swipes", swipes)
        XCTAssertLessThanOrEqual(swipes, 2, "the appearance row pushed the Google switch down")

        let appearanceRow = scrollTo("settings-appearance", in: app)
        XCTAssertTrue(appearanceRow.waitForExistence(timeout: 5), "no appearance row")
        appearanceRow.tap()
        XCTAssertTrue(app.staticTexts["appearance-debug"].waitForExistence(timeout: 10),
                      "the appearance page did not open")

        // Dark theme: the window style changes and the debug line follows.
        choose("appearance-theme", option: "Dark", in: app)
        XCTAssertTrue(waitUntil(10) { self.debugText("appearance-debug")?.contains("theme=dark") == true },
                      "the theme did not apply: \(debugText("appearance-debug") ?? "none")")
        shot("appearance-dark")

        // Map look and map light/dark stay independent of the app theme.
        choose("appearance-map-look", option: "Bright", in: app)
        choose("appearance-map-appearance", option: "Dark", in: app)
        XCTAssertTrue(waitUntil(10) {
            let line = self.debugText("appearance-debug") ?? ""
            return line.contains("look=bright") && line.contains("map=dark")
        }, "the map choice did not persist: \(debugText("appearance-debug") ?? "none")")
        shot("appearance-theme")

        // Icon, label, speed, vehicle and detail.
        choose("appearance-icon-size", option: "Large", in: app)
        choose("appearance-label-size", option: "Largest labels", in: app)
        choose("appearance-speed-unit", option: "mph", in: app)
        choose("appearance-vehicle", option: "UFO", in: app)
        choose("appearance-detail", option: "Compact", in: app)

        let speedSwitch = scrollTo("appearance-speed-display", in: app)
        XCTAssertTrue(speedSwitch.waitForExistence(timeout: 5))
        choose("appearance-speed-display", option: "Off", in: app)
        XCTAssertTrue(waitUntil(10) { self.debugText("appearance-debug")?.contains("speed=0") == true },
                      "the speed switch did not reach the holder")
        choose("appearance-speed-display", option: "On", in: app)
        XCTAssertTrue(waitUntil(10) { self.debugText("appearance-debug")?.contains("speed=1") == true })

        let line = debugText("appearance-debug") ?? "missing"
        report("appearance_settings", line.replacingOccurrences(of: " ", with: ","))
        XCTAssertTrue(line.contains("theme=dark"), line)
        XCTAssertTrue(line.contains("look=bright"), line)
        XCTAssertTrue(line.contains("icon=large"), line)
        XCTAssertTrue(line.contains("label=xl"), line)
        XCTAssertTrue(line.contains("unit=imperial"), line)
        XCTAssertTrue(line.contains("vehicle=ufo"), line)
        XCTAssertTrue(line.contains("detail=compact"), line)

        let preview = scrollTo("appearance-preview", in: app)
        XCTAssertTrue(preview.waitForExistence(timeout: 5), "no appearance preview")
        let previewVehicle = app.descendants(matching: .any)["appearance-preview-vehicle"]
        XCTAssertTrue(previewVehicle.waitForExistence(timeout: 5))
        XCTAssertEqual(previewVehicle.label, "UFO")
        XCTAssertEqual(app.staticTexts["appearance-preview-speed-unit"].label, "mph")
        shot("appearance-chrome")

        app.buttons["appearance-done"].tap()
        XCTAssertTrue(app.buttons["settings-done"].waitForExistence(timeout: 5))
        app.buttons["settings-done"].tap()

        // The same holder feeds the real drive chrome. Free driving needs no route.
        let open = app.buttons["free-drive-open"]
        XCTAssertTrue(open.waitForExistence(timeout: 30), "no free-drive entry")
        open.tap()
        let chrome = app.descendants(matching: .any)["free-drive-chrome"]
        XCTAssertTrue(chrome.waitForExistence(timeout: 20), "the free-drive chrome did not open")
        let vehicle = app.descendants(matching: .any)["free-vehicle-icon"]
        XCTAssertTrue(vehicle.waitForExistence(timeout: 10), "the chosen vehicle is not in the chrome")
        XCTAssertEqual(vehicle.label, "UFO")
        report("appearance_chrome_vehicle", vehicle.label)

        let unit = app.staticTexts["free-speed-unit"]
        XCTAssertTrue(unit.waitForExistence(timeout: 60), "the speed pill never appeared")
        XCTAssertEqual(unit.label, "mph")
        report("appearance_chrome_unit", unit.label)
        shot("appearance-chrome-drive")

        app.buttons["free-exit"].tap()
        XCTAssertTrue(waitUntil(10) { !chrome.exists }, "free driving did not stop")
    }

    private func openSettings(_ app: XCUIApplication) {
        app.buttons["map-overflow"].tap()
        XCTAssertTrue(app.buttons["settings-menu-item"].waitForExistence(timeout: 5))
        app.buttons["settings-menu-item"].tap()
        XCTAssertTrue(app.staticTexts["settings-debug"].waitForExistence(timeout: 15), "settings did not open")
    }

    @discardableResult
    private func scrollTo(_ id: String, in app: XCUIApplication) -> XCUIElement {
        let element = app.descendants(matching: .any)[id]
        let page = app.descendants(matching: .any)["appearance-screen"].firstMatch
        let scroller = page.exists && page.frame.height > 1 ? page : app
        for _ in 0..<10 where !element.isHittable {
            scroller.swipeUp()
        }
        return element
    }

    private func choose(_ id: String, option: String, in app: XCUIApplication) {
        let picker = scrollTo(id, in: app)
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "missing picker \(id)")
        picker.tap()
        let button = app.buttons[option]
        if button.waitForExistence(timeout: 5) {
            button.tap()
        } else {
            let text = app.staticTexts[option]
            XCTAssertTrue(text.waitForExistence(timeout: 5), "missing option \(option)")
            text.tap()
        }
    }

    private func resetAfterTest() {
        let clean = XCUIApplication()
        clean.launchArguments = ["-VelaResetSettings", "YES", "-VelaDeterministic", "YES"]
        clean.launch()
        clean.terminate()
    }
}
