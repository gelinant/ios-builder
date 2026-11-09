import XCTest

/// N-4: a drive with one waypoint announces it, carries on to the destination, offers to save the
/// car's spot on arrival, and one Live Activity covers the whole trip. The link fixes both ends on
/// the Market Street fixture, so the simulated replay ends exactly at the destination.
final class NavArrivalUITests: VelaUITestCase {
    private let fixtureDrive = "https://www.google.com/maps/dir/?api=1" +
        "&origin=37.7749,-122.4194&destination=37.7942,-122.3946&travelmode=driving"

    override func tearDown() {
        if let app, app.buttons["nav-end"].exists {
            app.buttons["nav-end"].tap()
            let confirm = app.buttons["nav-end-confirm"].firstMatch
            if confirm.waitForExistence(timeout: 2) { confirm.tap() }
            _ = waitUntil(5) { self.value("activity") != "1" }
        }
        super.tearDown()
    }

    func testWaypointArrivalParkingAndEnd() throws {
        let app = launch(camera: "sf", followUser: true, arguments: ["-VelaOpenURL", fixtureDrive])
        let chooser = app.otherElements["route-sheet"]
        XCTAssertTrue(chooser.waitForExistence(timeout: 90)
            || app.buttons["route-mode-DRIVE"].waitForExistence(timeout: 10),
            "the directions link did not open the chooser")
        if value("mode") != "DRIVE" {
            app.buttons["route-mode-DRIVE"].tap()
        }
        XCTAssertTrue(waitUntil(120) {
            self.value("loading") == "0" && (Int(self.value("routes") ?? "") ?? 0) > 0
        }, "no driving route: \(debugText("route-debug") ?? "none")")

        // R-1's stop picker: one stop on Market Street before the end.
        app.buttons["route-add-stop"].tap()
        let placeField = app.textFields["route-place-search-field"]
        XCTAssertTrue(placeField.waitForExistence(timeout: 10), "no stop search field")
        placeField.tap()
        placeField.typeText("Embarcadero Station\n")
        let placeRows = app.buttons.matching(identifier: "route-place-result")
        XCTAssertTrue(placeRows.firstMatch.waitForExistence(timeout: 60), "no stop search result")
        placeRows.firstMatch.tap()
        XCTAssertTrue(waitUntil(120) {
            self.value("stops") == "1" && self.value("loading") == "0" && self.value("mode") == "DRIVE"
        }, "the route lost its stop: \(debugText("route-debug") ?? "none")")
        report("nav_arrival_stops", value("stops") ?? "?")

        let start = app.buttons["route-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10), "no Start button")
        start.tap()
        XCTAssertTrue(app.otherElements["nav-banner"].waitForExistence(timeout: 20), "no nav banner")
        XCTAssertTrue(waitUntil(10) { self.value("nav") == "1" }, "navigation did not start")
        XCTAssertEqual(value("nextstop"), "1", "the drive has no next stop: \(debugText("nav-debug") ?? "none")")
        let checksActivity = value("actenabled") == "1"
        let activityRequests = intValue("actrequests") ?? 0
        if checksActivity {
            XCTAssertTrue(waitUntil(10) { self.value("activity") == "1" }, "no Live Activity on Start")
        }

        // The host's sim_route_arm watcher replays sf-market on "nav replay: start".
        let waypoint = app.descendants(matching: .any).matching(identifier: "nav-waypoint").firstMatch
        XCTAssertTrue(waypoint.waitForExistence(timeout: 200),
                      "the waypoint was never announced: \(debugText("nav-debug") ?? "none")")
        sleep(1)
        shot("nav-waypoint")
        XCTAssertEqual(value("reached"), "1", "the reached-stop serial did not advance")
        report("nav_waypoint", "announced")
        report("nav_waypoint_meters_left", intValue("left") ?? -1)

        let cont = app.buttons["nav-waypoint-continue"]
        XCTAssertTrue(cont.waitForExistence(timeout: 5), "no Continue action on the waypoint card")
        cont.tap()
        XCTAssertTrue(waitUntil(5) { self.value("nav") == "1" && self.value("active") == "1" },
                      "the waypoint card ended the drive")
        XCTAssertFalse(waypoint.exists, "the waypoint card stayed after Continue")
        if checksActivity {
            XCTAssertEqual(value("activity"), "1", "the waypoint ended the Live Activity")
            XCTAssertEqual(intValue("actrequests"), activityRequests, "the waypoint requested a second Live Activity")
        }
        report("nav_waypoint_continued", "1")

        XCTAssertTrue(waitUntil(90) { self.value("arrived") == "1" },
                      "the destination was never reached: \(debugText("nav-debug") ?? "none")")
        let arrival = app.descendants(matching: .any).matching(identifier: "nav-arrival").firstMatch
        XCTAssertTrue(arrival.waitForExistence(timeout: 10), "no arrival card")
        XCTAssertEqual(value("nav"), "0", "arrival kept the drive running")
        XCTAssertEqual(value("active"), "1", "arrival dropped the route before Done")
        XCTAssertEqual(value("stops"), "0", "the waypoint was still listed after arrival")
        sleep(1)
        shot("nav-arrival")
        report("nav_arrival", "shown")

        // The car's spot is offered once, from the arrival position, and writes the same parking
        // store as the map button.
        let save = app.buttons["nav-save-parking"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "no Save parking action on arrival")
        save.tap()
        let saved = app.descendants(matching: .any).matching(identifier: "nav-parking-saved").firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5), "the parking offer gave no confirmation")
        XCTAssertEqual(value("parked"), "1", "the parking spot was not saved")
        report("nav_arrival_parking", "saved")

        app.buttons["nav-done"].tap()
        XCTAssertTrue(waitUntil(10) { self.value("nav") == "0" && self.value("active") == "0" },
                      "Done did not end the drive")
        XCTAssertTrue(app.textFields["search-field"].waitForExistence(timeout: 5),
                      "browse chrome was not restored after Done")
        XCTAssertFalse(arrival.exists)
        XCTAssertEqual(value("idle"), "0")
        XCTAssertEqual(value("background"), "0")
        if checksActivity {
            XCTAssertTrue(waitUntil(5) { self.value("activity") == "0" }, "Live Activity survived Done")
            XCTAssertEqual(intValue("actrequests"), activityRequests, "Done requested another Live Activity")
            report("nav_arrival_activity", "one")
        }
        shot("nav-end")
        report("nav_arrival_end", "restored")
    }

    private func value(_ key: String) -> String? {
        guard let line = debugText("nav-debug") else { return nil }
        for part in line.split(separator: " ") where part.hasPrefix("\(key)=") {
            return String(part.dropFirst(key.count + 1))
        }
        return nil
    }

    private func intValue(_ key: String) -> Int? {
        value(key).flatMap(Int.init)
    }
}
