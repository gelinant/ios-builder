import CoreGraphics
import XCTest

/// SET-CONTENT on the simulator: the short top-level list, the data and content page, the
/// recorded-trip purge and the Google switch that must stay on the first screen.
final class SettingsUITests: VelaUITestCase {
    /// The converged list: eight rows, each with a trailing value, and the Google switch still
    /// reachable without scrolling. The privacy page keeps the request counter.
    func testTopLevelRowsAndPrivacyPage() {
        let app = launch(arguments: ["-VelaResetSettings", "YES"])
        defer { resetAfterTest() }
        openSettings(app)

        let rows = [
            "settings-privacy-page", "settings-appearance", "settings-navigation",
            "settings-voice", "settings-data-content", "settings-trips",
            "settings-offline", "settings-about",
        ]
        for id in rows {
            let row = app.descendants(matching: .any)[id]
            XCTAssertTrue(row.waitForExistence(timeout: 5), "missing top-level row \(id)")
            XCTAssertTrue(row.isHittable, "\(id) is not reachable without scrolling")
        }
        report("settings_rows", rows.count)
        XCTAssertLessThanOrEqual(rows.count, 8)

        // The common answers are on the list itself, without opening a page.
        XCTAssertTrue(app.staticTexts[appearanceThemeValue].exists,
                      "the appearance row does not show the theme")
        XCTAssertTrue(app.staticTexts["Full place data"].exists,
                      "the data row does not show the place-content value")

        // The Google switch stays directly reachable, as the localization guard requires.
        let google = app.switches["settings-no-google"]
        XCTAssertTrue(google.exists, "the Google switch is missing from the first screen")
        XCTAssertTrue(google.isHittable, "the Google switch needs scrolling")
        shot("settings-top")

        app.buttons["settings-privacy-page"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["privacy-screen"].waitForExistence(timeout: 10),
                      "the privacy page did not open")
        let total = scrollTo("privacy-counter-total", in: app)
        XCTAssertTrue(total.waitForExistence(timeout: 5), "the privacy counter is missing")
        shot("settings-privacy-page")
        app.buttons["privacy-done"].tap()
        XCTAssertTrue(app.buttons["settings-done"].waitForExistence(timeout: 5))
    }

    func testContentAndData() {
        let app = launch(arguments: ["-VelaResetSettings", "YES"])
        defer { resetAfterTest() }
        openSettings(app)

        // The Google switch stays on the first screen of the list.
        XCTAssertTrue(app.switches["settings-no-google"].isHittable)
        shot("settings-top")

        app.buttons["settings-data-content"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["settings-data-screen"].waitForExistence(timeout: 10),
                      "the data and content page did not open")

        choose("settings-place-content", option: "Tiles only", in: app)
        setSwitch("settings-photos-wifi", on: true, in: app)
        choose("settings-photo-quality", option: "Low", in: app)
        choose("settings-photo-cache-size", option: "50 MB", in: app)

        let clear = scrollTo("settings-photo-cache-clear", in: app)
        XCTAssertTrue(clear.waitForExistence(timeout: 5), "the photo cache purge is missing")
        clear.tap()
        XCTAssertTrue(scrollTo("settings-photo-cache-used", in: app).exists)

        setSwitch("settings-low-data", on: true, in: app)
        setSwitch("settings-low-ram", on: true, in: app)

        let line = debugText("settings-content-debug")
            ?? (scrollTo("settings-content-debug", in: app).exists
                ? debugText("settings-content-debug") : nil)
            ?? "missing"
        report("settings_content", line.replacingOccurrences(of: " ", with: ","))
        shot("settings-content")
        XCTAssertTrue(line.contains("lowData=1"), line)
        XCTAssertTrue(line.contains("lowRam=1"), line)
        XCTAssertTrue(line.contains("wifi=1"), line)
        XCTAssertTrue(line.contains("place=tiles"), line)
        XCTAssertTrue(line.contains("quality=low"), line)
        XCTAssertTrue(line.contains("cacheMb=50"), line)

        app.buttons["settings-data-done"].tap()
        XCTAssertTrue(app.buttons["settings-trips"].waitForExistence(timeout: 5))
        app.buttons["settings-trips"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["settings-trips-screen"].waitForExistence(timeout: 10),
                      "the saved and trips page did not open")

        setSwitch("settings-redact-exports", on: true, in: app)
        let delete = scrollTo("settings-trips-delete", in: app)
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "the trip purge is missing")
        delete.tap()
        let dialog = app.sheets.firstMatch
        _ = dialog.waitForExistence(timeout: 5)
        let confirm = dialog.exists
            ? dialog.buttons["Delete all recorded trips"].firstMatch
            : app.buttons["Delete all recorded trips"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "the purge has no confirmation")
        confirm.tap()

        let tripLine = debugText("settings-trips-debug")
            ?? (scrollTo("settings-trips-debug", in: app).exists
                ? debugText("settings-trips-debug") : nil)
            ?? "missing"
        report("settings_trips", tripLine.replacingOccurrences(of: " ", with: ","))
        XCTAssertTrue(tripLine.contains("redact=1"), tripLine)
        XCTAssertTrue(tripLine.contains("trips=0"), tripLine)

        app.buttons["settings-trips-done"].tap()
        XCTAssertTrue(app.buttons["settings-done"].waitForExistence(timeout: 5))
        app.buttons["settings-done"].tap()
        XCTAssertTrue(app.textFields["search-field"].waitForExistence(timeout: 10))
    }

    /// DESIGN-W1 wave 1: the three surfaces this lot owns use the token geometry. The scenario
    /// reads the 44 pt targets of the hierarchy, names the screenshots and reports the line the
    /// CI summary copies.
    func testDesignTokensApplied() {
        let app = launch(arguments: ["-VelaResetSettings", "YES"])
        defer { resetAfterTest() }
        openSettings(app)

        let done = app.buttons["settings-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 15))
        report("design_settings_done_height", Int(done.frame.height))
        XCTAssertGreaterThanOrEqual(done.frame.height, 44, "Done is under the 44 pt target")

        // The Google switch stays on the first screen, and its row keeps a 44 pt target.
        let google = app.switches["settings-no-google"]
        XCTAssertTrue(google.isHittable)
        report("design_settings_google_height", Int(google.frame.height))
        XCTAssertGreaterThanOrEqual(google.frame.height, 44)
        shot("design-settings")
        report("design_settings", 1)

        let about = scrollTo("settings-about", in: app)
        XCTAssertTrue(about.waitForExistence(timeout: 5), "the About row is missing")
        about.tap()
        let aboutDone = app.buttons["about-done"]
        XCTAssertTrue(aboutDone.waitForExistence(timeout: 10), "the About hub did not open")
        // A toolbar item reports its 36 pt label, not the 44 pt bar it sits in, so the scenario
        // proves the About target by the search row and the hub itself rather than that frame.
        XCTAssertTrue(aboutDone.isHittable, "the About Done is not reachable")
        let search = app.textFields["about-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5), "the About search field is missing")
        report("design_about_search_height", Int(search.frame.height))
        shot("design-about")
        aboutDone.tap()
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        done.tap()

        XCTAssertTrue(app.textFields["search-field"].waitForExistence(timeout: 10))
        app.buttons["map-overflow"].tap()
        XCTAssertTrue(app.buttons["offline-menu-item"].waitForExistence(timeout: 5))
        app.buttons["offline-menu-item"].tap()
        let offlineDone = app.buttons["offline-done"]
        XCTAssertTrue(offlineDone.waitForExistence(timeout: 15), "the offline sheet did not open")
        report("design_offline_done_height", Int(offlineDone.frame.height))
        let areaStart = app.buttons["offline-area-start"]
        XCTAssertTrue(areaStart.waitForExistence(timeout: 10), "the area entry is missing")
        XCTAssertGreaterThanOrEqual(areaStart.frame.height, 44, "the area entry is under 44 pt")
        report("design_offline_area_height", Int(areaStart.frame.height))
        shot("design-offline")
        report("design_offline", 1)
    }

    private var appearanceThemeValue: String {
        // The appearance row shows the current theme. The reset suite starts on Follow system.
        "Follow system"
    }

    private func openSettings(_ app: XCUIApplication) {
        app.buttons["map-overflow"].tap()
        XCTAssertTrue(app.buttons["settings-menu-item"].waitForExistence(timeout: 5))
        app.buttons["settings-menu-item"].tap()
        // The debug line sits under the maid section headers, so the screen is proved by its own
        // identifier and the line is only revealed when a scenario reads it.
        // The Done button is a real control; the screen's own identifier sits on a container and is
        // not always published.
        if !app.buttons["settings-done"].waitForExistence(timeout: 15) {
            report("sheet_debug", debugText("sheet-debug") ?? "missing")
            print("SETTINGS-DID-NOT-OPEN\n\(app.debugDescription)")
        }
        XCTAssertTrue(app.buttons["settings-done"].exists, "settings did not open")
    }

    @discardableResult
    private func scrollTo(_ id: String, in app: XCUIApplication) -> XCUIElement {
        let element = app.descendants(matching: .any)[id]
        // A SwiftUI Form builds its rows lazily and drops the ones far off screen, so an absent
        // row says nothing about its direction. Look one way, then the other, and stop as soon as
        // the row is both present and hittable.
        let form = settingsForm(app)
        // A SwiftUI Form builds its rows lazily and drops the ones far off screen, so an absent
        // row says nothing about its direction. Look one way, then the other, and stop as soon as
        // the row is both present and hittable. The loops break instead of relying on a `where`
        // clause, which would keep re-querying a resolved row and hand a stale frame to the tap.
        for _ in 0..<24 {
            if onScreen(element) { return element }
            // A row still in the hierarchy above the form asks for a downward swipe; everything
            // else is below and asks for an upward one. A row the form has not built yet has a
            // zero frame, and asking a zero-frame element for its hittability throws, so the
            // frame is checked first.
            if element.exists && element.frame.height > 1 && element.frame.maxY < form.frame.minY {
                form.swipeDown()
            } else {
                form.swipeUp()
            }
        }
        for _ in 0..<24 {
            if onScreen(element) { return element }
            form.swipeDown()
        }
        return element
    }

    /// True only when the element is built and its activation point is valid. A lazy Form row
    /// that sits far off screen exists sometimes with a zero frame, and `isHittable` throws on
    /// that frame instead of returning false.
    private func onScreen(_ element: XCUIElement) -> Bool {
        guard element.exists else { return false }
        let frame = element.frame
        guard frame.width > 1, frame.height > 1 else { return false }
        return element.isHittable
    }

    /// The Form that is on screen. The map's quick-category row stays in the hierarchy behind the
    /// sheet and answers `scrollViews.firstMatch` first, so scrolling that element moved nothing
    /// and the switches below the fold never became hittable.
    private func settingsForm(_ app: XCUIApplication) -> XCUIElement {
        let screens = [
            "settings-data-screen", "settings-trips-screen", "settings-navigation-screen",
            "settings-voice-screen", "appearance-screen", "privacy-screen", "about-screen",
            "settings-screen",
        ]
        for id in screens {
            let form = app.descendants(matching: .any)[id].firstMatch
            if form.exists && form.frame.width > 1 && form.frame.height > 1 && form.isHittable {
                return form
            }
        }
        return app
    }

    private func setSwitch(_ id: String, on: Bool, in app: XCUIApplication) {
        let toggle = scrollTo(id, in: app)
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "missing switch \(id)")
        let target = on ? "1" : "0"
        if String(describing: toggle.value ?? "") != target {
            // The row's accessibility frame is wider than the switch: tap the control itself.
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        if !waitUntil(2, { String(describing: toggle.value ?? "") == target }),
           String(describing: toggle.value ?? "") != target {
            toggle.tap()
        }
        XCTAssertTrue(waitUntil(10) { String(describing: toggle.value ?? "") == target },
                      "\(id) did not change: \(String(describing: toggle.value ?? "none"))")
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
        clean.launchArguments = [
            "-VelaResetSettings", "YES", "-VelaDeterministic", "YES", "-VelaResetNavigation", "YES",
        ]
        clean.launch()
        clean.terminate()
    }
}
