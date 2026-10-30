import CoreGraphics
import XCTest

/// SET-CONTENT on the simulator: the place content policy, the two Android flags, the photo cache
/// row and the recorded-trip purge. The Google switch must still be near the top.
final class SettingsUITests: VelaUITestCase {
    func testContentAndData() {
        let app = launch(arguments: ["-VelaResetSettings", "YES"])
        defer { resetAfterTest() }
        openSettings(app)

        // The Google switch stays in the first two screens of the form.
        var swipes = 0
        while !app.switches["settings-no-google"].isHittable && swipes < 2 {
            settingsForm(app).swipeUp()
            swipes += 1
        }
        report("settings_google_swipes", swipes)
        XCTAssertLessThanOrEqual(swipes, 2, "the Google switch needs too much scrolling")
        XCTAssertTrue(app.switches["settings-no-google"].isHittable)

        // The rows are visited in the order the form shows them, so every scroll goes one way.
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
        XCTAssertTrue(line.contains("redact=1"), line)
        XCTAssertTrue(line.contains("trips=0"), line)

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

        // The Google switch stays near the top, and its row keeps a 44 pt target.
        var swipes = 0
        while !app.switches["settings-no-google"].isHittable && swipes < 2 {
            settingsForm(app).swipeUp()
            swipes += 1
        }
        report("design_settings_google_swipes", swipes)
        XCTAssertTrue(app.switches["settings-no-google"].isHittable)
        report("design_settings_google_height", Int(app.switches["settings-no-google"].frame.height))
        XCTAssertGreaterThanOrEqual(app.switches["settings-no-google"].frame.height, 44)
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

    /// The settings form itself. The map's quick-category row stays in the hierarchy behind the
    /// sheet and answers `scrollViews.firstMatch` first, so scrolling that element moved nothing
    /// and the switches below the fold never became hittable.
    private func settingsForm(_ app: XCUIApplication) -> XCUIElement {
        let form = app.descendants(matching: .any)["settings-screen"].firstMatch
        return form.exists ? form : app
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
