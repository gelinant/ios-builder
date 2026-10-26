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
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 60), "no result row")
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
        XCTAssertTrue(app.buttons["place-all-photos"].waitForExistence(timeout: 10), "no gallery entry")
        shot("place-photos")

        // Gallery: page the cheap RPC first when it has a cursor, then exercise the category walk.
        app.buttons["place-all-photos"].tap()
        XCTAssertTrue(app.buttons["place-gallery-close"].waitForExistence(timeout: 10), "gallery did not open")
        let initialPhotos = intValue("count", debugID: "place-gallery-debug")
        var galleryPaging = "single-page"
        if app.buttons["place-grid-more-photos"].exists {
            app.buttons["place-grid-more-photos"].tap()
            sleep(1)
            waitUntil(45) { self.intValue("loading", debugID: "place-gallery-debug") == 0 }
            let paged = intValue("count", debugID: "place-gallery-debug")
            if paged > initialPhotos { galleryPaging = "rpc" }
        }
        if app.buttons["place-photo-categories"].exists {
            app.buttons["place-photo-categories"].tap()
            sleep(1)
            waitUntil(90) {
                self.intValue("loading", debugID: "place-gallery-debug") == 0 &&
                self.intValue("walk", debugID: "place-gallery-debug") == 0
            }
            if galleryPaging == "single-page" { galleryPaging = "walk" }
        }
        let galleryCount = intValue("count", debugID: "place-gallery-debug")
        report("place_gallery_count", galleryCount)
        report("place_gallery_categories", intValue("categories", debugID: "place-gallery-debug"))
        report("place_gallery_paging", galleryPaging)
        shot("place-gallery-grid")
        XCTAssertGreaterThan(galleryCount, 0, "no gallery photos")

        if app.buttons["place-grid-photo-0"].exists {
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

        // Opening the full panel arms the same lazy review load as scrolling the inline section.
        XCTAssertTrue(app.buttons["place-all-reviews"].waitForExistence(timeout: 10), "no reviews panel entry")
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
