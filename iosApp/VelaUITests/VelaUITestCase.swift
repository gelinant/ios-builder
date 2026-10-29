import XCTest

/// Base class of the UI scenarios (docs/ios/TESTING-IOS.md): launch with the app's test arguments,
/// named screenshots, waits, and `UITEST key=value` lines that scripts/ios/ci-ipa.sh copies to the
/// summary.
class VelaUITestCase: XCTestCase {
    /// Swipes the presented sheet until the element exists. A SwiftUI List builds its rows lazily,
    /// so a row that is below the first screen is not in the tree yet and `.waitForExistence` fails
    /// even though the row is there once scrolled.
    @discardableResult
    func revealInSheet(_ element: XCUIElement, in app: XCUIApplication, tries: Int = 10) -> Bool {
        let named = app.descendants(matching: .any)["offline-sheet"].firstMatch
        var attempt = 0
        while !element.exists && attempt < tries {
            if named.exists && named.frame.height > 1 {
                named.swipeUp()
            } else if app.scrollViews.firstMatch.exists, app.scrollViews.firstMatch.frame.height > 1 {
                app.scrollViews.firstMatch.swipeUp()
            } else {
                app.swipeUp()
            }
            attempt += 1
        }
        return element.exists
    }

    private(set) var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
    }

    /// Launches the app over a start camera (`sf`, `davis`, `sacramento` or `lat,lng[,zoom]`),
    /// deterministic (no animation) unless told otherwise, and waits for the map screen.
    @discardableResult
    func launch(camera: String = "sf", deterministic: Bool = true, followUser: Bool = false,
                arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-VelaStartCamera", camera] + arguments
        if deterministic { app.launchArguments += ["-VelaDeterministic", "YES"] }
        if followUser { app.launchArguments += ["-VelaFollowUser", "YES"] }
        app.launch()
        self.app = app
        XCTAssertTrue(app.textFields["search-field"].waitForExistence(timeout: 60), "no map screen")
        return app
    }

    /// Saves the screen as `<name>.png` in SHOT_DIR (set by ci-ipa.sh through
    /// TEST_RUNNER_SHOT_DIR) and as an attachment of the test result.
    func shot(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SHOT_DIR"], !dir.isEmpty {
            let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).png")
            do {
                try shot.pngRepresentation.write(to: url)
            } catch {
                print("SCREENSHOT_WRITE_FAILED \(name): \(error)")
            }
        }
    }

    /// Polls [condition] every half second until it holds or [timeout] seconds pass.
    @discardableResult
    func waitUntil(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if condition() { return true }
            usleep(500_000)
        }
        return condition()
    }

    /// The text of a Debug build status line (`velacore-debug`, `calibration-debug`), or nil.
    func debugText(_ id: String) -> String? {
        let element = app.staticTexts[id]
        return element.exists ? element.label : nil
    }

    /// One result line for the CI summary.
    func report(_ key: String, _ value: Any) {
        print("UITEST \(key)=\(value)")
    }
}
