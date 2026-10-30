import XCTest

/// UX-JOURNEY: four end-to-end user journeys. Each scenario walks the path a person takes, writes
/// one screenshot per step and asserts the end state: the map back, no leftover sheet, and, for
/// search to guidance, the camera the journey started from.
final class JourneyUITests: VelaUITestCase {
    private struct JourneyFailure: Error, CustomStringConvertible {
        let description: String
    }

    // MARK: Journey 1: search to guidance and back

    func testJourney1SearchToGuidanceAndBack() {
        do {
            let app = launch(camera: "sf", followUser: true, arguments: [
                "-VelaResetSettings", "YES", "-VelaRouteOrderFixture", "YES",
            ])
            shot("journey-1-search")

            let field = app.textFields["search-field"]
            sleep(3)
            focus(field, in: app)
            field.typeText("coffee\n")
            let rows = app.buttons.matching(identifier: "search-result")
            try require(rows.firstMatch.waitForExistence(timeout: 60), "no coffee result")
            sleep(2)
            shot("journey-1-results")

            rows.firstMatch.tap()
            let directions = app.buttons["place-directions"]
            try require(directions.waitForExistence(timeout: 15), "the place sheet did not open")
            try require(directions.isHittable, "Directions is covered on the place sheet")
            shot("journey-1-place")

            directions.tap()
            try require(app.otherElements["route-sheet"].waitForExistence(timeout: 15)
                        || app.buttons["route-mode-DRIVE"].waitForExistence(timeout: 5),
                        "the route chooser did not open")
            if routeValue("mode", in: app) != "DRIVE" {
                app.buttons["route-mode-DRIVE"].tap()
            }
            try require(waitUntil(120) {
                self.routeValue("mode", in: app) == "DRIVE"
                    && self.routeValue("loading", in: app) == "0"
                    && (Int(self.routeValue("routes", in: app) ?? "") ?? 0) >= 1
            }, "no driving route: \(debugText("route-debug") ?? "none")")
            sleep(2)
            shot("journey-1-route")
            let cameraBefore = try camera(in: app)

            let steps = app.buttons["route-steps"]
            try require(steps.waitForExistence(timeout: 10) && steps.isHittable, "Steps is not reachable")
            steps.tap()
            try require(app.descendants(matching: .any)["steps-sheet"].waitForExistence(timeout: 10),
                        "the steps sheet did not open")
            try require(app.descendants(matching: .any).matching(identifier: "step-row").firstMatch
                            .waitForExistence(timeout: 10), "the steps sheet has no step")
            shot("journey-1-steps")

            let stepsClose = app.buttons["steps-close"]
            try require(stepsClose.waitForExistence(timeout: 5) && stepsClose.isHittable,
                        "the steps sheet cannot be closed")
            stepsClose.tap()
            try require(waitUntil(10) {
                !app.descendants(matching: .any)["steps-sheet"].exists
                    && app.buttons["route-start"].waitForExistence(timeout: 5)
            }, "closing Steps did not return to the route chooser")
            shot("journey-1-route-back")

            app.buttons["route-start"].tap()
            try require(app.otherElements["nav-banner"].waitForExistence(timeout: 20),
                        "guidance did not start")
            shot("journey-1-guidance")
            try require(!app.buttons["route-close"].exists,
                        "the route chooser stayed on top of guidance")

            app.buttons["nav-end"].tap()
            let confirm = app.buttons["nav-end-confirm"].firstMatch
            try require(confirm.waitForExistence(timeout: 5), "no End confirmation")
            confirm.tap()
            try require(waitUntil(15) {
                !app.otherElements["nav-banner"].exists
                    && app.textFields["search-field"].exists
            }, "End did not restore the browse map")
            shot("journey-1-end")

            try assertMapOnly(app, "the guidance journey left a sheet behind")
            try require(waitUntil(10) { (try? self.camera(in: app)) == cameraBefore },
                        "the map did not return to its pre-guidance camera: "
                            + "before=\(cameraBefore) after=\(camera(in: app))")
            report("journey_1_camera", cameraBefore)
            report("journey_1", "ok")
        } catch {
            report("journey_1", "fail")
            XCTFail("journey 1: \(error)")
        }
    }

    // MARK: Journey 2: place to saved list to route and back to the list

    func testJourney2PlaceToSavedListToRouteAndBack() {
        do {
            // French proves the journey is completable in one of the 24 catalog languages, and
            // that the primary flow labels are translated rather than hard-coded English.
            let app = launch(camera: "davis", arguments: [
                "-VelaResetSettings", "YES", "-VelaPlaceFixture", "YES",
                "-VelaRouteOrderFixture", "YES", "-VelaLanguage", "fr",
            ])
            try require(app.staticTexts["place-name"].waitForExistence(timeout: 60),
                        "the fixture place did not open")
            let save = app.buttons["place-save"]
            try require(save.waitForExistence(timeout: 10), "the place sheet has no Save action")
            try require(save.label == "Enregistrer" || save.label == "Enregistré",
                        "the Save label is not French: \(save.label)")
            try require(app.buttons["place-directions"].label == "Itinéraire",
                        "the Directions label is not French: \(app.buttons["place-directions"].label)")
            shot("journey-2-place")

            // A place left over from another suite is quick-saved already; start from unsaved so
            // the list membership is this journey's own.
            if save.label == "Enregistré" { save.tap() }
            try require(waitUntil(5) { app.buttons["place-save"].label == "Enregistrer" },
                        "the place could not be unsaved")
            app.buttons["place-save"].tap()
            app.buttons["saved-open"].tap()
            try require(app.navigationBars.firstMatch.waitForExistence(timeout: 15),
                        "Saved did not open")
            shot("journey-2-saved")

            let create = app.buttons["saved-create-list"]
            try require(reveal("saved-create-list", in: "saved-sheet", app: app).waitForExistence(timeout: 10)
                        || create.waitForExistence(timeout: 5), "no new-list action")
            create.tap()
            let nameField = app.textFields["saved-name-field"]
            try require(nameField.waitForExistence(timeout: 10), "no list name field")
            let listName = "Voyage \(Int(Date().timeIntervalSince1970) % 100000)"
            try require(focusAndType(nameField, listName, in: app), "the list name field did not take the text")
            app.buttons["saved-name-save"].tap()
            try require(app.buttons["saved-list"].firstMatch.waitForExistence(timeout: 10),
                        "the list was not created")
            app.buttons["saved-close"].tap()

            let lists = app.buttons["place-lists"]
            try require(lists.waitForExistence(timeout: 10) && lists.isHittable,
                        "the Lists action is covered on the place sheet")
            lists.tap()
            let listChoice = app.buttons[listName]
            try require(listChoice.waitForExistence(timeout: 10), "the new list is missing from the place picker")
            listChoice.tap()
            let done = app.buttons["Terminé"].exists
                ? app.buttons["Terminé"] : app.buttons["Done"]
            try require(done.waitForExistence(timeout: 5), "no Done action in the list picker")
            done.tap()
            shot("journey-2-list-picker")

            app.buttons["saved-open"].tap()
            let listRow = app.buttons["saved-list"].firstMatch
            try require(listRow.waitForExistence(timeout: 10), "the saved list row is missing")
            listRow.tap()
            try require(app.buttons["saved-list-place"].waitForExistence(timeout: 10),
                        "the list detail did not open")
            shot("journey-2-list")

            app.buttons["saved-list-place"].tap()
            try require(app.staticTexts["place-name"].waitForExistence(timeout: 15),
                        "the place from the list did not open")
            shot("journey-2-place-from-list")

            app.buttons["place-directions"].tap()
            try require(app.buttons["route-mode-DRIVE"].waitForExistence(timeout: 15)
                        || app.otherElements["route-sheet"].waitForExistence(timeout: 5),
                        "the list place did not offer routes")
            try require(waitUntil(120) {
                self.routeValue("loading", in: app) == "0"
                    && (Int(self.routeValue("routes", in: app) ?? "") ?? 0) >= 1
            }, "no route to the list place: \(debugText("route-debug") ?? "none")")
            shot("journey-2-route")

            app.buttons["route-close"].tap()
            try require(waitUntil(10) { !app.buttons["route-close"].exists },
                        "the route chooser did not close")
            try require(app.buttons["place-close"].waitForExistence(timeout: 10),
                        "the place sheet did not come back under the route")
            app.buttons["place-close"].tap()

            // The return point is the list, not the bare map.
            try require(app.buttons["saved-list-place"].waitForExistence(timeout: 15),
                        "closing the place did not return to the Saved list")
            shot("journey-2-back-to-list")
            try require(app.navigationBars.firstMatch.label == listName,
                        "the Saved sheet reopened on the root instead of the list")
            app.buttons["saved-close"].tap()
            try assertMapOnly(app, "the Saved journey left a sheet behind")
            shot("journey-2-end")
            report("journey_2_language", "fr")
            report("journey_2", "ok")
        } catch {
            report("journey_2", "fail")
            XCTFail("journey 2: \(error)")
        }
    }

    // MARK: Journey 3: transit stop to the trip screen and back

    func testJourney3TransitDoorToDoor() {
        do {
            let app = launch(camera: "sf", waitForMap: false, arguments: [
                "-VelaTransitFixture", "YES", "-VelaTransitLineFixture", "YES",
                "-VelaTransitBoardOfflineTest", "YES", "-VelaTransitBoardTest", "YES",
            ])
            try require(app.descendants(matching: .any)["transit-board"].waitForExistence(timeout: 60)
                        || app.staticTexts["transit-board-station"].waitForExistence(timeout: 5),
                        "the stop board did not open")
            // The line fixture opens its own sheet on a delay; close it so the board is the
            // surface the journey starts from.
            let autoLine = app.otherElements["transit-line-sheet"]
            if autoLine.waitForExistence(timeout: 15) {
                app.buttons["transit-line-close"].tap()
                try require(waitUntil(10) { !autoLine.exists }, "the fixture line sheet did not close")
            }
            try require(waitUntil(30) {
                self.field("loading", in: self.boardDebug(in: app)) == "0"
            }, "the board stayed loading: \(boardDebug(in: app) ?? "none")")
            shot("journey-3-stop")

            let lineRows = app.descendants(matching: .any).matching(identifier: "transit-board-line")
            try require(lineRows.firstMatch.waitForExistence(timeout: 15), "the board has no line row")
            lineRows.firstMatch.tap()
            try require(app.otherElements["transit-line-sheet"].waitForExistence(timeout: 20),
                        "the line sheet did not open from the board")
            shot("journey-3-line")
            app.buttons["transit-line-close"].tap()
            try require(waitUntil(10) { !app.otherElements["transit-line-sheet"].exists },
                        "the line sheet did not close")

            app.buttons["transit-board-close"].tap()
            try require(app.otherElements["transit-card"].waitForExistence(timeout: 20),
                        "closing the board did not return to the transit card")
            shot("journey-3-board-end")

            let itinerary = app.buttons["transit-detail-open"]
            try require(itinerary.waitForExistence(timeout: 15) && itinerary.isHittable,
                        "the itinerary entry is not reachable on the transit card")
            itinerary.tap()
            try require(app.descendants(matching: .any)["steps-sheet"].waitForExistence(timeout: 20),
                        "the itinerary sheet did not open")
            shot("journey-3-itinerary")

            let trip = app.buttons["transit-trip-open"]
            try require(trip.waitForExistence(timeout: 15) && trip.isHittable,
                        "the trip screen entry is not reachable in the itinerary")
            trip.tap()
            try require(app.buttons["transit-trip-close"].waitForExistence(timeout: 20),
                        "the trip screen did not open")
            shot("journey-3-trip")
            app.buttons["transit-trip-close"].tap()
            try require(app.otherElements["transit-card"].waitForExistence(timeout: 20),
                        "closing the trip screen did not return to the card")

            let go = app.buttons["transit-go-open"]
            try require(go.waitForExistence(timeout: 20), "the card has no GO action")
            go.tap()
            try require(app.descendants(matching: .any)["transit-go-screen"].waitForExistence(timeout: 30),
                        "GO did not open")
            shot("journey-3-go")
            app.buttons["transit-go-close"].tap()
            try require(waitUntil(10) { !app.descendants(matching: .any)["transit-go-screen"].exists },
                        "GO did not close")
            shot("journey-3-go-end")

            app.buttons["transit-end"].tap()
            try require(waitUntil(20) {
                !app.otherElements["transit-card"].exists
                    && app.textFields["search-field"].waitForExistence(timeout: 5)
            }, "End did not return to the map")
            shot("journey-3-end")
            try assertMapOnly(app, "the transit journey left a sheet behind")
            report("journey_3", "ok")
        } catch {
            report("journey_3", "fail")
            XCTFail("journey 3: \(error)")
        }
    }

    // MARK: Journey 4: offline area download left and reopened

    func testJourney4OfflineAreaDownloadAndReopen() {
        do {
            let app = launch(camera: "43.7391,7.4280,14", followUser: false, arguments: [
                "-VelaOfflineTest", "YES", "-VelaOfflineFixture", "YES", "-VelaOfflineAreaSlow", "YES",
            ])
            openOfflineSheet(app)
            shot("journey-4-offline")

            let start = app.buttons["offline-area-start"]
            try require(reveal("offline-area-start", in: "offline-sheet", app: app)
                            .waitForExistence(timeout: 30), "the area entry is missing")
            start.tap()
            try require(app.descendants(matching: .any)["offline-area-frame"].waitForExistence(timeout: 10),
                        "the area picker did not open")
            let estimate = app.staticTexts["area-estimate"]
            try require(waitUntil(20) { estimate.exists && estimate.label.contains("Estimated download") },
                        "no estimate for the framed area")
            shot("journey-4-frame")

            let download = app.buttons["area-download"]
            try require(waitUntil(20) { download.exists && download.isEnabled },
                        "Download stayed disabled")
            download.tap()
            try require(app.progressIndicators["area-progress"].waitForExistence(timeout: 45),
                        "the area download never showed progress")
            sleep(2)
            shot("journey-4-download")
            let firstPieces = areaPieces(in: app)
            try require(firstPieces > 0, "the progress card reports no downloaded piece yet")

            // Leave the download surface mid-download, then reopen the manager.
            let hide = app.buttons["area-hide"]
            try require(hide.waitForExistence(timeout: 10), "the progress card cannot be dismissed")
            hide.tap()
            try require(waitUntil(10) { !app.descendants(matching: .any)["area-progress-card"].exists },
                        "the progress card stayed on the map")

            openOfflineSheet(app)
            try require(app.descendants(matching: .any)["offline-sheet"].waitForExistence(timeout: 15),
                        "the offline sheet did not reopen")
            let reopened = try offlinePieces(in: app)
            shot("journey-4-reopen")
            report("journey_4_first_pieces", firstPieces)
            report("journey_4_reopened_pieces", reopened)
            app.buttons["offline-done"].tap()
            try require(waitUntil(10) { !app.descendants(matching: .any)["offline-sheet"].exists },
                        "the offline sheet did not close")

            openOfflineSheet(app)
            let again = try offlinePieces(in: app)
            shot("journey-4-reopen-again")
            report("journey_4_second_open_pieces", again)
            try require(again >= reopened,
                        "the reopened sheet went backwards: \(reopened) then \(again)")
            app.buttons["offline-done"].tap()
            try require(waitUntil(10) { !app.descendants(matching: .any)["offline-sheet"].exists },
                        "the offline sheet did not close the second time")
            shot("journey-4-end")
            try assertMapOnly(app, "the offline journey left a sheet behind")
            report("journey_4", "ok")
        } catch {
            report("journey_4", "fail")
            XCTFail("journey 4: \(error)")
        }
    }

    // MARK: Helpers

    private func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw JourneyFailure(description: message) }
    }

    /// The end state every journey shares: browser chrome, no content sheet, no system sheet.
    private func assertMapOnly(_ app: XCUIApplication, _ message: String) throws {
        try require(app.textFields["search-field"].waitForExistence(timeout: 10), message + ": no search field")
        let sheets = [
            "route-sheet", "steps-sheet", "place-sheet", "map-poi-sheet", "offline-sheet",
            "transit-board", "transit-line-sheet", "transit-go-screen", "transit-card",
        ]
        for id in sheets {
            try require(!app.descendants(matching: .any)[id].exists, "\(message): \(id) is still up")
        }
    }

    private func focus(_ field: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<3 {
            field.tap()
            if app.keyboards.count > 0 { return }
            sleep(1)
        }
    }

    private func focusAndType(_ field: XCUIElement, _ text: String, in app: XCUIApplication) -> Bool {
        for _ in 0..<4 {
            field.tap()
            sleep(1)
            if app.keyboards.count > 0 {
                field.typeText(text)
                if (field.value as? String) == text { return true }
            }
        }
        return false
    }

    private func openOfflineSheet(_ app: XCUIApplication) {
        let overflow = app.buttons["map-overflow"]
        guard overflow.waitForExistence(timeout: 30) else { return }
        for _ in 0..<4 {
            overflow.tap()
            if app.buttons["offline-menu-item"].waitForExistence(timeout: 3) {
                app.buttons["offline-menu-item"].tap()
                return
            }
            sleep(1)
        }
    }

    /// The camera the debug line reports as `start_center=lat,lon,zoom`.
    private func camera(in app: XCUIApplication) throws -> String {
        guard let line = debugText("start-debug"),
              let center = field("start_center", in: line) else {
            throw JourneyFailure(description: "no camera line: \(debugText("start-debug") ?? "none")")
        }
        return center
    }

    private func routeValue(_ key: String, in app: XCUIApplication) -> String? {
        field(key, in: debugText("route-debug"))
    }

    private func boardDebug(in app: XCUIApplication) -> String? {
        [app.staticTexts["transit-board-debug"], app.staticTexts["transit-board-status"]]
            .first(where: { $0.exists })?.label
    }

    private func field(_ key: String, in line: String?) -> String? {
        guard let line else { return nil }
        for part in line.split(separator: " ") where part.hasPrefix("\(key)=") {
            return String(part.dropFirst(key.count + 1))
        }
        return nil
    }

    /// The pieces the area progress card has downloaded, read from its debug line.
    private func areaPieces(in app: XCUIApplication) -> Int {
        let line = app.staticTexts["area-progress-debug"].exists
            ? app.staticTexts["area-progress-debug"].label
            : app.staticTexts["area-debug"].exists ? app.staticTexts["area-debug"].label : ""
        guard let pieces = field("pieces", in: line) else { return 0 }
        return Int(pieces.split(separator: "/").first ?? "") ?? 0
    }

    /// The offline manager's area state after leaving and reopening it mid-download. A finished
    /// download counts as all pieces, so a reopen can only move forward.
    private func offlinePieces(in app: XCUIApplication) throws -> Int {
        if app.staticTexts["area-sheet-ready"].waitForExistence(timeout: 3) { return 100 }
        let pieces = app.staticTexts["area-sheet-pieces"]
        guard pieces.waitForExistence(timeout: 15) else {
            throw JourneyFailure(description: "the reopened offline sheet has no area state")
        }
        let first = pieces.label.split(separator: " ").first ?? ""
        guard let count = Int(first) else {
            throw JourneyFailure(description: "unreadable area state: \(pieces.label)")
        }
        return count
    }
}
