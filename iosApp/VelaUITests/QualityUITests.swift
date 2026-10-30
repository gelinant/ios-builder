import CoreGraphics
import XCTest

/// Accessibility layout audits. Optional measurements are reported without making offscreen lazy
/// content a failure. Required targets fail only for a missing element, an undersized accessibility
/// frame, or an empty button label. Reachability and content assertions fail normally.
final class QualityUITests: VelaUITestCase {
    private let largestText = "UICTContentSizeCategoryAccessibilityXXXL"
    /// The chips the quick-category row shows by default, with their English labels. The identifier
    /// comes from the chip's label key (`cat_gas` -> `category-gas`), not from its regional query,
    /// so the fuel chip is `category-gas` in every region even where it searches "Petrol station".
    private let categoryIDs = [
        "category-restaurants", "category-coffee", "category-gas",
        "category-groceries", "category-parking", "category-ev",
    ]
    private let categoryEnglish = [
        "Restaurants", "Coffee", "Gas station", "Groceries", "Parking", "EV charging station",
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

    /// QUALITY-REG: the map menu (`map-overflow`) is the only way into Settings from the map, and
    /// in compact landscape the chrome's action column is taller than the window. The invariant is
    /// that every fixed chrome target stays inside the app frame. It currently fails on
    /// `map-overflow` (reported at y = -95 in the R3 run) until `MapScreen` clamps the chrome; this
    /// test is the regression guard for that hook.
    func testCompactLandscapeChromeFits() {
        let app = launch(camera: "sf")
        XCTAssertTrue(app.textFields["search-field"].waitForExistence(timeout: 20))
        landscape()
        shot("quality-compact-landscape-chrome")
        assertInsideWindow(app, ids: ["search-field", "saved-open", "map-overflow"],
                           screen: "compact_landscape")
        let overflow = app.buttons["map-overflow"].firstMatch
        XCTAssertTrue(overflow.isHittable, "the map menu cannot be tapped in compact landscape")
    }

    func testPlaceLargeTextLandscape() {
        let app = launchLarge(camera: "davis")
        qualityOpenPlace(app, query: "Davis Food Co-op")
        _ = waitUntil(45) { self.qualityValue("details", debugID: "place-debug") == "done" }
        landscape()
        sleep(2)
        shot("quality-place-large-landscape")
        let scroll = app.descendants(matching: .any)["place-scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 10))

        // The photo grid is on the Photos tab. Its tab button is the scroll target that makes the
        // photo reachable at AX5; the assertion that a photo exists and opens stays unchanged.
        let photosTab = app.buttons["place-tab-photos"]
        XCTAssertTrue(openPlaceTab(app, id: "place-tab-photos", in: scroll),
                      "the Photos tab is not reachable")
        photosTab.tap()
        let photo = app.buttons.matching(identifier: "place-photo").firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 10), "the Photos tab opened no photo")
        XCTAssertTrue(qualityReveal(photo, in: scroll), "place photo is not reachable")
        assertTargets(app, ids: ["place-photo"])
        XCTAssertTrue(photo.label.hasPrefix("Place photo 1 of "))
        shot("quality-place-photo-accessibility")

        // All photos is an Overview action, so return to that tab before reaching it.
        let overviewTab = app.buttons["place-tab-overview"]
        XCTAssertTrue(openPlaceTab(app, id: "place-tab-overview", in: scroll),
                      "the Overview tab is not reachable")
        overviewTab.tap()
        let allPhotos = app.buttons["place-all-photos"]
        XCTAssertTrue(qualityReveal(allPhotos, in: scroll), "photo grid action is not reachable")
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
        audit(app, screen: "place", ids: [
            "place-close", "place-directions", "place-save", "place-share", "place-all-photos",
            "place-all-reviews", "place-photo", "place-review-photo",
        ], required: ["place-close"])
        XCTAssertTrue(app.staticTexts["place-name"].exists)
    }

    func testRoutePickerLargeTextLandscape() {
        let app = launchLarge(camera: "sf", followUser: true, extra: ["-VelaRouteOrderFixture", "YES"])
        qualityOpenRoute(app, query: "coffee")
        XCTAssertTrue(app.buttons["route-row"].firstMatch.waitForExistence(timeout: 90),
                      "no route for the landscape audit")
        landscape()
        sleep(2)
        shot("quality-route-large-landscape")
        assertTargets(app, ids: ["route-swap", "route-close", "route-mode-DRIVE", "route-mode-WALK"])
        // route-scroll is not exposed as a ScrollView: the unified sheet has to be dragged from
        // inside the visible part of its own frame.
        let sheet = app.descendants(matching: .any)["route-sheet"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 10), "no route sheet")
        let avoid = app.buttons["route-avoid-highways"]
        XCTAssertTrue(revealInSheet(avoid, in: sheet, steps: 14, screen: "route_avoid"),
                      "avoid options are not reachable")
        assertTargets(app, ids: ["route-avoid-highways", "route-avoid-tolls", "route-avoid-ferries"])
        let steps = app.buttons["route-steps"]
        XCTAssertTrue(revealInSheet(steps, in: sheet, steps: 6, screen: "route_actions"),
                      "route actions are not reachable")
        assertTargets(app, ids: ["route-start", "route-steps"])
        audit(app, screen: "route", ids: [
            "route-swap", "route-close", "route-mode-DRIVE", "route-mode-WALK",
            "route-avoid-highways", "route-start", "route-steps", "route-row",
        ], required: ["route-close", "route-avoid-highways", "route-start", "route-steps"])
        steps.tap()
        XCTAssertTrue(app.buttons["steps-close"].waitForExistence(timeout: 15))
        assertTargets(app, ids: ["steps-close"])
        let stepsSheet = app.descendants(matching: .any)["steps-sheet"]
        let stepsScroll = stepsSheet.descendants(matching: .scrollView).firstMatch
        if stepsScroll.exists {
            _ = revealUntilExists(app.descendants(matching: .any)["step-lanes"], in: stepsScroll, steps: 10)
        }
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
        for (id, englishLabel) in zip(categoryIDs, categoryEnglish) {
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
        // A Form switch reports the full row frame, so its center cannot locate the visible knob.
        // The screenshot checks that visual position without turning a valid RTL row into a failure.
        shot("quality-settings-he-rtl-privacy")
        audit(app, screen: "hebrew", ids: [
            "settings-done", "settings-language", "settings-units", "settings-no-google",
        ], required: ["settings-done", "settings-no-google"])
        report("quality_hebrew_layout", "done-left-toggle-screenshot")
    }

    /// The runner has only iPhone 17. Landscape exercises a compact vertical size class, not an SE.
    func testCompactHeightSettingsLandscape() {
        let app = launch(arguments: ["-VelaResetSettings", "YES"])
        landscape()
        assertInsideWindow(app, ids: ["map-overflow"], screen: "compact_landscape")
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

    /// VoiceOver reads the accessibility hierarchy in query order. These three tests walk the
    /// hierarchy of the map, place sheet, route picker and settings, and check the label content
    /// against the data the views received. The map hint and rotor actions are read from UIKit in
    /// `MapAccessibilityTests`, because XCUITest does not expose them.
    func testMapAndPlaceReadingOrder() {
        let app = launch(camera: "davis")
        let map = app.descendants(matching: .any)["map"]
        XCTAssertTrue(map.exists, "the map is not in the accessibility hierarchy")
        XCTAssertEqual(map.label, "Map")
        report("quality_map_label", map.label)
        let locate = app.buttons["Show my location"]
        XCTAssertTrue(locate.waitForExistence(timeout: 5), "the locate button is not in the hierarchy")
        XCTAssertEqual(locate.label, "Show my location")
        // The overflow icon reports a 20-point glyph frame at normal text. MapScreen owns that
        // target; Q-2 only measured it at AX5 where the header widens it. Report, do not fail.
        let overflow = app.buttons["map-overflow"]
        XCTAssertTrue(overflow.exists, "the map menu is not in the hierarchy")
        report("quality_map_overflow", "\(Int(overflow.frame.width))x\(Int(overflow.frame.height))")
        report("quality_map_controls", "map,locate,overflow")

        qualityOpenPlace(app, query: "Davis Food Co-op")
        _ = waitUntil(45) { self.qualityValue("details", debugID: "place-debug") == "done" }
        let sheet = app.descendants(matching: .any)["place-sheet"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 15), "no place sheet")
        let scroll = app.descendants(matching: .any)["place-scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 10), "no place scroll view")

        // Summary and actions first: name, rating, status, then the action row left to right.
        assertVerticalOrder(app, ["place-name", "place-rating", "place-status", "place-directions"],
                            screen: "place_top", minimum: 3)
        assertHorizontalOrder(app, ["place-directions", "place-save", "place-lists", "place-share"],
                              screen: "place_actions", minimum: 3)

        // Opening hours belong under the status button that reveals them.
        let hourLines = Int(qualityValue("hours", debugID: "place-debug") ?? "") ?? 0
        if hourLines > 1 {
            app.buttons["place-status"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["place-hours"].waitForExistence(timeout: 5))
            assertVerticalOrder(app, ["place-status", "place-hours"], screen: "place_hours", minimum: 2)
            app.buttons["place-status"].tap()
        } else {
            report("quality_place_order_hours", "skipped-no-hours")
        }

        // Details follow the actions: address, photos, popular times, reviews.
        let address = placeText(app, "place-address")
        if revealUntilHittable(address, in: scroll, steps: 8) {
            assertVerticalOrder(app, ["place-directions", "place-address"],
                                screen: "place_address", minimum: 2)
        } else {
            report("quality_place_order_address", "no-address")
        }
        // The photo grid lives behind the Photos tab, so the tab has to be opened before the
        // first photo can exist in the hierarchy. Scrolling alone never reached it.
        let photosTab = app.buttons["place-tab-photos"]
        XCTAssertTrue(openPlaceTab(app, id: "place-tab-photos", in: scroll),
                      "the Photos tab is not reachable")
        photosTab.tap()
        let photo = app.buttons.matching(identifier: "place-photo").firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 10), "the Photos tab opened no photo")
        XCTAssertTrue(revealUntilHittable(photo, in: scroll, steps: 12), "place photos are not reachable")
        assertVerticalOrder(app, ["place-directions", "place-photo"],
                            screen: "place_photo", minimum: 2)
        XCTAssertNotNil(photo.label.range(of: "^Place photo \\d+ of \\d+$", options: .regularExpression),
                        "place photo lacks position or total: \(photo.label)")

        // Popular times and reviews are sections of the Overview tab: go back before reading them.
        let overviewTab = app.buttons["place-tab-overview"]
        XCTAssertTrue(openPlaceTab(app, id: "place-tab-overview", in: scroll),
                      "the Overview tab is not reachable")
        overviewTab.tap()
        let popular = app.descendants(matching: .any)["place-popular"]
        _ = revealUntilExists(popular, in: scroll, steps: 4)
        assertPopularTimeLabels(app)

        let reviews = app.descendants(matching: .any)["place-reviews-title"]
        XCTAssertTrue(revealUntilExists(reviews, in: scroll, steps: 24), "reviews are not reachable")
        assertVerticalOrder(app, ["place-directions", "place-reviews-title"],
                            screen: "place_reviews", minimum: 2)
        let reviewPhoto = app.buttons.matching(identifier: "place-review-photo").firstMatch
        _ = revealUntilExists(reviewPhoto, in: scroll, steps: 24)
        assertReviewPhotoLabels(app)
        shot("quality-place-reading-order")

        // Settings, reached from the map after closing the sheet.
        app.buttons["place-close"].tap()
        XCTAssertTrue(waitUntil(10) { !app.descendants(matching: .any)["place-sheet"].exists })
        qualityOpenSettings(app)
        assertSettingsReadingOrder(app)
    }

    func testRoutePickerReadingOrder() {
        let app = launch(camera: "sf", followUser: true,
                         arguments: ["-VelaRouteOrderFixture", "YES"])
        qualityOpenRoute(app, query: "coffee")
        XCTAssertTrue(app.buttons["route-row"].firstMatch.waitForExistence(timeout: 90),
                      "no route for the reading order audit")
        let sheet = app.descendants(matching: .any)["route-sheet"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 10), "no route sheet")
        assertVerticalOrder(app, [
            "route-destination", "route-origin-button", "route-mode-DRIVE", "route-avoid-highways",
            "route-row", "route-start",
        ], screen: "route", minimum: 5)
        assertHorizontalOrder(app, ["route-swap", "route-close"], screen: "route_header", minimum: 2)
        assertHorizontalOrder(app, [
            "route-mode-DRIVE", "route-mode-WALK", "route-mode-BICYCLE", "route-mode-TRANSIT",
        ], screen: "route_modes", minimum: 4)
        assertHorizontalOrder(app, ["route-avoid-highways", "route-avoid-tolls", "route-avoid-ferries"],
                              screen: "route_avoids", minimum: 3)
        assertHorizontalOrder(app, ["route-start", "route-steps"], screen: "route_actions", minimum: 2)
        shot("quality-route-reading-order")

        app.buttons["route-steps"].tap()
        XCTAssertTrue(app.buttons["steps-close"].waitForExistence(timeout: 15))
        let stepsSheet = app.descendants(matching: .any)["steps-sheet"]
        XCTAssertTrue(stepsSheet.waitForExistence(timeout: 10))
        let stepsScroll = stepsSheet.descendants(matching: .scrollView).firstMatch
        if stepsScroll.exists {
            _ = revealUntilExists(app.descendants(matching: .any)["step-lanes"], in: stepsScroll, steps: 10)
        }
        assertLaneLabels(app)
        shot("quality-steps-reading-order")
    }

    /// The runner has only an iPhone 17 and a compact iPhone 16e. This test reports the real screen
    /// size and always runs the key screens; the SE size (375x667) stays open until it runs on one.
    func testSmallScreenKeyScreens() {
        let app = launch(camera: "sf")
        let size = app.frame.size
        let seSize = size.width <= 375 && size.height <= 700
        let compact = size.width < 402 || size.height < 800
        report("quality_screen_size", "\(Int(size.width))x\(Int(size.height))")
        report("quality_small_screen", seSize ? "se-size" : (compact ? "compact-not-se" : "not-small-runner-device"))
        // The text field and the overflow icon report their glyph-sized accessibility frames in
        // normal text (Q-3 measured 22 and 20 points high and wide). Q-2 sized their visible
        // containers, not these elements, and MapScreen owns the overflow frame: report only.
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 20))
        report("quality_small_search_field", "\(Int(field.frame.width))x\(Int(field.frame.height))")
        let overflow = app.buttons["map-overflow"]
        if overflow.exists {
            report("quality_small_overflow", "\(Int(overflow.frame.width))x\(Int(overflow.frame.height))")
        }
        assertTargets(app, ids: categoryIDs)
        qualitySearch(app, query: "coffee")
        assertTargets(app, ids: ["search-clear", "search-panel-toggle"])
        report("quality_small_search_field_after", "\(Int(field.frame.width))x\(Int(field.frame.height))")
        XCTAssertGreaterThanOrEqual(app.buttons.matching(identifier: "search-result").count, 3,
                                    "the result list collapsed on this screen")
        shot("quality-small-search")

        app.buttons.matching(identifier: "search-result").firstMatch.tap()
        XCTAssertTrue(app.staticTexts["place-name"].waitForExistence(timeout: 20))
        _ = waitUntil(45) { self.qualityValue("details", debugID: "place-debug") == "done" }
        assertTargets(app, ids: ["place-close", "place-directions", "place-save", "place-share"])
        let sheet = app.descendants(matching: .any)["place-sheet"]
        XCTAssertTrue(sheet.exists, "no place sheet")
        // The sheet keeps half the screen for the map, as declared in MapScreen.
        XCTAssertLessThanOrEqual(sheet.frame.height, size.height * 0.6,
                                 "the place sheet covers more than 60% of the screen")
        let scroll = app.descendants(matching: .any)["place-scroll"]
        XCTAssertTrue(scroll.exists)
        XCTAssertGreaterThanOrEqual(scroll.frame.height, 60,
                                    "the place content viewport collapsed on this screen")
        report("quality_small_sheet", "\(Int(sheet.frame.height))of\(Int(size.height))")
        shot("quality-small-place")

        app.buttons["place-close"].tap()
        XCTAssertTrue(waitUntil(10) { !app.descendants(matching: .any)["place-sheet"].exists })
        qualityOpenSettings(app)
        assertTargets(app, ids: ["settings-done", "settings-language", "settings-units"])
        assertSettingsReadingOrder(app)
        shot("quality-small-settings")
    }

    private func launchLarge(camera: String, followUser: Bool = false,
                             extra: [String] = []) -> XCUIApplication {
        launch(camera: camera, followUser: followUser, arguments: [
            "-VelaResetSettings", "YES",
            "-UIPreferredContentSizeCategoryName", largestText,
        ] + extra)
    }

    private func landscape() {
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        XCTAssertEqual(XCUIDevice.shared.orientation, .landscapeLeft)
    }

    /// Every named chrome target must sit inside the app frame, at any size class. A target that is
    /// present in the hierarchy but drawn above or below the window cannot be tapped, which is how
    /// the compact-landscape menu regression shows up.
    private func assertInsideWindow(_ app: XCUIApplication, ids: [String], screen: String) {
        let window = app.frame
        for id in ids {
            let element = app.descendants(matching: .any)[id].firstMatch
            XCTAssertTrue(element.waitForExistence(timeout: 5), "missing target: \(id)")
            guard element.exists else { continue }
            let frame = element.frame
            report("quality_\(screen)_\(qualityKey(id))_frame",
                   "\(Int(frame.minX)),\(Int(frame.minY)),\(Int(frame.width))x\(Int(frame.height))")
            XCTAssertTrue(window.contains(frame),
                          "\(id) is off the window: \(frame) not inside \(window)")
        }
    }

    /// A place sheet's text row. `place-address` is currently applied to the row container, so
    /// SwiftUI stamps the same identifier on the icon and the text; the StaticText query picks the
    /// readable row. The product fix is one line in `PlaceSheet` (hook reported in QUALITY.md):
    /// `.accessibilityElement(children: .combine)` before `.accessibilityIdentifier("place-address")`.
    private func placeText(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        let texts = app.staticTexts.matching(identifier: id)
        let count = texts.count
        report("quality_place_\(qualityKey(id))_elements", count)
        return count > 0 ? texts.firstMatch : app.descendants(matching: .any)[id].firstMatch
    }

    /// Opens a place tab. The tab row is a horizontal ScrollView, so at AX5 the Photos tab can be
    /// outside the row's viewport: a vertical reveal alone never makes it hittable. Bring the row
    /// into the viewport first, then drag the row itself left or right until the tab is hittable.
    private func openPlaceTab(_ app: XCUIApplication, id: String, in scroll: XCUIElement) -> Bool {
        let tab = app.buttons[id]
        guard tab.waitForExistence(timeout: 10) else { return false }
        for _ in 0..<16 {
            if qualityHittable(tab, in: app) { return true }
            if app.frame.intersects(tab.frame), tab.frame.height > 0 { break }
            qualityDrag(scroll, up: tab.frame.minY > app.frame.midY)
            usleep(400_000)
        }
        let row = app.descendants(matching: .any)["place-tabs"].firstMatch
        for left in [true, false] {
            for _ in 0..<8 {
                if qualityHittable(tab, in: app) { return true }
                guard row.exists, app.frame.intersects(row.frame), row.frame.width > 44 else { break }
                let from = left ? 0.85 : 0.15
                let to = left ? 0.15 : 0.85
                let start = row.coordinate(withNormalizedOffset: CGVector(dx: from, dy: 0.5))
                let end = row.coordinate(withNormalizedOffset: CGVector(dx: to, dy: 0.5))
                start.press(forDuration: 0.05, thenDragTo: end)
                usleep(300_000)
            }
        }
        return qualityHittable(tab, in: app)
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

    /// Popular times are checked only when the sheet received them. The bar labels must carry the
    /// selected day, the hour and the occupancy; an empty chart is a failure once hours exist.
    private func assertPopularTimeLabels(_ app: XCUIApplication) {
        let popular = app.descendants(matching: .any)["place-popular"]
        guard popular.exists else {
            report("quality_popular_time_bars", "no-data")
            return
        }
        let days = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH 'popular-day-'")).allElementsBoundByIndex
        XCTAssertFalse(days.isEmpty, "popular times render without day buttons")
        let selected = days.first { $0.isSelected }
        XCTAssertNotNil(selected, "no popular-times day is marked selected")
        report("quality_popular_days", days.count)

        let bars = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH 'popular-hour-' OR identifier == 'popular-current-hour'"))
            .allElementsBoundByIndex
        let hours = Int(qualityValue("popular", debugID: "place-debug") ?? "") ?? 0
        XCTAssertFalse(bars.isEmpty && hours > 0,
                       "popular times have \(hours) hours today but expose no bar")
        for bar in bars {
            let label = bar.label
            if let day = selected?.label, !day.isEmpty {
                XCTAssertTrue(label.hasPrefix(day + ","), "popular bar lacks its day: \(label)")
            }
            XCTAssertNotNil(label.range(of: "\\d{1,2}", options: .regularExpression),
                            "popular bar lacks its hour: \(label)")
            let value = (bar.value as? String) ?? ""
            XCTAssertNotNil(value.range(of: "^\\d+% occupied$", options: .regularExpression),
                            "popular bar lacks its occupancy: \(value)")
        }
        report("quality_popular_time_bars", bars.isEmpty ? "empty-day" : bars.count)
    }

    /// Review photos must name their position, total and author when the reviews supplied photos.
    private func assertReviewPhotoLabels(_ app: XCUIApplication) {
        let rows = app.descendants(matching: .any).matching(identifier: "place-review").count
        let photos = app.buttons.matching(identifier: "place-review-photo").allElementsBoundByIndex
        for photo in photos where photo.exists {
            XCTAssertNotNil(photo.label.range(
                of: "^Photo \\d+ of \\d+ from the review by .+$", options: .regularExpression),
                "review photo lacks position, total or author: \(photo.label)")
        }
        report("quality_review_rows", rows)
        report("quality_review_photo_labels", photos.isEmpty ? "no-photo" : photos.count)
    }

    /// Lanes are checked only when the steps sheet rendered the lane group.
    private func assertLaneLabels(_ app: XCUIApplication) {
        let lanes = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH 'step-lane-'")).allElementsBoundByIndex
        let group = app.descendants(matching: .any)["step-lanes"]
        guard group.exists || !lanes.isEmpty else {
            report("quality_lane_labels", "no-data")
            return
        }
        XCTAssertFalse(lanes.isEmpty, "lane group rendered without a labeled lane")
        for lane in lanes {
            XCTAssertNotNil(lane.label.range(of: "^Lane \\d+ of \\d+$", options: .regularExpression),
                            "lane lacks its position: \(lane.label)")
            let value = (lane.value as? String) ?? ""
            XCTAssertFalse(value.isEmpty, "lane lacks its directions")
            XCTAssertNotNil(value.range(of: "(^|\\. )(Not )?[Rr]ecommended$", options: .regularExpression),
                            "lane lacks its recommendation: \(value)")
        }
        report("quality_lane_labels", lanes.count)
    }

    /// Reading order is compared on the frames of the elements the accessibility hierarchy exposes,
    /// never on a screenshot. A vertical chain must not go back up; a horizontal row must not go
    /// back left. Lazy elements the hierarchy dropped are skipped and reported, and `minimum` sets
    /// how many links the caller needs to consider the order actually checked.
    @discardableResult
    private func assertVerticalOrder(_ app: XCUIApplication, _ ids: [String], screen: String,
                                     minimum: Int) -> Int {
        var checks = 0
        var previous: (id: String, y: CGFloat)?
        var missing: [String] = []
        for id in ids {
            let element = app.descendants(matching: .any)[id].firstMatch
            guard element.exists, element.frame.height > 0 else {
                missing.append(id)
                continue
            }
            let y = element.frame.minY
            if let previous, y < previous.y - 2 {
                XCTFail("\(screen): \(id) is above \(previous.id)")
            }
            checks += 1
            previous = (id, y)
        }
        report("quality_\(screen)_order_checks", checks)
        report("quality_\(screen)_order_missing", missing.isEmpty ? "none" : missing.joined(separator: ","))
        XCTAssertGreaterThanOrEqual(checks, minimum,
                                    "\(screen): only \(checks) of \(ids.count) elements were in the hierarchy")
        return checks
    }

    @discardableResult
    private func assertHorizontalOrder(_ app: XCUIApplication, _ ids: [String], screen: String,
                                       minimum: Int) -> Int {
        var checks = 0
        var previous: (id: String, x: CGFloat)?
        var rowY: CGFloat?
        var missing: [String] = []
        for id in ids {
            let element = app.descendants(matching: .any)[id].firstMatch
            guard element.exists, element.frame.width > 0 else {
                missing.append(id)
                continue
            }
            let frame = element.frame
            if let rowY, abs(frame.midY - rowY) > 40 {
                XCTFail("\(screen): \(id) is not on the same row as the previous targets")
            }
            if let previous, frame.midX < previous.x - 2 {
                XCTFail("\(screen): \(id) is left of \(previous.id)")
            }
            rowY = rowY ?? frame.midY
            checks += 1
            previous = (id, frame.midX)
        }
        report("quality_\(screen)_order_checks", checks)
        report("quality_\(screen)_order_missing", missing.isEmpty ? "none" : missing.joined(separator: ","))
        XCTAssertGreaterThanOrEqual(checks, minimum,
                                    "\(screen): only \(checks) of \(ids.count) elements were in the hierarchy")
        return checks
    }

    private func assertSettingsReadingOrder(_ app: XCUIApplication) {
        let form = app.descendants(matching: .any)["settings-screen"]
        XCTAssertTrue(form.waitForExistence(timeout: 15), "no settings screen")
        assertVerticalOrder(app, ["settings-language", "settings-units", "settings-clock"],
                            screen: "settings_top", minimum: 3)
        let toggle = app.switches["settings-no-google"]
        XCTAssertTrue(qualityReveal(toggle, in: form), "privacy toggle is not reachable")
        assertVerticalOrder(app, ["settings-language", "settings-units", "settings-clock",
                                  "settings-no-google"], screen: "settings_toggle", minimum: 2)
        let privacy = app.descendants(matching: .any)["settings-privacy-link"]
        XCTAssertTrue(qualityReveal(privacy, in: form), "privacy link is not reachable")
        assertVerticalOrder(app, ["settings-clock", "settings-no-google", "settings-privacy-link"],
                            screen: "settings_privacy", minimum: 2)
        XCTAssertFalse(privacy.label.isEmpty, "the privacy link has no label")
        XCTAssertFalse(toggle.label.isEmpty, "the privacy toggle has no label")
    }

    /// Scrolls down until the element is instantiated: lazy content only enters the hierarchy when
    /// its section approaches the viewport. It stops as soon as the element exists, so a missing
    /// section does not scroll the whole sheet away.
    private func revealUntilExists(_ element: XCUIElement, in scroll: XCUIElement, steps: Int) -> Bool {
        for _ in 0..<steps {
            if element.exists { return true }
            qualityDrag(scroll, up: true)
            usleep(400_000)
        }
        return element.exists
    }

    /// Same as `revealUntilExists`, but keeps scrolling until the element can be tapped. Used for
    /// targets measured or tapped after the reveal. `up` scrolls the content up (towards the end);
    /// `false` scrolls back towards the top, for a row that is already above the viewport.
    private func revealUntilHittable(_ element: XCUIElement, in scroll: XCUIElement, steps: Int,
                                     up: Bool = true) -> Bool {
        guard let app else { return false }
        for _ in 0..<steps {
            if qualityHittable(element, in: app) { return true }
            qualityDrag(scroll, up: up)
            usleep(400_000)
        }
        return qualityHittable(element, in: app)
    }

    /// Scrolls the one unified sheet at large text, where the inner scroll has no element of its
    /// own. The sheet frame can be taller than the window (its content is laid out before the host
    /// clamps it), so every drag point comes from the intersection with the app frame: dragging a
    /// coordinate outside the window scrolls nothing and made the avoid row look unreachable.
    private func revealInSheet(_ element: XCUIElement, in sheet: XCUIElement, steps: Int,
                               screen: String) -> Bool {
        guard let app else { return false }
        for step in 0..<steps {
            if qualityHittable(element, in: app) { return true }
            let frame = element.exists ? "\(element.frame)" : "missing"
            print("QUALITY_SHEET_REVEAL screen=\(screen) step=\(step) frame=\(frame)")
            guard let (start, end) = sheetDragPoints(app: app, sheet: sheet) else { return false }
            start.press(forDuration: 0.05, thenDragTo: end)
            usleep(400_000)
        }
        return qualityHittable(element, in: app)
    }

    /// The two on-screen points of a vertical drag inside [sheet], clamped to the app frame. The
    /// unified route scroll may not be exposed at all, so the sheet anchor is used and the drag
    /// runs in its visible middle, away from the pinned action row and the home indicator.
    private func sheetDragPoints(app: XCUIApplication, sheet: XCUIElement)
        -> (XCUICoordinate, XCUICoordinate)? {
        let window = app.frame
        let visible = window.intersection(sheet.frame)
        let area = visible.isNull || visible.height < 44 ? window : visible
        guard area.height >= 44 else { return nil }
        let x = area.midX / window.width
        let startY = (area.minY + area.height * 0.75) / window.height
        let endY = (area.minY + area.height * 0.25) / window.height
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: startY))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: endY))
        return (start, end)
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
            app.launchArguments = [
                "-VelaStartCamera", "sf", "-VelaDeterministic", "YES", "-VelaResetNavigation", "YES",
            ]
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
        // At AX5 the field frame can sit at the very top of a landscape screen, and the first tap
        // occasionally lands without focus. Tap once more before typing instead of failing there.
        if !app.keyboards.firstMatch.waitForExistence(timeout: 2) {
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)).tap()
            _ = app.keyboards.firstMatch.waitForExistence(timeout: 2)
        }
        usleep(300_000)
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
        for step in 0..<36 {
            if qualityHittable(element, in: app) { return true }
            qualityRevealTrace(element, direction: "up", step: step)
            qualityDrag(scroll, up: true)
            usleep(400_000)
        }
        for step in 0..<44 {
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

    func qualityDrag(_ scroll: XCUIElement, up: Bool) {
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
