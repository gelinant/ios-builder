import CoreGraphics
import XCTest

/// Accessibility layout audits. Optional measurements are reported without making offscreen lazy
/// content a failure. Required targets fail only for a missing element, an undersized accessibility
/// frame, or an empty button label. Reachability and content assertions fail normally.
final class QualityUITests: VelaUITestCase {
    private let largestText = "UICTContentSizeCategoryAccessibilityXXXL"
    private let categoryIDs = [
        "category-coffee", "category-restaurants", "category-gas",
        "category-parking", "category-groceries", "category-transit",
    ]

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    func testSearchLargeTextLandscape() {
        let app = launchLarge(camera: "sf")
        assertTargets(app, ids: categoryIDs)
        let map = app.descendants(matching: .any)["map"]
        XCTAssertTrue(map.exists)
        XCTAssertEqual(map.label, "Map")
        landscape()
        shot("quality-map-large-landscape")
        qualitySearch(app, query: "coffee")
        sleep(2)
        shot("quality-search-large-landscape")
        audit(app, screen: "search", ids: [
            "search-field", "search-clear", "map-overflow", "search-panel-toggle", "search-result",
        ], required: ["search-field", "search-panel-toggle"])
        XCTAssertTrue(app.buttons["search-panel-toggle"].exists)
    }

    func testPlaceLargeTextLandscape() {
        let app = launchLarge(camera: "davis")
        qualityOpenPlace(app, query: "Davis Food Co-op")
        _ = waitUntil(45) { self.qualityValue("details", debugID: "place-debug") == "done" }
        landscape()
        sleep(2)
        shot("quality-place-large-landscape")
        let scroll = app.scrollViews["place-scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 10))

        let allPhotos = app.buttons["place-all-photos"]
        if qualityReveal(allPhotos, in: scroll) {
            assertTargets(app, ids: ["place-close", "place-directions", "place-save", "place-share", "place-all-photos"])
            allPhotos.tap()
            let gridClose = app.buttons["place-gallery-close"]
            if !gridClose.waitForExistence(timeout: 20) { shot("quality-place-grid-unreachable") }
            XCTAssertTrue(gridClose.exists, "photo grid did not open")
            let gridPhoto = app.buttons["place-grid-photo-0"]
            XCTAssertTrue(qualityReveal(gridPhoto, in: app.scrollViews.firstMatch),
                          "first grid photo is not reachable")
            XCTAssertTrue(gridPhoto.label.hasPrefix("Place photo 1 of "))
            gridClose.tap()
            XCTAssertTrue(app.staticTexts["place-name"].waitForExistence(timeout: 10))
        }

        let photo = app.buttons.matching(identifier: "place-photo").firstMatch
        XCTAssertTrue(qualityReveal(photo, in: scroll), "place photo is not reachable")
        assertTargets(app, ids: ["place-photo"])
        XCTAssertTrue(photo.label.hasPrefix("Place photo 1 of "))
        shot("quality-place-photo-accessibility")
        assertConditionalPlaceLabels(app)
        audit(app, screen: "place", ids: [
            "place-close", "place-directions", "place-save", "place-share", "place-all-photos",
            "place-all-reviews", "place-photo", "place-review-photo",
        ], required: ["place-close", "place-photo"])
        XCTAssertTrue(app.staticTexts["place-name"].exists)
    }

    func testRoutePickerLargeTextLandscape() {
        let app = launchLarge(camera: "sf", followUser: true)
        qualityOpenRoute(app, query: "coffee")
        XCTAssertTrue(app.buttons["route-row"].firstMatch.waitForExistence(timeout: 90),
                      "no route for the landscape audit")
        landscape()
        sleep(2)
        shot("quality-route-large-landscape")
        assertTargets(app, ids: ["route-swap", "route-close", "route-mode-DRIVE", "route-mode-WALK"])
        let scroll = app.scrollViews["route-scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 10))
        let avoid = app.buttons["route-avoid-highways"]
        XCTAssertTrue(qualityReveal(avoid, in: scroll), "avoid options are not reachable")
        assertTargets(app, ids: ["route-avoid-highways", "route-avoid-tolls", "route-avoid-ferries"])
        let steps = app.buttons["route-steps"]
        XCTAssertTrue(qualityReveal(steps, in: scroll), "route actions are not reachable")
        assertTargets(app, ids: ["route-start", "route-steps"])
        audit(app, screen: "route", ids: [
            "route-swap", "route-close", "route-mode-DRIVE", "route-mode-WALK",
            "route-avoid-highways", "route-start", "route-steps", "route-row",
        ], required: ["route-close", "route-avoid-highways", "route-start", "route-steps"])
        steps.tap()
        XCTAssertTrue(app.buttons["steps-close"].waitForExistence(timeout: 15))
        assertTargets(app, ids: ["steps-close"])
        assertLaneLabels(app)
        shot("quality-steps-large-landscape")
    }

    func testSettingsLargeTextLandscape() {
        let app = launchLarge(camera: "sf")
        qualityOpenSettings(app)
        landscape()
        sleep(2)
        shot("quality-settings-large-landscape")
        XCTAssertTrue(app.staticTexts["settings-debug"].exists)
        assertTargets(app, ids: ["settings-done", "settings-language", "settings-units"])
        let form = app.descendants(matching: .any)["settings-screen"]
        let toggle = app.switches["settings-no-google"]
        XCTAssertTrue(qualityReveal(toggle, in: form), "privacy toggle is not reachable")
        assertTargets(app, ids: ["settings-no-google"])
        let privacy = app.descendants(matching: .any)["settings-privacy-link"]
        XCTAssertTrue(qualityReveal(privacy, in: form), "privacy link is not reachable")
        assertTargets(app, ids: ["settings-privacy-link"])
        shot("quality-settings-privacy-large-landscape")
        audit(app, screen: "settings", ids: [
            "settings-done", "settings-language", "settings-units", "settings-clock",
            "settings-no-google", "settings-privacy-link",
        ], required: ["settings-done", "settings-privacy-link"])
    }

    func testHebrewRightToLeft() {
        let app = launch(arguments: ["-VelaResetSettings", "YES", "-VelaLanguage", "he"])
        sleep(2)
        shot("quality-search-he-rtl")
        XCTAssertNotEqual(app.textFields["search-field"].placeholderValue, "Search")
        assertTargets(app, ids: categoryIDs)
        let english = ["Coffee", "Restaurants", "Gas", "Parking", "Groceries", "Transit stops"]
        for (id, englishLabel) in zip(categoryIDs, english) {
            let category = app.buttons[id]
            XCTAssertTrue(category.exists)
            XCTAssertNotEqual(category.label, englishLabel, "category is not localized: \(id)")
        }
        qualityOpenSettings(app)
        shot("quality-settings-he-rtl")
        assertTargets(app, ids: ["settings-done", "settings-language", "settings-units"])
        let done = app.buttons["settings-done"]
        XCTAssertLessThan(done.frame.midX, app.frame.midX, "Done did not move to the RTL trailing edge")
        let form = app.descendants(matching: .any)["settings-screen"]
        let toggle = app.switches["settings-no-google"]
        XCTAssertTrue(qualityReveal(toggle, in: form), "Hebrew privacy toggle is not reachable")
        assertTargets(app, ids: ["settings-no-google"])
        XCTAssertLessThan(toggle.frame.midX, app.frame.midX, "toggle did not move to the RTL leading edge")
        shot("quality-settings-he-rtl-privacy")
        audit(app, screen: "hebrew", ids: [
            "settings-done", "settings-language", "settings-units", "settings-no-google",
        ], required: ["settings-done", "settings-no-google"])
        report("quality_hebrew_layout", "done-left-toggle-left")
    }

    /// The runner has only iPhone 17. Landscape exercises a compact vertical size class, not an SE.
    func testCompactHeightSettingsLandscape() {
        let app = launch(arguments: ["-VelaResetSettings", "YES"])
        landscape()
        qualityOpenSettings(app)
        shot("quality-settings-compact-landscape")
        assertTargets(app, ids: ["settings-done", "settings-language", "settings-units"])
        let form = app.descendants(matching: .any)["settings-screen"]
        let toggle = app.switches["settings-no-google"]
        XCTAssertTrue(qualityReveal(toggle, in: form), "compact-height privacy toggle is not reachable")
        assertTargets(app, ids: ["settings-no-google"])
        let privacy = app.descendants(matching: .any)["settings-privacy-link"]
        XCTAssertTrue(qualityReveal(privacy, in: form), "compact-height privacy link is not reachable")
        assertTargets(app, ids: ["settings-privacy-link"])
        report("quality_compact_device", "iphone-17-landscape-compact-height-only")
    }

    private func launchLarge(camera: String, followUser: Bool = false) -> XCUIApplication {
        launch(camera: camera, followUser: followUser, arguments: [
            "-VelaResetSettings", "YES",
            "-UIPreferredContentSizeCategoryName", largestText,
        ])
    }

    private func landscape() {
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        XCTAssertEqual(XCUIDevice.shared.orientation, .landscapeLeft)
    }

    private func assertTargets(_ app: XCUIApplication, ids: [String]) {
        for id in ids {
            let element = app.descendants(matching: .any)[id].firstMatch
            XCTAssertTrue(element.waitForExistence(timeout: 5), "missing target: \(id)")
            guard element.exists else { continue }
            let frame = element.frame
            report("quality_required_target_\(qualityKey(id))", "\(Int(frame.width))x\(Int(frame.height))")
            XCTAssertGreaterThanOrEqual(frame.width, 44, "target is too narrow: \(id)")
            XCTAssertGreaterThanOrEqual(frame.height, 44, "target is too short: \(id)")
        }
    }

    private func qualityReveal(_ element: XCUIElement, in scroll: XCUIElement) -> Bool {
        guard let app else { return false }
        return qualityRevealElement(element, in: scroll, app: app)
    }

    private func assertConditionalPlaceLabels(_ app: XCUIApplication) {
        let reviewPhotos = app.buttons.matching(identifier: "place-review-photo").allElementsBoundByIndex
        for photo in reviewPhotos where photo.exists {
            XCTAssertTrue(photo.label.contains(" from the review by "), "review photo lacks its author")
        }
        report("quality_review_photo_labels", reviewPhotos.count)
        let bars = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH 'popular-hour-' OR identifier == 'popular-current-hour'"))
        for bar in bars.allElementsBoundByIndex where bar.exists {
            XCTAssertTrue(bar.label.contains(","), "popular-time bar lacks its day and hour")
            XCTAssertTrue((bar.value as? String)?.contains("%") == true,
                          "popular-time bar lacks its occupancy value")
        }
        report("quality_popular_time_labels", bars.allElementsBoundByIndex.count)
    }

    private func assertLaneLabels(_ app: XCUIApplication) {
        let lanes = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH 'step-lane-'")).allElementsBoundByIndex
        for lane in lanes where lane.exists {
            XCTAssertTrue(lane.label.hasPrefix("Lane "), "lane lacks its position")
            let value = (lane.value as? String) ?? ""
            XCTAssertFalse(value.isEmpty, "lane lacks its directions")
            XCTAssertTrue(value.lowercased().contains("recommended"), "lane lacks its recommendation")
        }
        report("quality_lane_labels", lanes.count)
    }

    private func audit(_ app: XCUIApplication, screen: String, ids: [String], required: [String] = []) {
        var small: [String] = []
        var smallIDs: Set<String> = []
        var missing: [String] = []
        for id in ids {
            let element = app.descendants(matching: .any)[id].firstMatch
            guard element.exists else {
                missing.append(id)
                continue
            }
            let frame = element.frame
            let size = "\(Int(frame.width))x\(Int(frame.height))"
            report("quality_\(screen)_target_\(qualityKey(id))", size)
            // Frame size is valid offscreen. isHittable is neither a size check nor reliable there.
            if frame.width < 44 || frame.height < 44 {
                small.append("\(id):\(size)")
                smallIDs.insert(id)
            }
        }
        let unlabeled = app.buttons.allElementsBoundByIndex.filter {
            $0.exists && $0.isEnabled && $0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && qualityAppIdentifier($0.identifier)
        }.map { $0.identifier }
        report("quality_\(screen)_small_targets", small.count)
        report("quality_\(screen)_unlabeled_buttons", unlabeled.count)
        report("quality_\(screen)_missing_targets", missing.count)
        print("QUALITY_AUDIT screen=\(screen) small=\(small.joined(separator: ","))")
        print("QUALITY_AUDIT screen=\(screen) unlabeled=\(unlabeled.joined(separator: ","))")
        print("QUALITY_AUDIT screen=\(screen) missing=\(missing.joined(separator: ","))")
        let requiredMissing = required.filter { missing.contains($0) }
        let requiredSmall = required.filter { smallIDs.contains($0) }
        XCTAssertTrue(requiredMissing.isEmpty, "required targets missing: \(requiredMissing)")
        XCTAssertTrue(requiredSmall.isEmpty, "required targets undersized: \(requiredSmall)")
        XCTAssertTrue(unlabeled.isEmpty, "unlabeled app buttons: \(unlabeled)")
    }
}

/// One-iteration XCTest measurements on the simulator. Xcode 26 emits absolute and peak physical
/// memory alongside the metric's before/after values. Full values stay in the xcodebuild log and
/// transient xcresult; no number is copied into the docs unless the runner emitted it.
final class QualityPerformanceUITests: VelaUITestCase {
    func testApplicationLaunchMetric() {
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTApplicationLaunchMetric()], options: options) {
            let app = XCUIApplication()
            app.launchArguments = ["-VelaStartCamera", "sf", "-VelaDeterministic", "YES"]
            app.launch()
            app.terminate()
        }
        report("quality_launch_metric", "five_iterations_xcodebuild_log")
    }

    func testMapMemoryMetric() {
        defer { app?.terminate() }
        measureScenario("map") { _ in
            // Let the first vector tiles and glyphs settle after the search field appears.
            sleep(8)
        }
    }

    func testSearchMemoryMetric() {
        defer { app?.terminate() }
        measureScenario("search") { app in
            self.qualitySearch(app, query: "coffee")
        }
    }

    func testPlaceMemoryMetric() {
        defer { app?.terminate() }
        measureScenario("place") { app in
            self.qualityOpenPlace(app, query: "Davis Food Co-op")
            _ = self.waitUntil(45) { self.qualityValue("details", debugID: "place-debug") == "done" }
        }
    }

    func testNavigationMemoryMetric() {
        defer {
            qualityEndNavigation()
            app?.terminate()
        }
        measureScenario("navigation", followUser: true) { app in
            self.qualityOpenRoute(app, query: "coffee")
            XCTAssertTrue(self.waitUntil(90) {
                self.qualityValue("loading") == "0" && (Int(self.qualityValue("routes") ?? "") ?? 0) > 0
            })
            app.buttons["route-start"].tap()
            XCTAssertTrue(app.otherElements["nav-banner"].waitForExistence(timeout: 20))
            XCTAssertTrue(self.waitUntil(15) { self.qualityValue("nav", debugID: "nav-debug") == "1" })
            sleep(5)
        }
    }

    func testOfflineMemoryMetric() {
        defer { app?.terminate() }
        measureScenario("offline", camera: "43.7391,7.4280,14", arguments: ["-VelaOfflineTest", "YES"]) { app in
            self.qualityOfflineMapAndSearch(app)
        }
    }

    private func measureScenario(
        _ name: String,
        camera: String = "sf",
        followUser: Bool = false,
        arguments: [String] = [],
        scenario: @escaping (XCUIApplication) -> Void
    ) {
        let measuredApp = XCUIApplication()
        let options = XCTMeasureOptions()
        options.iterationCount = 1
        options.invocationOptions = [.manuallyStart]
        measure(metrics: [XCTMemoryMetric(application: measuredApp)], options: options) {
            let app = self.launch(camera: camera, followUser: followUser, arguments: arguments)
            self.startMeasuring()
            scenario(app)
        }
        report("quality_memory_\(name)", "one_iteration_xcodebuild_log")
    }
}

private extension VelaUITestCase {
    func qualitySearch(_ app: XCUIApplication, query: String) {
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 20))
        field.tap()
        field.typeText(query + "\n")
        let rows = app.buttons.matching(identifier: "search-result")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 60), "no search result for quality audit")
        sleep(3)
    }

    func qualityOpenPlace(_ app: XCUIApplication, query: String) {
        qualitySearch(app, query: query)
        app.buttons.matching(identifier: "search-result").firstMatch.tap()
        XCTAssertTrue(app.staticTexts["place-name"].waitForExistence(timeout: 20), "no place for quality audit")
    }

    func qualityRevealElement(_ element: XCUIElement, in scroll: XCUIElement,
                              app: XCUIApplication) -> Bool {
        // Check existence and an on-screen frame before isHittable. Querying that property for an
        // offscreen accessibility-sized element can otherwise fail the whole UI test query.
        for step in 0..<24 {
            if qualityHittable(element, in: app) { return true }
            qualityRevealTrace(element, direction: "up", step: step)
            qualityDrag(scroll, up: true)
            usleep(400_000)
        }
        for step in 0..<30 {
            if qualityHittable(element, in: app) { return true }
            qualityRevealTrace(element, direction: "down", step: step)
            qualityDrag(scroll, up: false)
            usleep(400_000)
        }
        let reachable = qualityHittable(element, in: app)
        if !reachable {
            let id = element.exists ? element.identifier : "missing"
            let frame = element.exists ? "\(element.frame)" : "missing"
            print("QUALITY_REVEAL_FAILED id=\(id) frame=\(frame) scroll=\(scroll.frame)")
        }
        return reachable
    }

    private func qualityDrag(_ scroll: XCUIElement, up: Bool) {
        // A full swipe jumps about 700 points and can skip a 44-point target between two snapshots.
        let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.85 : 0.15))
        let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.15 : 0.85))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func qualityRevealTrace(_ element: XCUIElement, direction: String, step: Int) {
        guard element.exists, element.identifier == "place-directions" else { return }
        let frame = element.exists ? "\(element.frame)" : "missing"
        print("QUALITY_REVEAL_DIRECTIONS direction=\(direction) step=\(step) frame=\(frame)")
    }

    func qualityHittable(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        guard element.exists else { return false }
        let frame = element.frame
        guard frame.width > 0, frame.height > 0, app.frame.intersects(frame) else { return false }
        return element.isHittable
    }

    func qualityOpenRoute(_ app: XCUIApplication, query: String) {
        qualityOpenPlace(app, query: query)
        let directions = app.buttons["place-directions"]
        let scroll = app.scrollViews["place-scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 15))
        let reachable = qualityRevealElement(directions, in: scroll, app: app)
        if !reachable { shot("quality-directions-unreachable") }
        XCTAssertTrue(reachable, "Directions is not reachable")
        directions.tap()
        XCTAssertTrue(app.buttons["route-mode-DRIVE"].waitForExistence(timeout: 15))
        if qualityValue("mode") != "DRIVE" { app.buttons["route-mode-DRIVE"].tap() }
    }

    func qualityOpenSettings(_ app: XCUIApplication) {
        app.buttons["map-overflow"].tap()
        XCTAssertTrue(app.buttons["settings-menu-item"].waitForExistence(timeout: 5))
        app.buttons["settings-menu-item"].tap()
        XCTAssertTrue(app.staticTexts["settings-debug"].waitForExistence(timeout: 15))
    }

    func qualityOfflineMapAndSearch(_ app: XCUIApplication) {
        app.buttons["map-overflow"].tap()
        XCTAssertTrue(app.buttons["offline-menu-item"].waitForExistence(timeout: 5))
        app.buttons["offline-menu-item"].tap()
        let filter = app.textFields["offline-filter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 30))
        filter.tap()
        filter.typeText("Monaco")
        if app.keyboards.buttons["return"].exists { app.keyboards.buttons["return"].tap() }
        let download = app.buttons["offline-download-monaco"]
        let installed = app.staticTexts["offline-installed-monaco"]
        if download.waitForExistence(timeout: 10) {
            download.tap()
            XCTAssertTrue(app.progressIndicators["offline-progress"].waitForExistence(timeout: 20))
            XCTAssertTrue(installed.waitForExistence(timeout: 300))
            XCTAssertTrue(app.staticTexts["offline-ready"].waitForExistence(timeout: 60))
            XCTAssertTrue(waitUntil(30) { !app.progressIndicators["offline-progress"].exists })
        } else {
            XCTAssertTrue(installed.waitForExistence(timeout: 30), "Monaco is neither installed nor downloadable")
        }
        let block = app.buttons["offline-test-block"]
        for _ in 0..<4 where !block.isHittable { app.tables.firstMatch.swipeDown() }
        XCTAssertTrue(block.waitForExistence(timeout: 5))
        block.tap()
        app.buttons["offline-done"].tap()
        XCTAssertTrue(waitUntil(60) {
            self.debugText("offline-map-debug")?.contains("archive=monaco.pmtiles remote=0") == true
        })
        qualitySearch(app, query: "Casino de Monte Carlo")
        XCTAssertTrue(waitUntil(10) { self.debugText("search-debug")?.contains("offline=1") == true })
    }

    func qualityEndNavigation() {
        guard let app else { return }
        let end = app.buttons["nav-end"]
        guard end.exists else { return }
        end.tap()
        let confirm = app.buttons["nav-end-confirm"].firstMatch
        if confirm.waitForExistence(timeout: 5) {
            confirm.tap()
            _ = waitUntil(10) { self.qualityValue("nav", debugID: "nav-debug") == "0" }
        }
    }

    func qualityValue(_ key: String, debugID: String = "route-debug") -> String? {
        guard let line = debugText(debugID) else { return nil }
        for part in line.split(separator: " ") where part.hasPrefix("\(key)=") {
            return String(part.dropFirst(key.count + 1))
        }
        return nil
    }

    func qualityKey(_ id: String) -> String {
        id.lowercased().replacingOccurrences(of: "-", with: "_")
    }

    func qualityAppIdentifier(_ id: String) -> Bool {
        let prefixes = [
            "search-", "map-", "place-", "route-", "step-", "settings-", "saved-", "offline-",
            "nav-", "category-", "parking-",
        ]
        return prefixes.contains { id.hasPrefix($0) }
    }
}
