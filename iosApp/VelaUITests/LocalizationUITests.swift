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
        assertLabel("Utiliser Vela sans Google", report: "l10n_fr_no_google")
        shot("settings-fr")
        app.buttons["settings-appearance"].tap()
        XCTAssertTrue(app.staticTexts["appearance-debug"].waitForExistence(timeout: 10),
                      "the appearance page did not open")
        assertLabel("Langue", report: "l10n_fr_language")
        assertLabel("Unités", report: "l10n_fr_units")
        shot("settings-fr-appearance")
    }

    func testGermanSettingsLayout() {
        let app = launch(arguments: ["-VelaResetSettings", "YES", "-VelaLanguage", "de"])
        XCTAssertEqual(app.textFields["search-field"].placeholderValue as? String, "Suchen")
        report("l10n_de_placeholder", "Suchen")
        openSettings(app)
        assertLabel("Einstellungen", report: "l10n_de_title")
        assertLabel("Vela ohne Google nutzen", report: "l10n_de_no_google")
        shot("settings-de")
        app.buttons["settings-appearance"].tap()
        XCTAssertTrue(app.staticTexts["appearance-debug"].waitForExistence(timeout: 10),
                      "the appearance page did not open")
        assertLabel("Sprache", report: "l10n_de_language")
        shot("settings-de-appearance")
    }

    func testSettingsPersistAcrossRelaunch() {
        let app = launch(arguments: ["-VelaResetSettings", "YES"])
        defer { resetAfterTest() }
        openSettings(app)
        setGoogleSwitch(true, in: app)
        app.buttons["settings-appearance"].tap()
        XCTAssertTrue(app.staticTexts["appearance-debug"].waitForExistence(timeout: 10),
                      "the appearance page did not open")
        choose("settings-units", option: "Imperial (miles, feet)", in: app)
        choose("settings-clock", option: "24-hour (16:35)", in: app)
        choose("settings-language", option: "Français", in: app)
        app.buttons["appearance-done"].tap()
        XCTAssertTrue(app.buttons["settings-done"].waitForExistence(timeout: 5))
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
        XCTAssertTrue(waitUntil(10) { !app.buttons["layers-close"].exists },
                      "the layers sheet did not close")

        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "no search field")
        field.tap()
        field.typeText("coffee")
        XCTAssertEqual(field.value as? String, "coffee", "the unified field did not take the query")
        // The row sits at the end of a LazyVStack; a busy query can leave it below the 320 pt
        // panel and unbuilt. Scroll the panel itself, then retry with a query that has no local
        // rows if the first one still did not build it.
        let panel = app.descendants(matching: .any)["search-suggestions"]
        XCTAssertTrue(panel.waitForExistence(timeout: 10), "no unified search panel")
        var everywhere = reveal("unified-search-everywhere", in: "search-suggestions", tries: 30)
        if !everywhere.exists {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8))
            field.typeText("zzcoffeezz")
            XCTAssertEqual(field.value as? String, "zzcoffeezz",
                           "the unified field did not take the fallback query")
            everywhere = reveal("unified-search-everywhere", in: "search-suggestions", tries: 20)
        }
        XCTAssertTrue(everywhere.exists, "no search-everywhere row")
        XCTAssertTrue(everywhere.label.contains("Recherch"), "unified search stayed English: \(everywhere.label)")
        report("l10n_fr_search_everywhere", everywhere.label.replacingOccurrences(of: " ", with: "_"))
        shot("unified-search-fr")
    }

    /// I18N-4: five labels that A11Y-W4 saw in English, each on its own French surface.
    func testFrenchPreviouslyUnlocalizedSurfaces() {
        // 1. The search results header counts rows through the catalog plural.
        var app = launch(arguments: ["-VelaResetSettings", "YES", "-VelaLanguage", "fr"])
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "no search field")
        field.tap()
        field.typeText("coffee\n")
        let row = app.buttons.matching(identifier: "search-result").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 60), "the coffee search returned no result row")
        let toggle = app.buttons["search-panel-toggle"]
        XCTAssertTrue(waitUntil(15) {
            (toggle.value as? String)?.contains("résultat") == true
        }, "the result count stayed English: \(toggle.value as? String ?? "missing")")
        report("l10n_fr_result_count", toggle.value as? String ?? "missing")
        shot("search-results-fr")
        app.terminate()

        // 2 and 3. Free drive: the simple-map switch and the exit button.
        app = launch(camera: "sf", followUser: true,
                     arguments: ["-VelaResetSettings", "YES", "-VelaLanguage", "fr",
                                 "-VelaNavAlertsFixture", "YES"])
        let open = app.buttons["free-drive-open"]
        XCTAssertTrue(open.waitForExistence(timeout: 30), "no free-drive entry")
        open.tap()
        XCTAssertTrue(app.descendants(matching: .any)["free-drive-chrome"]
            .waitForExistence(timeout: 15), "the free-drive chrome did not open")
        let simple = app.buttons["free-simple-map"]
        XCTAssertTrue(simple.exists, "no simple-map switch")
        XCTAssertEqual(simple.label, "Carte simple", "the simple-map switch stayed English")
        let exit = app.buttons["free-exit"]
        XCTAssertEqual(exit.label, "Quitter la conduite libre", "the exit button stayed English")
        report("l10n_fr_free_drive", simple.label)
        shot("free-drive-fr")
        exit.tap()
        XCTAssertTrue(waitUntil(10) { !app.descendants(matching: .any)["free-drive-chrome"].exists },
                      "the free-drive chrome stayed after exit")
        app.terminate()

        // 4. GO while the plan is still being prepared.
        app = XCUIApplication()
        app.launchArguments = [
            "-VelaStartCamera", "sf",
            "-VelaDeterministic", "YES",
            "-VelaLanguage", "fr",
            "-VelaTransitGoTest", "YES",
            "-VelaTransitGoScene", "prepare",
        ]
        app.launch()
        let preparing = app.staticTexts["transit-go-preparing"]
        XCTAssertTrue(preparing.waitForExistence(timeout: 60), "the GO loading line did not appear")
        XCTAssertEqual(preparing.label, "Préparation du guidage GO",
                       "the GO loading line stayed English")
        report("l10n_fr_go_preparing", preparing.label)
        shot("transit-go-preparing-fr")
        app.terminate()

        // 5. The cached board's ferry row.
        app = launch(camera: "sf", arguments: ["-VelaResetSettings", "YES", "-VelaLanguage", "fr",
                                               "-VelaTransitBoardOfflineTest", "YES"])
        XCTAssertTrue(app.descendants(matching: .any)["transit-board"].waitForExistence(timeout: 40),
                      "the cached board never opened")
        let ferry = app.staticTexts["Ferry"].firstMatch
        XCTAssertTrue(ferry.waitForExistence(timeout: 20), "the board lost its ferry label")
        report("l10n_fr_board_ferry", ferry.label)
        shot("transit-board-ferry-fr")
    }

    func testFrenchTerrainScreen() {
        // M-2: the relief screen's title, status line and credits come from the catalog. The
        // screen waits on the explicit ready state, never on a fixed sleep, so a slow WebGL
        // start or a late elevation tile cannot turn the run red.
        let app = launch(camera: "45.9237,6.8694,13.0",
                         arguments: ["-VelaResetSettings", "YES", "-VelaLanguage", "fr",
                                     "-VelaTerrainFixture", "YES"])
        XCTAssertTrue(app.buttons["terrain-close"].waitForExistence(timeout: 40),
                      "the terrain screen did not open")
        let ready = waitUntil(120) {
            (debugText("terrain-debug") ?? "").contains("terrain_state=ready")
        }
        let line = debugText("terrain-debug") ?? "no line"
        XCTAssertTrue(ready, "the terrain never reached ready: \(line)")
        XCTAssertFalse(line.contains("terrain_state=unavailable"),
                       "the terrain reported unavailable online: \(line)")

        let status = app.staticTexts["terrain-status"]
        XCTAssertTrue(waitUntil(20) {
            status.exists && status.label == "Relief activé, ciel et atmosphère"
        }, "the terrain status stayed English: \(status.exists ? status.label : "missing")")
        XCTAssertFalse(status.label.contains("Indisponible"),
                       "the generic unavailable label is still visible")
        XCTAssertFalse(status.label.contains("Loading"),
                       "an English terrain status is still visible")
        report("l10n_fr_terrain_state", "ready")
        report("l10n_fr_terrain_status",
               status.label.replacingOccurrences(of: " ", with: "_"))
        shot("terrain-fr")
    }

    func testFrenchSatelliteCard() {
        // G-3: the satellite card's altitude, velocity and next pass are catalog labels.
        let app = launch(camera: "0,0,1",
                         arguments: ["-VelaResetSettings", "YES", "-VelaLanguage", "fr",
                                     "-VelaSatelliteFixture", "YES"])
        openLayers(app)
        let globe = app.buttons["layer-globe"]
        reveal(globe, in: app)
        XCTAssertTrue(globe.exists, "no Globe control in the layers sheet")
        if globe.value as? String != "on" { globe.tap() }
        let toggle = app.buttons["world-layer-satellite"]
        reveal(toggle, in: app)
        XCTAssertTrue(toggle.exists, "no Satellites row")
        if toggle.value as? String != "on" { toggle.tap() }
        XCTAssertTrue(waitUntil(5) {
            app.buttons["world-layer-satellite"].value as? String == "on"
        }, "the Satellites switch did not turn on")

        app.buttons["layers-close"].tap()
        XCTAssertTrue(waitUntil(10) { !app.buttons["layers-close"].exists })
        let map = app.otherElements["map"]
        XCTAssertTrue(map.waitForExistence(timeout: 10), "no map")
        let start = map.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.50))
        let end = map.coordinate(withNormalizedOffset: CGVector(dx: 0.44, dy: 0.50))
        start.press(forDuration: 0.2, thenDragTo: end)
        sleep(4)
        openLayers(app)
        let hst = app.buttons["world-row-satellite-20580"]
        reveal(hst, in: app)
        XCTAssertTrue(hst.exists, "no HST row after the fixture refresh")
        hst.tap()
        XCTAssertTrue(app.descendants(matching: .any)["satellite-detail-card"]
            .waitForExistence(timeout: 15), "no satellite card")
        let velocity = app.staticTexts["satellite-detail-velocity"]
        XCTAssertTrue(velocity.exists && velocity.label.contains("Vitesse"),
                      "the velocity stayed English: \(velocity.exists ? velocity.label : "missing")")
        let pass = app.staticTexts["satellite-detail-pass"]
        XCTAssertTrue(pass.exists && pass.label.contains("Prochain passage"),
                      "the next pass stayed English: \(pass.exists ? pass.label : "missing")")
        report("l10n_fr_satellite_velocity",
               velocity.label.replacingOccurrences(of: " ", with: "_"))
        shot("satellite-pass-fr")
    }

    private func openSettings(_ app: XCUIApplication) {
        app.buttons["map-overflow"].tap()
        XCTAssertTrue(app.buttons["settings-menu-item"].waitForExistence(timeout: 5))
        app.buttons["settings-menu-item"].tap()
        XCTAssertTrue(app.staticTexts["settings-debug"].waitForExistence(timeout: 15), "settings did not open")
    }

    private func openLayers(_ app: XCUIApplication) {
        let button = app.buttons["layers-button"]
        XCTAssertTrue(button.waitForExistence(timeout: 30), "no layers button")
        for _ in 0..<3 {
            button.tap()
            if app.buttons["layer-painted"].waitForExistence(timeout: 10) { return }
            if app.buttons["layers-close"].exists { app.buttons["layers-close"].tap() }
        }
        XCTFail("no layers sheet")
    }

    /// Swipes the sheet until [element] exists and can be tapped.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<18 where !(element.exists && element.isHittable) {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 0.2)
        }
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
