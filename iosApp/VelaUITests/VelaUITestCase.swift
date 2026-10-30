import XCTest

/// Base class of the UI scenarios (docs/ios/TESTING-IOS.md): launch with the app's test arguments,
/// named screenshots, waits, and `UITEST key=value` lines that scripts/ios/ci-ipa.sh copies to the
/// summary.
class VelaUITestCase: XCTestCase {
    /// Which way the content moves while `reveal` looks for an element. `.forward` is the usual
    /// case (a row below the fold); `.backward` returns to a card that sits above the current
    /// scroll position, such as a Settings line above the Privacy page.
    enum RevealDirection {
        case forward
        case backward
    }

    /// Swipes the named sheet until the element exists and is hittable. A SwiftUI `List`, `Form`
    /// or `LazyVStack` builds its rows lazily, so a row below the fold is not in the tree yet and
    /// `.waitForExistence` fails even though the row is there once scrolled.
    ///
    /// `sheet` is the identifier of the sheet root (`route-sheet`, `settings-screen`,
    /// `offline-sheet`, `search-suggestions`). The scroll container is resolved in this order:
    /// 1. a scroll view, collection view or table carrying the sheet identifier itself;
    /// 2. the first scroll container inside the identified sheet root, which covers a `Form` or a
    ///    `List` whose identifier lands on the container and a sheet that names its inner
    ///    `ScrollView` (`route-scroll` inside `route-sheet`);
    /// 3. the identified element itself when it is tall enough to drag.
    /// When none of these exist the helper does not swipe at all: it never falls back to the app,
    /// so a sheet cannot push the map, the search panel or another surface behind it.
    @discardableResult
    func reveal(_ id: String, in sheet: String, app: XCUIApplication? = nil,
                direction: RevealDirection = .forward, tries: Int = 12) -> XCUIElement {
        let target = app ?? self.app
        let element = target!.descendants(matching: .any)[id].firstMatch
        guard let container = sheetScrollContainer(named: sheet, in: target!) else { return element }
        var attempt = 0
        while !(element.exists && element.isHittable) && attempt < tries {
            if direction == .forward { container.swipeUp() } else { container.swipeDown() }
            usleep(300_000)
            attempt += 1
        }
        return element
    }

    /// The element that receives the drag for `reveal`: the sheet's own scroll container, never
    /// the app behind the sheet.
    private func sheetScrollContainer(named id: String, in app: XCUIApplication) -> XCUIElement? {
        for type in [XCUIElement.ElementType.scrollView, .collectionView, .table] {
            let candidate = app.descendants(matching: type)[id].firstMatch
            if candidate.exists && candidate.frame.height > 1 { return candidate }
        }
        let root = app.descendants(matching: .any)[id].firstMatch
        guard root.exists else { return nil }
        for type in [XCUIElement.ElementType.scrollView, .collectionView, .table] {
            let inner = root.descendants(matching: type).firstMatch
            if inner.exists && inner.frame.height > 1 { return inner }
        }
        return root.frame.height > 1 ? root : nil
    }

    /// Reads a Debug status line (`intents-debug`, `settings-debug`). Map lines have to be read
    /// before a sheet is opened, because `MapScreen` hides its debug block while a place or route
    /// sheet is up. The lines in the invisible map overlay (`tap-chain-debug`, `layers-debug`,
    /// `transit-debug`, `intents-debug`) stay readable while a sheet is open.
    func debugValue(_ id: String) -> String? {
        guard let app else { return nil }
        let line = app.descendants(matching: .any)[id].firstMatch
        guard line.exists else { return nil }
        return line.label.isEmpty ? nil : line.label
    }

    /// Swipes the presented sheet until the element exists. Kept for the older scenarios; new
    /// scenarios use `reveal(_:in:)`, which names the sheet and requires the element to be
    /// hittable.
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
