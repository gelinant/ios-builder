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
        var attempt = 0
        // A row update (a download finishing, a category being deleted) rebuilds the list, so the
        // container is resolved again before every swipe instead of once for the whole loop. The
        // first half second lets that rebuild settle before the first drag.
        if !(element.exists && element.isHittable) { usleep(500_000) }
        while !(element.exists && element.isHittable) && attempt < tries {
            guard let container = sheetScrollContainer(named: sheet, in: target!) else {
                return element
            }
            if direction == .forward { container.swipeUp() } else { container.swipeDown() }
            usleep(300_000)
            attempt += 1
        }
        return element
    }

    /// Opens one of the converged Settings sub-pages and waits for its root. The eight top-level
    /// rows keep their identifiers; the mapping names the page identifier each row pushes. Every
    /// control that moved to a sub-page is then found inside that page's own scroll container.
    @discardableResult
    func openSettingsPage(_ name: String, in app: XCUIApplication? = nil,
                          tries: Int = 16, timeout: TimeInterval = 15) -> XCUIElement {
        let target = app ?? self.app!
        let pages: [String: (row: String, screen: String)] = [
            "privacy": ("settings-privacy-page", "privacy-screen"),
            "appearance": ("settings-appearance", "appearance-screen"),
            "navigation": ("settings-navigation", "settings-navigation-screen"),
            "voice": ("settings-voice", "settings-voice-screen"),
            "data": ("settings-data-content", "settings-data-screen"),
            "trips": ("settings-trips", "settings-trips-screen"),
            "about": ("settings-about", "about-screen"),
        ]
        guard let page = pages[name] else {
            XCTFail("unknown Settings page \(name)")
            return target.descendants(matching: .any)["missing-settings-page"].firstMatch
        }
        let row = reveal(page.row, in: "settings-screen", app: target, tries: tries)
        XCTAssertTrue(row.waitForExistence(timeout: timeout), "missing Settings row \(page.row)")
        row.tap()
        let screen = target.descendants(matching: .any)[page.screen].firstMatch
        XCTAssertTrue(screen.waitForExistence(timeout: timeout), "the \(name) page did not open")
        return screen
    }

    /// CHROME-CONVERGE: reaches a former map button through the short actions sheet.
    ///
    /// The map keeps two persistent controls, `locate-button` and `map-actions-open`. The former
    /// layers, transit, free drive, parking, trips, trace, terrain and settings buttons now live
    /// as rows of `MapActionsSheet`, each keeping the identifier it carried on the map. A
    /// scenario that tapped one of them straight from the map calls this helper instead.
    ///
    /// Contract: when the target is already on screen and hittable, the helper taps it in place;
    /// otherwise it taps `map-actions-open`, waits for the sheet, scrolls the list to the row,
    /// taps it, and waits out the dismissal that the row triggers. The returned element is the
    /// destination query, resolved again after the tap; a scenario still waits for whatever the
    /// destination shows, so the proof is unchanged.
    ///
    /// `saved-open` has two entries: the bookmark accessory at the end of the search pill, which
    /// never left the map, and the Saved row in the actions sheet. Both carry the same
    /// identifier. The accessory is the shorter route, so the helper taps it first and only falls
    /// back to the sheet row when that accessory is missing or covered.
    @discardableResult
    func openMapAction(_ id: String, in app: XCUIApplication? = nil,
                       timeout: TimeInterval = 30) -> XCUIElement {
        let target = app ?? self.app!
        let direct = target.buttons[id].firstMatch
        if direct.exists && direct.isHittable {
            direct.tap()
            return target.buttons[id].firstMatch
        }

        let actions = target.buttons["map-actions-open"]
        XCTAssertTrue(actions.waitForExistence(timeout: timeout), "no map actions control")
        XCTAssertTrue(actions.isHittable, "the map actions control has no hit point")
        actions.tap()
        XCTAssertTrue(target.buttons["map-actions-close"].waitForExistence(timeout: 10),
                      "the map actions sheet did not open")

        let row = mapActionRow(id, in: target)
        XCTAssertTrue(row.exists, "the map actions sheet has no \(id) row")
        XCTAssertTrue(row.isHittable, "the \(id) row has no hit point")
        row.tap()

        // A chosen row dismisses the actions sheet before MapScreen performs the destination. A
        // destination that keeps its own sheet reuses that presentation gap; one that acts on the
        // map (terrain, trace, parking) simply leaves the map bare. Either way the actions sheet
        // is gone, and no destination is expected to leave it up.
        _ = waitUntil(10) { !target.buttons["map-actions-close"].exists }
        return target.buttons[id].firstMatch
    }

    /// The row of the actions sheet, scrolled into reach. The sheet is a `List`, so a row below
    /// the fold is absent from the tree until the list scrolls. The accessory with the same
    /// identifier (`saved-open`) stays in the hierarchy while the sheet covers it, so rows are
    /// resolved inside the sheet's list frame instead of taking `firstMatch`.
    private func mapActionRow(_ id: String, in app: XCUIApplication) -> XCUIElement {
        func list() -> XCUIElement? {
            let candidates = app.collectionViews.allElementsBoundByIndex
                + app.tables.allElementsBoundByIndex
            return candidates.filter { $0.exists && $0.frame.height > 100 }
                .max { $0.frame.height < $1.frame.height }
        }
        func row() -> XCUIElement? {
            let matches = app.buttons.matching(identifier: id).allElementsBoundByIndex
            if let frame = list()?.frame,
               let inside = matches.first(where: { frame.contains($0.frame) }) {
                return inside
            }
            return matches.first(where: { $0.isHittable })
        }
        var attempt = 0
        while !(row().map { $0.exists && $0.isHittable } ?? false) && attempt < 10 {
            if let sheet = list() { sheet.swipeUp() } else { app.swipeUp() }
            usleep(300_000)
            attempt += 1
        }
        return row() ?? app.buttons[id].firstMatch
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

    /// A performance limit that follows the runner instead of a wall-clock constant. The baseline
    /// is measured immediately before the action; the action may take up to `multiple` times that
    /// baseline, and must also stay under `capMs`.
    struct BaselineBudget {
        let baselineMs: Double
        let actionMs: Double
        let multiple: Double
        let capMs: Double

        var ratio: Double { baselineMs > 0 ? actionMs / baselineMs : .infinity }
        /// The strictest of the two rules: the multiple and the absolute cap.
        var limitMs: Double { min(baselineMs * multiple, capMs) }
        var isWithinBudget: Bool { actionMs <= limitMs }
    }

    /// Reports `<label>_baseline_ms`, `<label>_action_ms` and `<label>_ratio`, then asserts the
    /// action stays within `multiple` times the same-run baseline and under `capMs`. A constant
    /// budget on the shared simulator measures the runner; the baseline moves with it, while the
    /// cap keeps a real regression (tens of seconds) from hiding behind a slow baseline.
    @discardableResult
    func assertWithinBaseline(_ label: String, baselineMs: Double, actionMs: Double,
                              multiple: Double, capMs: Double,
                              file: StaticString = #filePath, line: UInt = #line) -> BaselineBudget {
        let budget = BaselineBudget(baselineMs: baselineMs, actionMs: actionMs,
                                    multiple: multiple, capMs: capMs)
        report("\(label)_baseline_ms", Int(baselineMs.rounded()))
        report("\(label)_action_ms", Int(actionMs.rounded()))
        report("\(label)_ratio", String(format: "%.2f", budget.ratio))
        XCTAssertGreaterThan(baselineMs, 0, "\(label) has no baseline", file: file, line: line)
        XCTAssertLessThanOrEqual(
            actionMs, budget.limitMs,
            "\(label) took \(Int(actionMs.rounded())) ms, over the \(Int(budget.limitMs.rounded())) ms "
                + "limit (\(String(format: "%.2f", budget.ratio))x a "
                + "\(Int(baselineMs.rounded())) ms baseline, cap \(Int(capMs)) ms)",
            file: file, line: line)
        return budget
    }

    /// The time a trivial UI query takes on the current runner, measured after a short settle.
    /// A gesture guard uses it as its baseline: when the runner is loaded every query is slower,
    /// and the gesture must not be slower than that by more than the allowed multiple.
    func responsivenessBaselineMs(_ probe: XCUIElement, settle: TimeInterval = 0.5) -> Double {
        let start = Date()
        usleep(UInt32(settle * 1_000_000))
        _ = probe.exists
        return (Date().timeIntervalSince(start) * 1000).rounded()
    }

    /// One result line for the CI summary.
    func report(_ key: String, _ value: Any) {
        print("UITEST \(key)=\(value)")
    }
}
