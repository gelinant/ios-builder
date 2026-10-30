import XCTest

/// P-1 end to end on the Davis fixture: complete gallery, full reviews, popular-times fallback,
/// and the decoded avatar pixels. The runner's datacenter address may limit every Google source;
/// paging beyond five is asserted only when Google serves another review.
final class PlaceUITests: VelaUITestCase {
    func testCompleteFixturePlace() throws {
        let app = launch(camera: "davis")
        let searchField = app.textFields["search-field"]
        sleep(4)
        searchField.tap()
        searchField.typeText("Davis Food Co-op\n")

        let rows = app.buttons.matching(identifier: "search-result")
        if !rows.firstMatch.waitForExistence(timeout: 45) {
            // Live Google can occasionally answer with no rows from the datacenter runner. Retry
            // once before calling the fixture failed.
            searchField.tap()
            searchField.typeText("\n")
        }
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 45), "no result row")
        sleep(3)
        rows.firstMatch.tap()

        let name = app.staticTexts["place-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 15), "no place sheet")
        report("place_open", 1)
        waitUntil(45) { self.value("details") == "done" && self.value("photos") != "0" }
        sleep(2)
        shot("place-top")
        report("place_phone", value("phone") ?? "?")
        report("place_hours", value("hours") ?? "?")

        let scroll = app.scrollViews["place-scroll"]
        XCTAssertTrue(scroll.exists, "no sheet scroll view")
        XCTAssertTrue(reveal(app.buttons["place-all-photos"], in: scroll), "no gallery entry")
        shot("place-photos")

        // Gallery: page the cheap RPC first when it has a cursor, then exercise the category walk.
        app.buttons["place-all-photos"].tap()
        XCTAssertTrue(app.buttons["place-gallery-close"].waitForExistence(timeout: 20), "gallery did not open")
        let initialPhotos = intValue("count", debugID: "place-gallery-debug")
        var galleryPaging = "single-page"
        if app.buttons["place-grid-more-photos"].exists {
            app.buttons["place-grid-more-photos"].tap()
            sleep(1)
            waitUntil(45) { self.intValue("loading", debugID: "place-gallery-debug") == 0 }
            let paged = intValue("count", debugID: "place-gallery-debug")
            if paged > initialPhotos { galleryPaging = "rpc" }
        }
        // The category walk drives a full Google photo page in a hidden WebView. On the CI
        // simulator that page can stall the accessibility snapshot (W-2's GPU issue), so it is
        // verified separately on a device instead of blocking the deterministic gallery checks.
        report("place_gallery_walk", "not-run-on-ci")

        let galleryCount = intValue("count", debugID: "place-gallery-debug")
        report("place_gallery_count", galleryCount)
        report("place_gallery_categories", intValue("categories", debugID: "place-gallery-debug"))
        report("place_gallery_paging", galleryPaging)
        shot("place-gallery-grid")
        XCTAssertGreaterThan(galleryCount, 0, "no gallery photos")

        if app.buttons["place-grid-photo-0"].exists {
            _ = reveal(app.buttons["place-grid-photo-0"], in: app.scrollViews.firstMatch)
            app.buttons["place-grid-photo-0"].tap()
            shot("place-after-photo-tap")
            report("place_viewer_state", value("viewer", debugID: "place-gallery-debug") ?? "missing")
            XCTAssertTrue(app.buttons["place-viewer-close"].waitForExistence(timeout: 10), "viewer did not open")
            sleep(4)
            shot("place-gallery")
            let viewer = app.descendants(matching: .any)["place-photo-viewer"]
            if galleryCount > 1 {
                let firstPage = app.staticTexts["place-gallery-counter"].label
                viewer.swipeLeft()
                waitUntil(10) { app.staticTexts["place-gallery-counter"].label != firstPage }
                report("place_gallery_page", app.staticTexts["place-gallery-counter"].label.replacingOccurrences(of: " ", with: ""))
                XCTAssertNotEqual(app.staticTexts["place-gallery-counter"].label, firstPage, "viewer did not page")
            }
            let image = app.descendants(matching: .any)["place-viewer-image"]
            if image.exists {
                image.pinch(withScale: 2, velocity: 1)
                sleep(1)
                report("place_gallery_zoom", (image.value as? String) ?? "unmeasured")
            }
            app.buttons["place-viewer-close"].tap()
        }
        app.buttons["place-gallery-close"].tap()
        XCTAssertTrue(scroll.waitForExistence(timeout: 5), "place sheet did not return after the gallery")
        sleep(1)
        shot("place-after-gallery")

        // Opening the full panel arms the same lazy review load as scrolling the inline section.
        XCTAssertTrue(reveal(app.buttons["place-all-reviews"], in: scroll), "no reviews panel entry")
        app.buttons["place-all-reviews"].tap()
        XCTAssertTrue(app.buttons["place-reviews-close"].waitForExistence(timeout: 10), "reviews panel did not open")
        waitUntil(150) { self.intValue("initialLoading", debugID: "place-reviews-debug") == 0 }
        sleep(2)
        shot("place-reviews")
        let beforeMore = intValue("count", debugID: "place-reviews-debug")
        report("place_reviews_initial", beforeMore)
        var reviewPaging = "no-cursor"
        if app.buttons["place-panel-more-reviews"].exists {
            app.buttons["place-panel-more-reviews"].tap()
            reviewPaging = "requested"
            sleep(1)
            waitUntil(120) { self.intValue("loading", debugID: "place-reviews-debug") == 0 }
        }
        let afterMore = intValue("count", debugID: "place-reviews-debug")
        if afterMore > beforeMore {
            reviewPaging = "added-\(afterMore - beforeMore)"
            if beforeMore <= 5 { XCTAssertGreaterThan(afterMore, 5, "Google paged but stayed within the limited five") }
        } else if reviewPaging == "requested" {
            reviewPaging = "limited"
        }
        report("place_reviews_paging", reviewPaging)
        report("place_reviews", afterMore)
        report("place_reviews_from", value("from", debugID: "place-reviews-debug") ?? "?")

        // Avatar evidence is the decoded sRGB pixel path, not an assumption about the view.
        waitUntil(25) { self.value("avatarLoaded", debugID: "place-reviews-debug") != "0" }
        waitUntil(10) { self.value("avatarColor", debugID: "place-reviews-debug") != "0" }
        shot("place-avatars")
        shot("place-reviews-full")
        report("place_avatars_loaded", value("avatarLoaded", debugID: "place-reviews-debug") ?? "0")
        report("place_avatars_nonblack", value("avatarColor", debugID: "place-reviews-debug") ?? "0")
        app.buttons["place-reviews-close"].tap()

        waitUntil(30) { self.value("fallback") != "none" && self.value("fallback") != "loading" }
        report("place_popular_fallback", value("fallback") ?? "?")
        report("place_popular_hours", value("popular") ?? "?")
        if intValue("popular") > 0 {
            _ = reveal(app.descendants(matching: .any)["place-popular"], in: scroll, up: false)
            shot("place-popular")
        }

        print("PLACE_DEBUG=\(debugText("place-debug") ?? "none")")
        XCTAssertGreaterThan(intValue("photos"), 0, "no photos")
        XCTAssertGreaterThan(afterMore, 0, "no reviews")
        XCTAssertGreaterThan(intValue("avatarLoaded"), 0, "no avatar image decoded")
        XCTAssertGreaterThan(intValue("avatarColor"), 0, "every decoded avatar was black")
        if value("fallback") == "none" {
            XCTAssertGreaterThan(intValue("popular"), 0, "popular times were absent and the fallback never ran")
        } else {
            XCTAssertNotEqual(value("fallback"), "loading", "popular-times fallback did not finish")
        }
    }

    /// Google's own tabs on the same fixture: expanded hours, the action pills, About and Photos
    /// with their empty states when Google omits data, and the related-places row.
    func testDetailsHoursTabsActionsAndRelated() throws {
        let app = launch(camera: "davis")
        let searchField = app.textFields["search-field"]
        sleep(4)
        searchField.tap()
        searchField.typeText("Davis Food Co-op\n")

        let rows = app.buttons.matching(identifier: "search-result")
        if !rows.firstMatch.waitForExistence(timeout: 45) {
            searchField.tap()
            searchField.typeText("\n")
        }
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 45), "no result row")
        sleep(3)
        rows.firstMatch.tap()

        let name = app.staticTexts["place-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 15), "no place sheet")
        waitUntil(45) { self.value("details") == "done" }
        let scroll = app.scrollViews["place-scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 10), "no sheet scroll view")

        // The photo header: a real photo when Google returned one, the category block otherwise.
        _ = waitUntil(20) { self.intValue("photos") > 0 }
        let headerKind = value("headerStyle") ?? "category"
        report("place_header", headerKind)
        let header = app.descendants(matching: .any)["place-header"]
        XCTAssertTrue(header.waitForExistence(timeout: 5), "no place header")
        if headerKind == "photo" {
            XCTAssertGreaterThanOrEqual(header.frame.height, 140, "the photo header is not 152 pt")
        } else {
            XCTAssertGreaterThanOrEqual(header.frame.height, 90, "the category header collapsed")
        }
        shot("design-place-header")

        // Hours: the status line expands the week (and any department schedule).
        let status = app.buttons["place-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10), "no status line")
        if intValue("hours") > 1 {
            status.tap()
            let hours = app.descendants(matching: .any)["place-hours"]
            XCTAssertTrue(hours.waitForExistence(timeout: 5), "hours did not expand")
            report("place_hours_expanded", 1)
            shot("place-hours-expanded")
        } else {
            report("place_hours_expanded", "google-omitted")
        }

        // The action row: Directions, Save, Lists, Share, then Call and Website where Google
        // supplies them, plus Google's own Order/Reserve/Book button when parsed.
        for id in ["place-directions", "place-save", "place-lists", "place-share"] {
            XCTAssertTrue(app.buttons[id].exists, "missing \(id)")
        }
        let hasCall = app.buttons["place-call"].exists
        let hasSite = app.buttons["place-website"].exists
        report("place_call", hasCall ? 1 : 0)
        report("place_website", hasSite ? 1 : 0)
        report("place_action_link", app.buttons["place-action-link"].exists ? 1 : 0)
        report("place_action_primary", "directions")
        XCTAssertGreaterThanOrEqual(app.buttons["place-directions"].frame.height, 44,
                                    "the primary action is under 44 pt")
        shot("place-actions")
        shot("design-place-actions")

        // The tabs Android shows, as available from the shared data, drawn as underlined text.
        let tabIDs = ["overview", "reviews", "about", "photos", "menu", "updates"]
        let present = tabIDs.filter { app.buttons["place-tab-\($0)"].exists }
        report("place_tabs_present", present.joined(separator: ","))
        report("place_tabs", "underlined")
        XCTAssertEqual(value("tabsStyle"), "underlined", "the tabs are not underlined text")
        let tabsRow = app.descendants(matching: .any)["place-tabs"]
        XCTAssertTrue(tabsRow.exists, "no place tabs row")
        XCTAssertGreaterThanOrEqual(app.buttons["place-tab-overview"].frame.height, 44,
                                    "the tab target is under 44 pt")
        shot("place-tabs")
        shot("design-place-tabs")
        XCTAssertTrue(present.contains("overview"), "no Overview tab")
        XCTAssertTrue(present.contains("about"), "no About tab")

        app.buttons["place-tab-about"].tap()
        let aboutEmpty = app.staticTexts["place-about-empty"]
        if aboutEmpty.waitForExistence(timeout: 2) {
            report("place_about", "google-omitted")
        } else {
            XCTAssertTrue(app.descendants(matching: .any)["place-about"].waitForExistence(timeout: 5), "no About content")
            report("place_about", intValue("about", debugID: "place-debug"))
        }
        shot("place-tab-about")

        if app.buttons["place-tab-photos"].exists {
            app.buttons["place-tab-photos"].tap()
            sleep(2)
            let photosEmpty = app.staticTexts["place-photos-empty"]
            if photosEmpty.exists {
                report("place_photos_tab", "google-omitted")
            } else {
                report("place_photos_tab", intValue("photos"))
                XCTAssertTrue(app.buttons["place-photo"].firstMatch.waitForExistence(timeout: 10), "no photo grid")
            }
            shot("place-tab-photos")
        }

        if app.buttons["place-tab-reviews"].exists {
            app.buttons["place-tab-reviews"].tap()
            shot("place-tab-reviews")
        }

        if app.buttons["place-tab-menu"].exists {
            app.buttons["place-tab-menu"].tap()
            report("place_menu_photos", intValue("menu"))
            shot("place-tab-menu")
        } else {
            report("place_menu_photos", "google-omitted")
        }

        if app.buttons["place-tab-updates"].exists {
            app.buttons["place-tab-updates"].tap()
            report("place_updates", intValue("updates"))
            shot("place-tab-updates")
        } else {
            report("place_updates", intValue("updates") > 0 ? "only-one" : "google-omitted")
        }

        // Back to Overview for the related-places row.
        app.buttons["place-tab-overview"].tap()
        let related = app.buttons.matching(identifier: "place-related")
        let relatedEmpty = app.staticTexts["place-related-empty"]
        var found = waitUntil(10) { related.firstMatch.exists || relatedEmpty.exists }
        if !found {
            _ = reveal(app.descendants(matching: .any)["place-related-section"], in: scroll)
            found = related.firstMatch.exists || relatedEmpty.exists
        }
        XCTAssertTrue(found, "no related-places section")
        let relatedCount = intValue("related")
        report("place_related", relatedCount)
        if relatedCount > 0 {
            XCTAssertTrue(reveal(related.firstMatch, in: scroll), "related row not reachable")
            shot("place-related-row")
            let before = app.staticTexts["place-name"].label
            related.firstMatch.tap()
            let opened = waitUntil(15) { app.staticTexts["place-name"].label != before }
            XCTAssertTrue(opened, "related place did not open")
            shot("place-related")
            report("place_related_open", app.staticTexts["place-name"].label)
        } else {
            shot("place-related-empty")
        }

        print("PLACE_DEBUG=\(debugText("place-debug") ?? "none")")
    }

    /// Finds a lazy section without jumping past it: a few swipes one way, then back the other.
    private func reveal(_ element: XCUIElement, in scroll: XCUIElement, up: Bool = true) -> Bool {
        for _ in 0..<4 {
            if element.isHittable { return true }
            if up { scroll.swipeUp() } else { scroll.swipeDown() }
            sleep(1)
        }
        for _ in 0..<8 {
            if element.isHittable { return true }
            if up { scroll.swipeDown() } else { scroll.swipeUp() }
            sleep(1)
        }
        return element.isHittable
    }

    /// One `key=value` of a place debug line.
    private func value(_ key: String, debugID: String = "place-debug") -> String? {
        guard let line = debugText(debugID) else { return nil }
        for part in line.split(separator: " ") where part.hasPrefix("\(key)=") {
            return String(part.dropFirst(key.count + 1))
        }
        return nil
    }

    private func intValue(_ key: String, debugID: String = "place-debug") -> Int {
        Int(value(key, debugID: debugID) ?? "") ?? -1
    }
}
