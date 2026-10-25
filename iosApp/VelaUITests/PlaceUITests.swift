import XCTest

/// M3 end to end: "coffee" over San Francisco, the first result's sheet with its details, photos
/// and reviews. Needs the network; the runner's datacenter address gets Google's limited view
/// (about five reviews, often no popular times).
final class PlaceUITests: VelaUITestCase {
    func testFirstCoffeeResultOpensItsSheet() throws {
        let app = launch(camera: "sf")
        let searchField = app.textFields["search-field"]
        sleep(4)
        searchField.tap()
        searchField.typeText("coffee\n")

        let rows = app.buttons.matching(identifier: "search-result")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 60), "no result row")
        sleep(3)
        rows.firstMatch.tap()

        let name = app.staticTexts["place-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 15), "no place sheet")
        report("place_name", name.label.replacingOccurrences(of: " ", with: "_"))
        // The details land in a few seconds; the photos with them.
        waitUntil(30) { (self.value("details") == "done" && self.value("photos") != "0") }
        sleep(3)
        shot("place-top")
        report("place_phone", value("phone") ?? "?")
        report("place_hours", value("hours") ?? "?")

        let scroll = app.scrollViews["place-scroll"]
        XCTAssertTrue(scroll.exists, "no sheet scroll view")
        scroll.swipeUp()
        sleep(3)
        shot("place-photos")

        // Scrolling the reviews on screen starts them: the feed first, the page after.
        for _ in 0..<3 where !app.staticTexts["place-reviews-title"].isHittable {
            scroll.swipeUp()
            sleep(1)
        }
        waitUntil(150) { self.value("reviewsLoading") == "0" }
        scroll.swipeUp()
        sleep(3)
        shot("place-reviews")
        scroll.swipeUp()
        sleep(2)
        shot("place-reviews-2")

        let photos = Int(value("photos") ?? "") ?? -1
        let reviews = Int(value("reviews") ?? "") ?? -1
        report("place_photos", photos)
        report("place_reviews", reviews)
        report("place_reviews_from", value("from") ?? "?")
        report("place_popular_hours", value("popular") ?? "?")
        print("PLACE_DEBUG=\(debugText("place-debug") ?? "none")")
        XCTAssertGreaterThan(photos, 0, "no photos")
        XCTAssertGreaterThan(reviews, 0, "no reviews")
    }

    /// One `key=value` of the sheet's debug line.
    private func value(_ key: String) -> String? {
        guard let line = debugText("place-debug") else { return nil }
        for part in line.split(separator: " ") where part.hasPrefix("\(key)=") {
            return String(part.dropFirst(key.count + 1))
        }
        return nil
    }
}
