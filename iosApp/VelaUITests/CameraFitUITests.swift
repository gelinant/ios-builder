import XCTest

/// CAMERA-FIT: from the San Francisco start camera, a search for "Sacramento, CA" moves the map to the
/// city, and the drive there is framed whole (both ends inside the area the route sheet leaves),
/// flat and north-up. Picking another route or mode frames again. Needs the network.
final class CameraFitUITests: VelaUITestCase {
    private let sacramento = (latitude: 38.5816, longitude: -121.4944)

    func testSearchFramesTheCityAndTheRouteFitsBothEnds() {
        let app = launch(camera: "sf", followUser: true, arguments: ["-VelaResetSettings", "YES"])
        sleep(4)
        type("Sacramento, CA", into: app.textFields["search-field"])

        XCTAssertTrue(waitUntil(60) { self.settled(kind: "search") }, "no search fit: \(line())")
        let search = line()
        print("CAMERA_FIT_SEARCH=\(search)")
        report("camera_fit_search", search.replacingOccurrences(of: " ", with: "|"))
        let center = coordinate(search, "fit_center")
        let km = distanceKm(center, sacramento)
        let zoom = number(search, "fit_zoom")
        report("camera_fit_search_km", Int(km.rounded()))
        report("camera_fit_search_zoom", zoom)
        sleep(2)
        shot("camera-fit-search")
        XCTAssertLessThan(km, 30, "the camera stayed away from Sacramento: \(search)")
        XCTAssertGreaterThanOrEqual(zoom, 10, "the city is framed too wide: \(search)")
        XCTAssertLessThanOrEqual(zoom, 13.5, "the city is framed too close: \(search)")

        let directions = app.buttons["place-directions"]
        if !directions.exists {
            let rows = app.buttons.matching(identifier: "search-result")
            XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 20), "no result row")
            rows.firstMatch.tap()
        }
        XCTAssertTrue(directions.waitForExistence(timeout: 15), "no Directions button")
        directions.tap()
        if app.buttons["route-mode-DRIVE"].waitForExistence(timeout: 10), routeValue("mode") != "DRIVE" {
            app.buttons["route-mode-DRIVE"].tap()
        }
        waitUntil(90) { self.routeValue("loading") == "0" && self.routeValue("mode") == "DRIVE" }
        XCTAssertTrue(waitUntil(30) { self.settled(kind: "route") }, "no route fit: \(line())")
        let route = line()
        print("CAMERA_FIT_ROUTE=\(route)")
        report("camera_fit_route", route.replacingOccurrences(of: " ", with: "|"))
        sleep(2)
        shot("camera-fit-route")
        assertRouteFit(route)
        let routeCenter = coordinate(route, "fit_center")
        XCTAssertTrue((37.4...38.9).contains(routeCenter.latitude), "the fit is not between the ends: \(route)")
        XCTAssertLessThan(number(route, "fit_zoom"), 11, "a 140 km drive is framed too close: \(route)")

        // Another route frames again.
        var count = number(route, "fit_count")
        let routeRows = app.buttons.matching(identifier: "route-row")
        if routeRows.count > 1, routeRows.element(boundBy: 1).isHittable {
            routeRows.element(boundBy: 1).tap()
            XCTAssertTrue(waitUntil(15) { self.settled(kind: "route", after: count) }, "no refit: \(line())")
            assertRouteFit(line())
            count = number(line(), "fit_count")
            report("camera_fit_alternate", 1)
        } else {
            report("camera_fit_alternate", 0)
        }

        // Another mode frames again.
        app.buttons["route-mode-TRANSIT"].tap()
        waitUntil(90) { self.routeValue("mode") == "TRANSIT" && self.routeValue("loading") == "0" }
        if Int(routeValue("transit") ?? "") ?? 0 > 0 {
            XCTAssertTrue(waitUntil(20) { self.settled(kind: "route", after: count) }, "no transit fit: \(line())")
            let transit = line()
            print("CAMERA_FIT_TRANSIT=\(transit)")
            assertRouteFit(transit)
            report("camera_fit_transit", transit.replacingOccurrences(of: " ", with: "|"))
            sleep(2)
            shot("camera-fit-transit")
        } else {
            report("camera_fit_transit", "no_itinerary")
        }
        app.buttons["route-mode-DRIVE"].tap()
        sleep(1)
    }

    private func assertRouteFit(_ line: String) {
        XCTAssertGreaterThan(number(line, "fit_points"), 1, line)
        XCTAssertEqual(number(line, "fit_inside"), number(line, "fit_points"), "an end is outside the fit: \(line)")
        XCTAssertEqual(number(line, "fit_pitch"), 0, "the route fit is tilted: \(line)")
        XCTAssertEqual(number(line, "fit_bearing").truncatingRemainder(dividingBy: 360), 0,
                       "the route fit is not north-up: \(line)")
    }

    /// Types [text] and checks the field kept every letter before submitting: the simulator can
    /// drop keys while the map loads.
    private func type(_ text: String, into field: XCUIElement) {
        for _ in 0..<3 {
            field.tap()
            _ = app.keyboards.firstMatch.waitForExistence(timeout: 5)
            if let current = field.value as? String, !current.isEmpty, current != text,
               app.buttons["search-clear"].exists {
                app.buttons["search-clear"].tap()
                field.tap()
            }
            field.typeText(text)
            if (field.value as? String) == text { break }
            sleep(1)
        }
        XCTAssertEqual(field.value as? String, text, "the search field lost letters")
        field.typeText("\n")
    }

    private func line() -> String { debugText("camera-fit-debug") ?? "" }

    /// The fit of [kind] has settled on the page, and is newer than fit number [after].
    private func settled(kind: String, after: Double = 0) -> Bool {
        let text = line()
        return text.hasPrefix("fit=\(kind)") && text.contains("fit_settled=1")
            && number(text, "fit_count") > after
    }

    private func field(_ line: String, _ key: String) -> String? {
        line.split(separator: " ").first { $0.hasPrefix("\(key)=") }.map { String($0.dropFirst(key.count + 1)) }
    }

    private func number(_ line: String, _ key: String) -> Double {
        Double(field(line, key) ?? "") ?? -1
    }

    private func coordinate(_ line: String, _ key: String) -> (latitude: Double, longitude: Double) {
        let parts = (field(line, key) ?? "").split(separator: ",").compactMap { Double($0) }
        return parts.count == 2 ? (parts[0], parts[1]) : (0, 0)
    }

    private func distanceKm(_ a: (latitude: Double, longitude: Double),
                            _ b: (latitude: Double, longitude: Double)) -> Double {
        let dLat = (a.latitude - b.latitude) * 111.32
        let dLng = (a.longitude - b.longitude) * 111.32 * cos(b.latitude * .pi / 180)
        return (dLat * dLat + dLng * dLng).squareRoot()
    }

    private func routeValue(_ key: String) -> String? {
        guard let line = debugText("route-debug") else { return nil }
        return field(line, key)
    }
}
