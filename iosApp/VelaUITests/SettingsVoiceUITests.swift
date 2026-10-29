import XCTest

/// SET-VOICE on the simulator: the voice section, the Android On / Alerts only / Off mode,
/// the guidance language versus the app language, the no-voice fallback, and the download rows.
/// The neural model is injected by scripts/ios/ci-ipa.sh as `VoiceFixture`; the download state is
/// the Debug-only `-VelaVoiceDownloadFixture` row, which starts no transfer.
final class SettingsVoiceUITests: VelaUITestCase {
    func testVoiceAndLanguage() {
        let app = launch(arguments: [
            "-VelaVoiceFixture", "YES",
            "-VelaVoiceDownloadFixture", "YES",
            "-VelaResetSettings", "YES",
        ])
        openSettings(app)

        // The same keys NAV-LIFE writes: the row and the drive button share the mode.
        let modeControl = app.segmentedControls["voice-mode"]
        XCTAssertTrue(scrollTo("voice-mode", in: app).waitForExistence(timeout: 15),
                      "no voice mode picker")
        shot("settings-voice")
        modeControl.buttons["Alerts only"].tap()
        let modeDebug = scrollDownToExists("voice-mode-debug", in: app)
        XCTAssertTrue(waitUntil(10) {
            modeDebug.label.contains("voicemode=alerts")
        }, "Alerts only did not reach the shared NavStore: \(modeDebug.label)")
        report("voice_mode", "alerts")
        shot("settings-voice-alerts")

        XCTAssertTrue(scrollUpTo("voice-mode", in: app).waitForExistence(timeout: 10))
        modeControl.buttons["On"].tap()
        _ = scrollDownToExists("voice-mode-debug", in: app)
        XCTAssertTrue(waitUntil(10) {
            (self.debugText("voice-mode-debug") ?? "").contains("voicemode=on")
        }, "the mode did not return to On")

        let current = scrollTo("voice-current", in: app)
        XCTAssertTrue(current.waitForExistence(timeout: 15), "no current voice row")
        XCTAssertTrue(current.label.contains("HFC Female"),
                      "the installed fixture is not the active voice: \(current.label)")
        report("voice_engine", current.label.replacingOccurrences(of: " ", with: "_"))

        // A guidance language with no installed neural voice falls back to the iPhone voice.
        let language = scrollUpTo("voice-directions-language", in: app)
        XCTAssertTrue(language.waitForExistence(timeout: 10), "no directions language row")
        shot("settings-voice-section")
        choose(language, option: "Français", in: app)
        let fallback = scrollTo("voice-fallback-hint", in: app)
        XCTAssertTrue(fallback.waitForExistence(timeout: 10),
                      "no fallback explanation after choosing French")
        XCTAssertTrue(fallback.label.contains("Français"), fallback.label)
        XCTAssertTrue(fallback.label.contains("iPhone voice"), fallback.label)
        report("voice_language", "fr")
        report("voice_fallback", fallback.label.replacingOccurrences(of: " ", with: "_"))
        shot("settings-voice-language")

        // The download row is visible whatever the guidance language is.
        let progress = scrollTo("voice-progress", in: app)
        XCTAssertTrue(progress.waitForExistence(timeout: 10), "no download progress row")
        report("voice_download", progress.label.replacingOccurrences(of: " ", with: "_"))
        shot("settings-voice-download")

        let library = scrollTo("voice-library", in: app)
        XCTAssertTrue(library.waitForExistence(timeout: 10), "no voice library row")
        library.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["voice-library-list"].waitForExistence(timeout: 10),
            "voice library did not open")
        XCTAssertTrue(app.staticTexts["Siwis"].waitForExistence(timeout: 10),
                      "the French catalog group is missing")
        shot("voice-library")
        app.buttons["voice-library-done"].tap()
    }

    private func openSettings(_ app: XCUIApplication) {
        let overflow = app.buttons["map-overflow"]
        XCTAssertTrue(overflow.waitForExistence(timeout: 20), "no map overflow menu")
        overflow.tap()
        XCTAssertTrue(app.buttons["settings-menu-item"].waitForExistence(timeout: 10))
        app.buttons["settings-menu-item"].tap()
        XCTAssertTrue(app.staticTexts["settings-debug"].waitForExistence(timeout: 20),
                      "settings did not open")
    }

    @discardableResult
    private func scrollTo(_ id: String, in app: XCUIApplication) -> XCUIElement {
        let element = app.descendants(matching: .any)[id]
        let scroll = app.scrollViews.firstMatch
        // Slow swipes do not jump over a short row the way a fast flick does. Every call site
        // here moves forward from the settings header.
        for _ in 0..<40 where !element.isHittable {
            if scroll.exists { scroll.swipeUp(velocity: .slow) } else { app.swipeUp() }
        }
        return element
    }

    /// Scrolls down until the row exists in the hierarchy. Used for the Debug lines, which are
    /// static text and can sit just below the fold of the row the test just tapped.
    @discardableResult
    private func scrollDownToExists(_ id: String, in app: XCUIApplication) -> XCUIElement {
        let element = app.descendants(matching: .any)[id]
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<12 where !element.isHittable {
            if scroll.exists { scroll.swipeUp(velocity: .slow) } else { app.swipeUp() }
        }
        return element
    }

    /// Moves back up to a row that was passed on the way down.
    @discardableResult
    private func scrollUpTo(_ id: String, in app: XCUIApplication) -> XCUIElement {
        let element = app.descendants(matching: .any)[id]
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<16 where !element.isHittable {
            if scroll.exists { scroll.swipeDown(velocity: .slow) } else { app.swipeDown() }
        }
        return element
    }

    private func choose(_ picker: XCUIElement, option: String, in app: XCUIApplication) {
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
}
