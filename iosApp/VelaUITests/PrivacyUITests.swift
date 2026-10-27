import XCTest

/// PR-1 on the simulator: the Privacy controls, the Google session rotation, and a NoGoogle
/// search that leaves the Debug Google request counter at zero.
final class PrivacyUITests: VelaUITestCase {
    func testPrivacyControlsAndSessionRotation() {
        let app = launch(arguments: ["-VelaResetSettings", "YES"])
        defer { resetAfterTest() }
        openSettings(app)
        let telemetry = scrollTo("settings-telemetry", in: app)
        XCTAssertTrue(telemetry.waitForExistence(timeout: 10), "privacy section is missing")
        shot("privacy")

        scrollTo("settings-privacy-page", in: app)
        app.buttons["settings-privacy-page"].tap()
        XCTAssertTrue(app.otherElements["privacy-screen"].waitForExistence(timeout: 10)
            || app.staticTexts["What reaches Google"].waitForExistence(timeout: 10),
            "privacy page did not open")
        shot("privacy-page")
        app.buttons["privacy-done"].tap()

        let mode = app.descendants(matching: .any)["settings-session-mode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 5), "session mode is missing")
        mode.tap()
        let day = app.buttons["Start a new one every day"].firstMatch
        if day.waitForExistence(timeout: 5) { day.tap() } else { app.staticTexts["Start a new one every day"].tap() }
        XCTAssertTrue(waitUntil(10) { String(describing: mode.value ?? "") == "day" },
                      "rotation mode did not persist: \(String(describing: mode.value ?? "none"))")

        let start = app.buttons["settings-session-new"]
        XCTAssertTrue(start.exists, "start-new-session button is missing")
        start.tap()
        XCTAssertTrue(app.staticTexts["settings-session-started"].waitForExistence(timeout: 5),
                      "the new session start was not shown")

        let current = String(describing: telemetry.value ?? "")
        if current != "1" { telemetry.tap() }
        if !waitUntil(2, { String(describing: telemetry.value ?? "") == "1" }) {
            // The Switch's accessible action can land on the label; the knob always toggles it.
            telemetry.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        XCTAssertTrue(waitUntil(10) { String(describing: telemetry.value ?? "") == "1" },
                      "telemetry switch did not change: \(String(describing: telemetry.value ?? "none"))")
        shot("privacy-rotation")
        report("privacy_rotation", "day")
        report("privacy_telemetry", "1")
    }

    func testNoGoogleSearchSendsNothingToGoogle() {
        let app = launch(arguments: ["-VelaResetSettings", "YES"])
        defer { resetAfterTest() }
        openSettings(app)
        setGoogleSwitch(true, in: app)
        app.buttons["settings-done"].tap()

        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("coffee\n")
        // The local-only path answers with a message, not Google rows; either way it settles.
        _ = waitUntil(20) {
            app.staticTexts["search-message"].exists || app.buttons.matching(identifier: "search-result").count > 0
        }
        app.buttons["map-overflow"].tap()
        XCTAssertTrue(app.buttons["settings-menu-item"].waitForExistence(timeout: 5))
        app.buttons["settings-menu-item"].tap()
        XCTAssertTrue(app.staticTexts["settings-debug"].waitForExistence(timeout: 10))
        let line = debugText("settings-debug") ?? ""
        let sent = value(line, "greq")
        let blocked = value(line, "gblocked")
        report("privacy_no_google_sent", sent)
        report("privacy_no_google_blocked", blocked)
        shot("privacy-no-google")
        XCTAssertEqual(sent, 0, "a Google request left the phone with NoGoogle on: \(line)")
        XCTAssertEqual(blocked, 0, "a code path still tried Google with NoGoogle on: \(line)")
    }

    func testNoGoogleDirectionsAndTransitSendNothingToGoogle() {
        let first = launch(arguments: ["-VelaResetSettings", "YES"])
        defer { resetAfterTest() }
        openSettings(first)
        setGoogleSwitch(true, in: first)
        first.buttons["settings-done"].tap()
        first.terminate()

        let link = "https://www.google.com/maps/dir/?api=1" +
            "&origin=38.5815719,-121.4943996&destination=38.5449065,-121.7405167&travelmode=driving"
        let app = launch(camera: "davis", arguments: ["-VelaOpenURL", link])
        XCTAssertTrue(app.otherElements["route-sheet"].waitForExistence(timeout: 90)
            || app.buttons["route-mode-DRIVE"].waitForExistence(timeout: 10),
            "the directions link did not open the chooser")
        app.buttons["route-mode-DRIVE"].tap()
        _ = waitUntil(45) { self.value(self.debugText("route-debug") ?? "", "loading") == 0 }
        app.buttons["route-mode-TRANSIT"].tap()
        _ = waitUntil(45) { self.value(self.debugText("route-debug") ?? "", "loading") == 0 }
        if app.buttons["route-close"].exists { app.buttons["route-close"].tap() }

        openSettings(app)
        XCTAssertTrue(app.staticTexts["settings-debug"].waitForExistence(timeout: 10))
        let line = debugText("settings-debug") ?? ""
        let sent = value(line, "greq")
        let blocked = value(line, "gblocked")
        report("privacy_no_google_routes_sent", sent)
        report("privacy_no_google_routes_blocked", blocked)
        XCTAssertEqual(sent, 0, "a Google request left the phone for directions or transit: \(line)")
    }

    private func openSettings(_ app: XCUIApplication) {
        app.buttons["map-overflow"].tap()
        XCTAssertTrue(app.buttons["settings-menu-item"].waitForExistence(timeout: 5))
        app.buttons["settings-menu-item"].tap()
        XCTAssertTrue(app.staticTexts["settings-debug"].waitForExistence(timeout: 15), "settings did not open")
    }

    /// The Privacy section is below the fold on an iPhone 17 at the default text size.
    @discardableResult
    private func scrollTo(_ id: String, in app: XCUIApplication) -> XCUIElement {
        let element = app.descendants(matching: .any)[id]
        for _ in 0..<5 where !element.isHittable {
            if app.scrollViews.firstMatch.exists { app.scrollViews.firstMatch.swipeUp() } else { app.swipeUp() }
        }
        return element
    }

    private func setGoogleSwitch(_ on: Bool, in app: XCUIApplication) {
        let toggle = scrollTo("settings-no-google", in: app)
        let target = on ? "1" : "0"
        if String(describing: toggle.value ?? "") != target { toggle.tap() }
        if !waitUntil(2, { String(describing: toggle.value ?? "") == target }),
           String(describing: toggle.value ?? "") != target {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)).tap()
        }
        XCTAssertTrue(waitUntil(10) { String(describing: toggle.value ?? "") == target },
                      "Google switch did not change: \(String(describing: toggle.value ?? "none"))")
    }

    private func value(_ line: String, _ key: String) -> Int {
        for part in line.split(separator: " ") {
            let pair = part.split(separator: "=", maxSplits: 1)
            if pair.count == 2, pair[0] == key, let number = Int(pair[1]) { return number }
        }
        return -1
    }

    private func resetAfterTest() {
        let clean = XCUIApplication()
        clean.launchArguments = ["-VelaResetSettings", "YES", "-VelaDeterministic", "YES"]
        clean.launch()
        clean.terminate()
    }
}
