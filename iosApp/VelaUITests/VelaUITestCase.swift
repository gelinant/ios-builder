import XCTest

/// Base class of the UI scenarios (docs/ios/TESTING-IOS.md): launch with the app's test arguments,
/// named screenshots, waits, and `UITEST key=value` lines that scripts/ios/ci-ipa.sh copies to the
/// summary.
class VelaUITestCase: XCTestCase {
    /// The sheet roots this base class knows, oldest presentation first. Discovery keeps the last
    /// one on screen, so a page opened from Settings wins over the Settings form behind it.
    private static let sheetRoots = [
        "route-sheet", "steps-sheet", "place-sheet", "map-poi-sheet", "offline-sheet",
        "unified-list-sheet", "unified-settings-sheet", "unified-wiki-sheet",
        "search-filter-sheet", "transit-live-sheet", "transit-line-sheet",
        "transit-go-line-sheet", "nav-stop-sheet", "list-editor-form",
        "settings-screen", "privacy-screen",
    ]

    /// Swipes the presented sheet until the element exists. A SwiftUI List builds its rows lazily,
    /// so a row that is below the first screen is not in the tree yet and `.waitForExistence` fails
    /// even though the row is there once scrolled. `sheet` names the sheet root or a stable element
    /// inside it; without it the helper finds the frontmost known sheet itself. A compact route
    /// chooser is expanded first, because its stop rows are not in the tree while it is compact.
    @discardableResult
    func revealInSheet(_ element: XCUIElement, in app: XCUIApplication, sheet: String? = nil,
                       tries: Int = 10, requireHittable: Bool = false, up: Bool = true) -> Bool {
        func reached() -> Bool { element.exists && (!requireHittable || element.isHittable) }
        var attempt = 0
        while !reached() && attempt < tries {
            let expand = app.buttons["route-expand"].firstMatch
            if !element.exists, expand.exists, expand.label == "Show all routes" {
                expand.tap()
            } else {
                swipeInsideSheet(in: app, named: sheet, up: up)
            }
            usleep(300_000)
            attempt += 1
        }
        return reached()
    }

    /// The sheet to scroll: the named root or anchor, else the last known sheet in the hierarchy.
    private func sheetTarget(in app: XCUIApplication, named: String?) -> XCUIElement? {
        if let named {
            let target = app.descendants(matching: .any)[named].firstMatch
            if target.exists && target.frame.height > 0 { return target }
        }
        var found: XCUIElement?
        for id in Self.sheetRoots {
            let candidate = app.descendants(matching: .any)[id].firstMatch
            if candidate.exists && candidate.frame.height > 1 { found = candidate }
        }
        return found
    }

    /// Swipes the tallest scroll view inside the sheet, or drags the sheet itself. The map's own
    /// scroll views are never used while a sheet is up.
    private func swipeInsideSheet(in app: XCUIApplication, named: String?, up: Bool) {
        if let target = sheetTarget(in: app, named: named) {
            let scrolls = target.scrollViews.allElementsBoundByIndex
                .filter { $0.exists && $0.frame.height > 1 && $0.frame.height > $0.frame.width }
            if let tallest = scrolls.max(by: { $0.frame.height < $1.frame.height }) {
                if up { tallest.swipeUp() } else { tallest.swipeDown() }
                return
            }
            if target.frame.height >= 200 {
                let near = up ? 0.65 : 0.25
                let far = up ? 0.2 : 0.7
                let start = target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: near))
                let end = target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: far))
                start.press(forDuration: 0.05, thenDragTo: end)
                return
            }
        }
        if let scroll = app.scrollViews.allElementsBoundByIndex.last(where: {
            $0.exists && $0.frame.height > 1 && $0.identifier != "quick-categories"
        }) {
            if up { scroll.swipeUp() } else { scroll.swipeDown() }
        } else if up {
            app.swipeUp()
        } else {
            app.swipeDown()
        }
    }

    private(set) var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
    }

    /// Launches the app over a start camera (`sf`, `davis`, `sacramento` or `lat,lng[,zoom]`),
    /// deterministic (no animation) unless told otherwise, and waits for the map screen. Every
    /// scenario starts from a clean launch state: the persisted drive is dropped unless the
    /// scenario asks for the resume itself.
    @discardableResult
    func launch(camera: String = "sf", deterministic: Bool = true, followUser: Bool = false,
                resetNavigation: Bool = true, waitForMap: Bool = true,
                arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-VelaStartCamera", camera] + arguments
        if deterministic { app.launchArguments += ["-VelaDeterministic", "YES"] }
        if followUser { app.launchArguments += ["-VelaFollowUser", "YES"] }
        if resetNavigation { app.launchArguments += ["-VelaResetNavigation", "YES"] }
        app.launch()
        self.app = app
        if waitForMap {
            XCTAssertTrue(app.textFields["search-field"].waitForExistence(timeout: 60), "no map screen")
        }
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

    /// The text of a Debug build status line (`velacore-debug`, `calibration-debug`), or nil. A
    /// local launcher that never assigned `app` reports a missing line instead of killing the
    /// runner with a force unwrap.
    func debugText(_ id: String) -> String? {
        guard let app else { return nil }
        let element = app.staticTexts[id]
        return element.exists ? element.label : nil
    }

    /// One result line for the CI summary.
    func report(_ key: String, _ value: Any) {
        print("UITEST \(key)=\(value)")
    }
}
