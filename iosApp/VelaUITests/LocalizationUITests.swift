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
