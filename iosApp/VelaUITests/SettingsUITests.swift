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
            app.scrollViews.firstMatch.swipeUp()
            swipes += 1
        }
        report("settings_google_swipes", swipes)
        XCTAssertLessThanOrEqual(swipes, 2, "the Google switch needs too much scrolling")
        XCTAssertTrue(app.switches["settings-no-google"].isHittable)

        setSwitch("settings-low-data", on: true, in: app)
        setSwitch("settings-low-ram", on: true, in: app)
        setSwitch("settings-photos-wifi", on: true, in: app)
        setSwitch("settings-redact-exports", on: true, in: app)

        choose("settings-place-content", option: "Tiles only", in: app)
        choose("settings-photo-quality", option: "Low", in: app)
        choose("settings-photo-cache-size", option: "50 MB", in: app)

        let clear = scrollTo("settings-photo-cache-clear", in: app)
        XCTAssertTrue(clear.waitForExistence(timeout: 5), "the photo cache purge is missing")
        clear.tap()
        XCTAssertTrue(scrollTo("settings-photo-cache-used", in: app).exists)

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

        for _ in 0..<6 where !app.staticTexts["settings-content-debug"].exists {
            app.scrollViews.firstMatch.swipeDown()
        }
        let line = debugText("settings-content-debug") ?? "missing"
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

    private func openSettings(_ app: XCUIApplication) {
        app.buttons["map-overflow"].tap()
        XCTAssertTrue(app.buttons["settings-menu-item"].waitForExistence(timeout: 5))
        app.buttons["settings-menu-item"].tap()
        // The debug line sits under the maid section headers, so the screen is proved by its own
        // identifier and the line is only revealed when a scenario reads it.
        // The Done button is a real control; the screen's own identifier sits on a container and is
        // not always published.
        XCTAssertTrue(app.buttons["settings-done"].waitForExistence(timeout: 15), "settings did not open")
    }

    @discardableResult
    private func scrollTo(_ id: String, in app: XCUIApplication) -> XCUIElement {
        let element = app.descendants(matching: .any)[id]
        // A SwiftUI Form builds its rows lazily, so an element that does not exist yet must be
        // scrolled for as well, and the settings form has grown with the appearance section.
        for _ in 0..<24 where !(element.exists && element.isHittable) {
            if app.scrollViews.firstMatch.exists { app.scrollViews.firstMatch.swipeUp() } else { app.swipeUp() }
        }
        return element
    }

    private func setSwitch(_ id: String, on: Bool, in app: XCUIApplication) {
        let toggle = scrollTo(id, in: app)
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "missing switch \(id)")
        let target = on ? "1" : "0"
        if String(describing: toggle.value ?? "") != target { toggle.tap() }
        if !waitUntil(2, { String(describing: toggle.value ?? "") == target }),
           String(describing: toggle.value ?? "") != target {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
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
        clean.launchArguments = ["-VelaResetSettings", "YES", "-VelaDeterministic", "YES"]
        clean.launch()
        clean.terminate()
    }
}
