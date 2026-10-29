import CoreGraphics
import XCTest

final class LocalizationUITests: VelaUITestCase {
    func testFrenchLabelsWithoutChangingSimulatorLanguage() {
        let app = launch(arguments: ["-VelaResetSettings", "YES", "-VelaLanguage", "fr"])
        let field = app.textFields["search-field"]
        let placeholder = field.placeholderValue as? String
        XCTAssertEqual(placeholder, "Rechercher")
        report("l10n_fr_placeholder", placeholder ?? "missing")

        openSettings(app)
        assertLabel("Paramètres", report: "l10n_fr_title")
        assertLabel("Langue", report: "l10n_fr_language")
        assertLabel("Unités", report: "l10n_fr_units")
        assertLabel("Utiliser Vela sans Google", report: "l10n_fr_no_google")
        shot("settings-fr")
    }

    func testGermanSettingsLayout() {
        let app = launch(arguments: ["-VelaResetSettings", "YES", "-VelaLanguage", "de"])
        XCTAssertEqual(app.textFields["search-field"].placeholderValue as? String, "Suchen")
        report("l10n_de_placeholder", "Suchen")
        openSettings(app)
        assertLabel("Einstellungen", report: "l10n_de_title")
        assertLabel("Sprache", report: "l10n_de_language")
        assertLabel("Vela ohne Google nutzen", report: "l10n_de_no_google")
        shot("settings-de")
    }

    func testSettingsPersistAcrossRelaunch() {
        let app = launch(arguments: ["-VelaResetSettings", "YES"])
        defer { resetAfterTest() }
        openSettings(app)
        choose("settings-units", option: "Imperial (miles, feet)", in: app)
        choose("settings-clock", option: "24-hour (16:35)", in: app)
        setGoogleSwitch(true, in: app)
        choose("settings-language", option: "Français", in: app)
        XCTAssertTrue(waitUntil(10) {
            let line = self.debugText("settings-debug") ?? ""
            return line.contains("language=fr") && line.contains("units=imperial")
                && line.contains("clock=24") && line.contains("google=1")
        }, "settings did not apply: \(self.debugText("settings-debug") ?? "none")")

        app.terminate()
        let relaunched = launch()
        openSettings(relaunched)
        let line = debugText("settings-debug") ?? "missing"
        report("settings_persistence", line.replacingOccurrences(of: " ", with: ","))
        XCTAssertTrue(line.contains("language=fr"), line)
        XCTAssertTrue(line.contains("units=imperial"), line)
        XCTAssertTrue(line.contains("clock=24"), line)
        XCTAssertTrue(line.contains("google=1"), line)
        relaunched.buttons["settings-done"].tap()
        XCTAssertEqual(relaunched.textFields["search-field"].placeholderValue as? String, "Rechercher")
    }


    func testFrenchTransitWorldAndSearchSurfaces() {
        // GO, on the recorded Paris ride: no network and no planner.
        var app = XCUIApplication()
        app.launchArguments = [
            "-VelaStartCamera", "sf",
            "-VelaDeterministic", "YES",
            "-VelaLanguage", "fr",
            "-VelaTransitGoTest", "YES",
            "-VelaTransitGoScene", "ride",
        ]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["transit-go-screen"].waitForExistence(timeout: 60),
                      "the GO screen was not presented")
        XCTAssertTrue(app.staticTexts["Départs"].exists, "Departures stayed English")
        XCTAssertTrue(app.staticTexts["Partir plus tard"].exists, "Leave later stayed English")
        XCTAssertTrue(app.staticTexts["Tout le voyage"].exists, "Whole trip stayed English")
        XCTAssertTrue(app.staticTexts["Fin"].exists, "End stayed English")
        XCTAssertTrue(app.buttons["transit-go-departures"].label.hasPrefix("Prochains départs"))
        report("l10n_fr_go_departures", app.buttons["transit-go-departures"].label)
        XCTAssertFalse(app.staticTexts["Departures"].exists, "an English GO label is still visible")
        shot("transit-go-fr")
        app.terminate()

        // The line sheet, on the recorded K board.
        app = XCUIApplication()
        app.launchArguments = [
            "-VelaStartCamera", "sf",
            "-VelaDeterministic", "YES",
            "-VelaLanguage", "fr",
            "-VelaTransitFixture", "YES",
            "-VelaTransitLineFixture", "YES",
        ]
        app.launch()
        XCTAssertTrue(app.otherElements["transit-line-sheet"].waitForExistence(timeout: 60),
                      "the line sheet did not open")
        XCTAssertEqual(app.buttons["transit-line-close"].label, "Fermer")
        XCTAssertEqual(app.buttons["transit-line-refresh"].label, "Actualiser")
        report("l10n_fr_line_close", app.buttons["transit-line-close"].label)
        shot("transit-line-fr")
        app.terminate()

        // World layers, then the unified search field.
        app = launch(arguments: ["-VelaResetSettings", "YES", "-VelaLanguage", "fr"])
        let layers = app.buttons["layers-button"]
        XCTAssertTrue(layers.waitForExistence(timeout: 30), "no layers button")
        layers.tap()
        XCTAssertTrue(app.buttons["layer-painted"].waitForExistence(timeout: 10), "no layers sheet")
        let aviation = app.buttons["world-layer-aviation"]
        for _ in 0..<8 where !aviation.exists {
            app.swipeUp()
        }
        XCTAssertTrue(aviation.exists, "no World layers section")
        XCTAssertTrue(aviation.label.contains("Avions"), "world layer title stayed English: \(aviation.label)")
        XCTAssertFalse(aviation.label.contains("Unavailable"), "world layer state stayed English: \(aviation.label)")
        XCTAssertFalse(aviation.label.contains("no data"), "world layer state stayed English: \(aviation.label)")
        report("l10n_fr_world_aviation", aviation.label.replacingOccurrences(of: " ", with: "_"))
        shot("world-layers-fr")
        app.buttons["layers-close"].tap()

        let field = app.textFields["search-field"]
        field.tap()
        field.typeText("coffee")
        let everywhere = app.descendants(matching: .any)["unified-search-everywhere"]
        XCTAssertTrue(everywhere.waitForExistence(timeout: 20), "no search-everywhere row")
        XCTAssertTrue(everywhere.label.contains("Recherch"), "unified search stayed English: \(everywhere.label)")
        report("l10n_fr_search_everywhere", everywhere.label.replacingOccurrences(of: " ", with: "_"))
        shot("unified-search-fr")
    }

    private func openSettings(_ app: XCUIApplication) {
        app.buttons["map-overflow"].tap()
        XCTAssertTrue(app.buttons["settings-menu-item"].waitForExistence(timeout: 5))
        app.buttons["settings-menu-item"].tap()
        XCTAssertTrue(app.staticTexts["settings-debug"].waitForExistence(timeout: 15), "settings did not open")
    }

    private func setGoogleSwitch(_ on: Bool, in app: XCUIApplication) {
        let toggle = app.switches["settings-no-google"]
        let target = on ? "1" : "0"
        report("settings_google_before", String(describing: toggle.value ?? "missing"))
        if String(describing: toggle.value ?? "") != target { toggle.tap() }
        let changed = waitUntil(2) { self.debugText("settings-debug")?.contains("google=\(target)") == true }
        if !changed && String(describing: toggle.value ?? "") != target {
            // Fall back to the knob when the switch accessibility action does not reach SwiftUI.
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)).tap()
        }
        report("settings_google_after", String(describing: toggle.value ?? "missing"))
        let line = debugText("settings-debug") ?? "missing"
        report("settings_google_debug", line.replacingOccurrences(of: " ", with: ","))
        XCTAssertTrue(waitUntil(10) { self.debugText("settings-debug")?.contains("google=\(target)") == true },
                      "Google switch did not change: \(line)")
    }

    private func choose(_ id: String, option: String, in app: XCUIApplication) {
        let picker = app.descendants(matching: .any)[id]
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

    private func assertLabel(_ label: String, report key: String) {
        XCTAssertTrue(app.staticTexts[label].waitForExistence(timeout: 10), "missing label \(label)")
        report(key, label.replacingOccurrences(of: " ", with: "_"))
    }

    private func resetAfterTest() {
        let clean = XCUIApplication()
        clean.launchArguments = ["-VelaResetSettings", "YES", "-VelaDeterministic", "YES"]
        clean.launch()
        clean.terminate()
    }
}
