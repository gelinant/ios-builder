import XCTest

/// VO-1: the downloaded Piper voice in Settings, and guidance really using it. scripts/ios/ci-ipa.sh
/// injects `en_US-hfc_female-medium` into the Debug app's bundle as `VoiceFixture`; release builds
/// have no model and keep AVSpeechSynthesizer.
final class VoiceUITests: VelaUITestCase {
    private let modelId = "en_US-hfc_female-medium"

    func testVoiceSettingsShowInstalledModel() {
        let app = launch(camera: "sf", arguments: ["-VelaVoiceFixture", "YES"])
        openSettings()
        let libraryButton = app.buttons["voice-library"]
        for _ in 0..<12 where !libraryButton.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(libraryButton.waitForExistence(timeout: 10), "no voice library row")
        XCTAssertTrue(
            app.staticTexts["voice-in-use-\(modelId)"].waitForExistence(timeout: 10),
            "installed model is not in use: \(debugText("voice-debug") ?? "none")")
        let debug = debugText("voice-debug") ?? ""
        XCTAssertTrue(debug.contains("engine=neural"), "wrong engine: \(debug)")
        report("voice_engine", debug.replacingOccurrences(of: " ", with: "_"))
        report("voice_installed", app.staticTexts["voice-in-use-\(modelId)"].exists ? 1 : 0)
        shot("voice-settings")

        libraryButton.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["voice-library-list"].waitForExistence(timeout: 10),
            "voice library did not open")
        XCTAssertTrue(app.staticTexts["HFC Female"].waitForExistence(timeout: 10), "catalog row missing")
        shot("voice-library")
        app.buttons["voice-library-done"].tap()
        XCTAssertTrue(app.buttons["voice-test"].waitForExistence(timeout: 10), "no Test voice button")
    }

    func testSystemVoiceWhenNeuralIsDisabled() {
        launch(camera: "sf", arguments: ["-VelaVoiceFixture", "YES", "-VelaVoiceDisableNeural", "YES"])
        openSettings()
        let libraryButton = app.buttons["voice-library"]
        for _ in 0..<12 where !libraryButton.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(libraryButton.waitForExistence(timeout: 10), "no voice library row")
        let debug = debugText("voice-debug") ?? ""
        XCTAssertTrue(debug.contains("engine=system"), "wrong fallback: \(debug)")
        report("voice_fallback", debug.replacingOccurrences(of: " ", with: "_"))
        shot("voice-fallback")
    }

    func testNeuralVoiceGuidanceAndFallbackMarker() {
        let app = launch(camera: "sf", followUser: true, arguments: ["-VelaVoiceFixture", "YES"])
        startCoffeeRoute()
        app.buttons["route-start"].tap()
        XCTAssertTrue(app.otherElements["nav-banner"].waitForExistence(timeout: 20), "no nav banner")
        XCTAssertTrue(waitUntil(40) {
            (self.debugText("nav-voice-debug") ?? "").contains("engine=neural")
        }, "guidance did not use the neural voice: \(debugText("nav-voice-debug") ?? "none")")
        let line = debugText("nav-voice-debug") ?? ""
        report("voice_guidance", line.replacingOccurrences(of: " ", with: "_"))
        shot("voice-guidance")
        app.buttons["nav-end"].tap()
        let confirm = app.buttons["nav-end-confirm"].firstMatch
        if confirm.waitForExistence(timeout: 5) { confirm.tap() }
    }

    private func openSettings() {
        let overflow = app.buttons["map-overflow"]
        XCTAssertTrue(overflow.waitForExistence(timeout: 20), "no map overflow menu")
        overflow.tap()
        let item = app.buttons["settings-menu-item"]
        XCTAssertTrue(item.waitForExistence(timeout: 10), "no settings item")
        item.tap()
        XCTAssertTrue(app.staticTexts["settings-debug"].waitForExistence(timeout: 20),
                      "settings did not open")
    }

    private func startCoffeeRoute() {
        let field = app.textFields["search-field"]
        sleep(4)
        field.tap()
        field.typeText("coffee\n")
        let rows = app.buttons.matching(identifier: "search-result")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 60), "no coffee result")
        sleep(3)
        rows.firstMatch.tap()
        let directions = app.buttons["place-directions"]
        XCTAssertTrue(directions.waitForExistence(timeout: 15), "no Directions button")
        directions.tap()
        if routeValue("mode") != "DRIVE" {
            app.buttons["route-mode-DRIVE"].tap()
        }
        XCTAssertTrue(waitUntil(90) {
            self.routeValue("loading") == "0" && (Int(self.routeValue("routes") ?? "") ?? 0) > 0
        }, "no driving route")
    }

    private func routeValue(_ key: String) -> String? {
        guard let line = debugText("route-debug") else { return nil }
        for part in line.split(separator: " ") where part.hasPrefix("\(key)=") {
            return String(part.dropFirst(key.count + 1))
        }
        return nil
    }

    // MARK: - VO-2 voice search

    /// The recognized text is injected (the CI simulator has no usable microphone), then everything
    /// after it is real: the common intent parser, the ordinary search store, the results panel.
    func testVoiceSearchInjectedQueryRunsTheSearch() {
        let app = launch(camera: "sf", followUser: true,
                         arguments: ["-VelaVoiceQuery", "coffee"])
        let mic = app.buttons["voice-search"]
        XCTAssertTrue(mic.waitForExistence(timeout: 20), "no voice-search button")
        mic.tap()
        let rows = app.buttons.matching(identifier: "search-result")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 90),
                      "voice search did not run a search")
        let query = (app.textFields["search-field"].value as? String) ?? ""
        XCTAssertTrue(query.lowercased().contains("coffee"),
                      "the recognized text did not reach the search field: \(query)")
        report("voice_search_results", rows.count)
        report("voice_search_query", query.replacingOccurrences(of: " ", with: "_"))
        sleep(3)
        shot("voice-search")
    }

    /// "navigate to coffee": the same injected text, the navigate intent, the ordinary search, then
    /// the existing route chooser on the first hit. No second search path is exercised.
    func testVoiceSearchNavigateIntentOpensTheChooser() {
        let app = launch(camera: "sf", followUser: true,
                         arguments: ["-VelaVoiceQuery", "navigate to coffee"])
        let mic = app.buttons["voice-search"]
        XCTAssertTrue(mic.waitForExistence(timeout: 20), "no voice-search button")
        mic.tap()
        let chooser = app.otherElements["route-sheet"]
        let drive = app.buttons["route-mode-DRIVE"]
        XCTAssertTrue(waitUntil(120) { chooser.exists || drive.exists },
                      "the navigate intent did not open the route chooser")
        let destination = app.staticTexts["route-destination"].exists
            ? app.staticTexts["route-destination"].label : "?"
        report("voice_intent_chooser", 1)
        report("voice_intent_destination", destination.replacingOccurrences(of: " ", with: "_"))
        sleep(2)
        shot("voice-search-intent")
        if app.buttons["route-close"].exists { app.buttons["route-close"].tap() }
    }
}
