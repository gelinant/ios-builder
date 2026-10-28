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

    func testConsentAndFullPrivacyPage() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-VelaStartCamera", "sf", "-VelaDeterministic", "YES",
            "-VelaResetSettings", "YES", "-VelaFirstRunConsent", "YES",
        ]
        app.launch()
        defer { resetAfterTest() }

        let consent = app.staticTexts["consent-title"]
        XCTAssertTrue(consent.waitForExistence(timeout: 30), "the first-run Google question did not appear")
        shot("privacy-consent")

        // The customize page offers the switches this app really has.
        let customize = scrollTo("consent-customize", in: app)
        XCTAssertTrue(customize.waitForExistence(timeout: 10), "no customize button")
        customize.tap()
        let lookup = app.switches["consent-lookup"]
        XCTAssertTrue(lookup.waitForExistence(timeout: 10), "no tapped-place switch on the consent page")
        XCTAssertEqual(String(describing: lookup.value ?? ""), "1", "lookup starts on")
        lookup.tap()
        if !waitUntil(2, { String(describing: lookup.value ?? "") == "0" }) {
            // The Switch's accessible action can land on the label; the knob always toggles it.
            lookup.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        XCTAssertTrue(waitUntil(5) { String(describing: lookup.value ?? "") == "0" },
                      "the consent lookup switch did not change")
        let usesDone = scrollTo("consent-uses-done", in: app)
        XCTAssertTrue(usesDone.waitForExistence(timeout: 10), "no continue button on the customize page")
        usesDone.tap()

        let cont = scrollTo("consent-continue", in: app)
        XCTAssertTrue(cont.waitForExistence(timeout: 10), "no continue button on the question")
        cont.tap()
        XCTAssertTrue(waitUntil(10) { !consent.exists }, "the first-run question did not close")
        XCTAssertTrue(app.textFields["search-field"].waitForExistence(timeout: 30),
                      "the map did not appear after the answer")

        openSettings(app)
        scrollTo("settings-privacy-page", in: app)
        app.buttons["settings-privacy-page"].tap()
        XCTAssertTrue(app.staticTexts["What reaches Google"].waitForExistence(timeout: 10),
                      "the privacy page did not open")
        XCTAssertTrue(app.staticTexts["What stays on this phone"].exists, "no local-data section")

        // The consent page's answer reached the same holder the Settings screen shows.
        let pageLookup = scrollTo("privacy-lookup", in: app)
        XCTAssertTrue(pageLookup.waitForExistence(timeout: 10), "no tapped-place switch on the page")
        XCTAssertEqual(String(describing: pageLookup.value ?? ""), "0",
                       "the consent answer was not kept: \(String(describing: pageLookup.value ?? "none"))")
        shot("privacy-page")
        report("privacy_consent_lookup", String(describing: pageLookup.value ?? "none"))

        let total = scrollTo("privacy-counter-total", in: app)
        XCTAssertTrue(total.waitForExistence(timeout: 10), "no request counter")
        let clear = scrollTo("privacy-clear-history", in: app)
        XCTAssertTrue(clear.waitForExistence(timeout: 10), "no clear-history action")
        XCTAssertTrue(app.staticTexts["Delete what is stored"].exists, "no delete section")
        let policy = scrollTo("privacy-link", in: app)
        XCTAssertTrue(policy.waitForExistence(timeout: 10), "no limits section")
        app.buttons["privacy-done"].tap()
        app.buttons["settings-done"].tap()
    }

    func testRequestCounterAndClearHistory() {
        var app = launch(arguments: ["-VelaResetSettings", "YES"])
        defer { resetAfterTest() }

        // A real search: its Google requests are what the counter must show.
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("coffee\n")
        let results = app.buttons.matching(identifier: "search-result")
        XCTAssertTrue(results.firstMatch.waitForExistence(timeout: 60), "no search result")
        results.firstMatch.tap()
        let placeName = app.staticTexts["place-name"]
        XCTAssertTrue(placeName.waitForExistence(timeout: 15), "no place sheet")
        let name = placeName.label
        let save = app.buttons["place-save"]
        XCTAssertTrue(save.waitForExistence(timeout: 10), "no Save button")
        save.tap()
        app.buttons["saved-open"].tap()
        XCTAssertTrue(app.buttons[name].waitForExistence(timeout: 10), "the place was not saved")
        app.buttons["saved-close"].tap()
        if app.buttons["place-close"].exists { app.buttons["place-close"].tap() }

        openSettings(app)
        scrollTo("settings-privacy-page", in: app)
        app.buttons["settings-privacy-page"].tap()
        let total = scrollTo("privacy-counter-total", in: app)
        XCTAssertTrue(total.waitForExistence(timeout: 10), "no request counter")
        let before = firstNumber(total.label)
        XCTAssertGreaterThan(before, 0, "the counter did not see the search: \(total.label)")
        shot("privacy-counter")
        report("privacy_counter_today", before)

        // Survives a relaunch: no reset, so the saved days come back.
        app.buttons["privacy-done"].tap()
        app.buttons["settings-done"].tap()
        app.terminate()
        app = launch()
        openSettings(app)
        scrollTo("settings-privacy-page", in: app)
        app.buttons["settings-privacy-page"].tap()
        let restored = scrollTo("privacy-counter-total", in: app)
        XCTAssertTrue(restored.waitForExistence(timeout: 10), "no request counter after relaunch")
        let after = firstNumber(restored.label)
        XCTAssertGreaterThanOrEqual(after, before,
                                    "the count was lost across relaunch: \(restored.label)")
        report("privacy_counter_after_relaunch", after)

        // Clearing the count must leave the saved place alone.
        let clearCount = scrollTo("privacy-counter-clear", in: app)
        XCTAssertTrue(clearCount.waitForExistence(timeout: 10), "no counter clear action")
        clearCount.tap()
        XCTAssertTrue(app.staticTexts["privacy-counter-cleared"].waitForExistence(timeout: 5),
                      "the clear action did not confirm")
        XCTAssertEqual(firstNumber(app.staticTexts["privacy-counter-total"].label), 0,
                       "the counter did not go to zero")
        shot("privacy-counter-cleared")
        app.buttons["privacy-done"].tap()
        XCTAssertTrue(waitUntil(10) { (self.debugText("settings-debug") ?? "").contains("greq=0") },
                      "the Debug line still counts requests after the clear: \(self.debugText("settings-debug") ?? "none")")
        app.buttons["settings-done"].tap()
        app.buttons["saved-open"].tap()
        XCTAssertTrue(app.buttons[name].waitForExistence(timeout: 10),
                      "clearing the request count removed a saved place")
        app.buttons["saved-close"].tap()
        if app.buttons["place-close"].exists { app.buttons["place-close"].tap() }

        // Clear history wipes recents, parking and trips, and still keeps saved places.
        openSettings(app)
        scrollTo("settings-privacy-page", in: app)
        app.buttons["settings-privacy-page"].tap()
        let clear = scrollTo("privacy-clear-history", in: app)
        XCTAssertTrue(clear.waitForExistence(timeout: 10), "no clear-history action")
        clear.tap()
        let confirm = app.buttons["Clear"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "no clear-history confirmation")
        confirm.tap()
        XCTAssertTrue(app.staticTexts["privacy-history-cleared"].waitForExistence(timeout: 5),
                      "history was not cleared")
        shot("privacy-history-cleared")
        app.buttons["privacy-done"].tap()
        app.buttons["settings-done"].tap()

        app.buttons["saved-open"].tap()
        XCTAssertTrue(app.buttons[name].waitForExistence(timeout: 10),
                      "clearing history removed a saved place")
        app.buttons["saved-close"].tap()
        if app.buttons["place-close"].exists { app.buttons["place-close"].tap() }

        let searchField = app.textFields["search-field"]
        searchField.tap()
        XCTAssertTrue(waitUntil(5) { app.buttons.matching(identifier: "search-recent").count == 0 },
                      "recent searches or places survived Clear history")
        report("privacy_history_recents", app.buttons.matching(identifier: "search-recent").count)
    }

    private func firstNumber(_ text: String) -> Int {
        let digits = text.split(whereSeparator: { !$0.isNumber })
        return digits.first.flatMap { Int($0) } ?? -1
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
