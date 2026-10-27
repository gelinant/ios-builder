import XCTest
@testable import Vela

/// The widget extension cannot be tapped from XCUITest, so these tests cover the payload it reads:
/// shortcut building, parking age, board rows, stale state and the App Group round trip.
final class WidgetTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func departure(minutes: Int, realtime: Bool = false) -> WidgetDeparture {
        WidgetDeparture(
            epochSec: Int64(now.timeIntervalSince1970) + Int64(minutes * 60),
            realtime: realtime,
            clockText: nil)
    }

    // MARK: Shortcuts

    func testShortcutsKeepHomeThenWorkAndTheirAddresses() {
        let shortcuts = WidgetSnapshotBuilder.shortcuts(
            home: WidgetShortcut(kind: .home, name: "Home", address: "620 G St, Davis, CA 95616"),
            work: WidgetShortcut(kind: .work, name: "Work", address: "1 Capitol Mall, Sacramento"))
        XCTAssertEqual(shortcuts.map(\.kind), [.home, .work])
        XCTAssertEqual(shortcuts[0].address, "620 G St, Davis, CA 95616")
        XCTAssertEqual(shortcuts[1].deepLink.absoluteString, "vela://navigate/work")
    }

    func testShortcutsDropMissingPlacesAndEmptyIsNotAFailure() {
        let onlyWork = WidgetSnapshotBuilder.shortcuts(
            home: nil, work: WidgetShortcut(kind: .work, name: "Work", address: nil))
        XCTAssertEqual(onlyWork.map(\.kind), [.work])
        XCTAssertTrue(WidgetSnapshotBuilder.shortcuts(home: nil, work: nil).isEmpty)
    }

    // MARK: Parking

    func testParkingAgeUsesWholeHoursAndMinutes() {
        let parking = WidgetParking(
            latitude: 38.5449, longitude: -121.7405,
            savedAt: now.addingTimeInterval(-(3 * 3600 + 20 * 60)))
        let age = parking.ageComponents(from: now)
        XCTAssertEqual(age.hours, 3)
        XCTAssertEqual(age.minutes, 20)
        XCTAssertEqual(parking.ageText(from: now), "3 h 20 min")
        XCTAssertEqual(parking.coordinateText, "38.5449, -121.7405")
        XCTAssertEqual(parking.deepLink.absoluteString, "vela://parking")
    }

    func testParkingAgeNeverGoesNegative() {
        let parking = WidgetParking(
            latitude: 0, longitude: 0, savedAt: now.addingTimeInterval(600))
        XCTAssertEqual(parking.ageComponents(from: now).hours, 0)
        XCTAssertEqual(parking.ageText(from: now), "0 min")
    }

    // MARK: Board

    func testBoardKeepsSoonestLinesAndThreeDeparturesPerLine() {
        let board = WidgetSnapshotBuilder.board(
            stopName: "Davis Downtown",
            latitude: 38.5449,
            longitude: -121.7405,
            fetchedAt: now.addingTimeInterval(-60),
            refreshFailed: false,
            lines: [
                WidgetBoardLine(label: "E", mode: "BUS", headsign: "Sacramento", color: "#1F7A3D",
                                departures: [departure(minutes: 9), departure(minutes: 4, realtime: true),
                                             departure(minutes: 14), departure(minutes: 24)]),
                WidgetBoardLine(label: "Z", mode: "BUS", headsign: "UC Davis", color: nil,
                                departures: [departure(minutes: 6)]),
                WidgetBoardLine(label: "A", mode: "BUS", headsign: "Woodland", color: nil,
                                departures: [departure(minutes: 2)]),
                WidgetBoardLine(label: "Q", mode: "BUS", headsign: "Nowhere", color: nil,
                                departures: [departure(minutes: 8)]),
            ],
            now: now)
        XCTAssertEqual(board?.stopName, "Davis Downtown")
        XCTAssertEqual(board?.lines.count, 3)
        XCTAssertEqual(board?.lines.first?.label, "A")
        let lineE = board?.lines.first { $0.label == "E" }
        XCTAssertEqual(lineE?.departures.map { $0.minutes(from: now) }, [4, 9, 14])
        XCTAssertEqual(lineE?.departures.first?.realtime, true)
    }

    func testBoardDropsPastDeparturesAndEmptyLinesButKeepsTheStop() {
        let past = WidgetSnapshotBuilder.board(
            stopName: "Davis Downtown", latitude: 38.5449, longitude: -121.7405,
            fetchedAt: now, refreshFailed: false,
            lines: [
                WidgetBoardLine(label: "E", mode: "BUS", headsign: nil, color: nil,
                                departures: [departure(minutes: -5)]),
            ],
            now: now)
        XCTAssertEqual(past?.lines.count, 0)
        XCTAssertEqual(past?.stopName, "Davis Downtown")
        XCTAssertEqual(past?.deepLink.absoluteString, "vela://board")

        let unnamed = WidgetSnapshotBuilder.board(
            stopName: "", latitude: 0, longitude: 0, fetchedAt: nil, refreshFailed: false,
            lines: [], now: now)
        XCTAssertNil(unnamed)
    }

    func testBoardStaleStateIsHonestAboutRefreshTime() {
        let fresh = WidgetBoard(
            stopName: "Davis Downtown", latitude: 1, longitude: 2,
            fetchedAt: now.addingTimeInterval(-5 * 60), refreshFailed: false, lines: [])
        XCTAssertFalse(fresh.isStale(asOf: now))
        XCTAssertTrue(fresh.updatedText().hasPrefix("Updated "))

        let old = WidgetBoard(
            stopName: "Davis Downtown", latitude: 1, longitude: 2,
            fetchedAt: now.addingTimeInterval(-21 * 60), refreshFailed: false, lines: [])
        XCTAssertTrue(old.isStale(asOf: now))

        let failed = WidgetBoard(
            stopName: "Davis Downtown", latitude: 1, longitude: 2,
            fetchedAt: now.addingTimeInterval(-60), refreshFailed: true, lines: [])
        XCTAssertTrue(failed.isStale(asOf: now))

        let never = WidgetBoard(
            stopName: "Davis Downtown", latitude: 1, longitude: 2,
            fetchedAt: nil, refreshFailed: false, lines: [])
        XCTAssertTrue(never.isStale(asOf: now))
        XCTAssertEqual(never.updatedText(), "No update yet")
    }

    func testDepartureCountdownIsCeiledAndNeverNegative() {
        XCTAssertEqual(departure(minutes: 4).minutes(from: now), 4)
        XCTAssertEqual(departure(minutes: 0).minutesText(from: now), "Now")
        XCTAssertEqual(departure(minutes: -3).minutes(from: now), 0)
        let secondsAway = WidgetDeparture(
            epochSec: Int64(now.timeIntervalSince1970) + 30, realtime: false, clockText: nil)
        XCTAssertEqual(secondsAway.minutes(from: now), 1)
    }

    // MARK: App Group payload

    func testAppGroupPayloadRoundTrips() throws {
        let suite = "app.vela.ios.tests.widgets"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let store = WidgetSnapshotStore(defaults: defaults)

        XCTAssertNil(store.load())
        let snapshot = WidgetSnapshot(
            shortcuts: [WidgetShortcut(kind: .home, name: "Home", address: "620 G St, Davis, CA 95616")],
            parking: WidgetParking(
                latitude: 38.5449, longitude: -121.7405,
                savedAt: now.addingTimeInterval(-3600)),
            board: WidgetBoard(
                stopName: "Davis Downtown", latitude: 38.5449, longitude: -121.7405,
                fetchedAt: now.addingTimeInterval(-120), refreshFailed: false,
                lines: [WidgetBoardLine(
                    label: "E", mode: "BUS", headsign: "Sacramento", color: "#1F7A3D",
                    departures: [departure(minutes: 4, realtime: true)])]),
            writtenAt: now)
        XCTAssertTrue(store.save(snapshot))
        let loaded = try XCTUnwrap(store.load())
        XCTAssertEqual(loaded, snapshot)
        XCTAssertEqual(loaded.board?.lines.first?.departures.first?.realtime, true)
        XCTAssertEqual(loaded.parking?.savedAt.timeIntervalSince1970 ?? 0,
                       snapshot.parking?.savedAt.timeIntervalSince1970 ?? -1,
                       accuracy: 0.001)

        store.clear()
        XCTAssertNil(store.load())
    }

    func testAppGroupPayloadRejectsGarbage() throws {
        let suite = "app.vela.ios.tests.widgets.garbage"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let store = WidgetSnapshotStore(defaults: defaults)
        defaults.set(Data("not json".utf8), forKey: WidgetSnapshotStore.defaultsKey)
        XCTAssertNil(store.load())
        defaults.removePersistentDomain(forName: suite)
    }

    func testPreviewSampleFillsEveryWidget() throws {
        let preview = WidgetSnapshot.preview
        XCTAssertEqual(preview.shortcuts.count, 2)
        XCTAssertNotNil(preview.parking)
        XCTAssertEqual(preview.board?.lines.count, 2)
        XCTAssertFalse(try XCTUnwrap(preview.board).isStale(asOf: Date()))
    }

    // MARK: Deep link

    func testBoardDeepLinkUsesTheSingleRouter() {
        XCTAssertEqual(VelaDeepLink.board.url.absoluteString, "vela://board")
        switch VelaDeepLinkRouter.parse("vela://board") {
        case .success(let link):
            XCTAssertEqual(link, .board)
        case .failure(let error):
            XCTFail("vela://board failed: \(error)")
        }
        switch VelaDeepLinkRouter.parse("vela://board/stop") {
        case .success(let link):
            XCTFail("Unexpected board route \(link)")
        case .failure(let error):
            XCTAssertEqual(error, .unknownRoute)
        }
    }
}
