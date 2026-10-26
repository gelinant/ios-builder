import CoreGraphics
import XCTest

/// Accessibility layout audits. Small targets and empty labels are reported as a baseline instead
/// of failing the whole CI job; the measured defects and their screenshots are tracked in
/// docs/ios/QUALITY.md. Screen-opening and content assertions still fail normally. Debug status
/// labels scale too, so compact-height failures need a Release or hidden-debug confirmation.
final class QualityUITests: VelaUITestCase {
    private let largestText = "UICTContentSizeCategoryAccessibilityXXXL"

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    func testSearchLargeTextLandscape() {
        let app = launchLarge(camera: "sf")
        landscape()
        shot("quality-map-large-landscape")
        qualitySearch(app, query: "coffee")
        sleep(2)
        shot("quality-search-large-landscape")
        audit(app, screen: "search", ids: [
            "search-field", "search-clear", "map-overflow", "search-panel-toggle", "search-result",
        ])
        XCTAssertTrue(app.buttons["search-panel-toggle"].exists)
    }

    func testPlaceLargeTextLandscape() {
        let app = launchLarge(camera: "davis")
        qualityOpenPlace(app, query: "Davis Food Co-op")
        _ = waitUntil(45) { self.qualityValue("details", debugID: "place-debug") == "done" }
        landscape()
        sleep(2)
        shot("quality-place-large-landscape")
        audit(app, screen: "place", ids: [
            "place-close", "place-directions", "place-save", "place-share", "place-all-photos",
            "place-all-reviews", "place-photo", "place-review-photo",
        ])
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
        audit(app, screen: "route", ids: [
            "route-swap", "route-close", "route-mode-DRIVE", "route-mode-WALK",
            "route-avoid-highways", "route-start", "route-steps", "route-row",
        ])
        XCTAssertTrue(app.buttons["route-close"].exists)
    }

    func testSettingsLargeTextLandscape() {
        let app = launchLarge(camera: "sf")
        qualityOpenSettings(app)
        landscape()
        sleep(2)
        shot("quality-settings-large-landscape")
        audit(app, screen: "settings", ids: [
            "settings-done", "settings-language", "settings-units", "settings-clock",
            "settings-no-google", "settings-privacy-link",
        ])
        XCTAssertTrue(app.staticTexts["settings-debug"].exists)
    }

    func testHebrewRightToLeft() {
        let app = launch(arguments: ["-VelaResetSettings", "YES", "-VelaLanguage", "he"])
        sleep(2)
        shot("quality-search-he-rtl")
        XCTAssertNotEqual(app.textFields["search-field"].placeholderValue, "Search")
        qualityOpenSettings(app)
        shot("quality-settings-he-rtl")
        audit(app, screen: "hebrew", ids: [
            "settings-done", "settings-language", "settings-units", "settings-no-google",
        ])
        report("quality_hebrew_layout", "screenshots")
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

    private func audit(_ app: XCUIApplication, screen: String, ids: [String]) {
        var small: [String] = []
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
            if element.isHittable && (frame.width < 44 || frame.height < 44) {
                small.append("\(id):\(size)")
            }
        }
        // Asking isHittable for an offscreen accessibility-sized button can itself fail the
        // query. Enabled buttons are enough for this label audit; reachability is checked above.
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

    func qualityOpenRoute(_ app: XCUIApplication, query: String) {
        qualityOpenPlace(app, query: query)
        let directions = app.buttons["place-directions"]
        XCTAssertTrue(directions.waitForExistence(timeout: 15))
        let scroll = app.scrollViews["place-scroll"]
        for _ in 0..<6 where !directions.isHittable { scroll.swipeUp() }
        XCTAssertTrue(directions.isHittable, "Directions is not reachable")
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
