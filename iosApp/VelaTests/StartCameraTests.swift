import Foundation
import XCTest
@testable import Vela

/// START-LOCATION: the launch camera's precedence, deadline, cancellation and persisted record.
final class StartCameraTests: XCTestCase {
    private let paris = LaunchOptions.Camera(latitude: 48.8566, longitude: 2.3522, zoom: 12)
    private let davis = LaunchOptions.Camera(latitude: 38.5449, longitude: -121.7405, zoom: 13)

    private func makeStore() -> (StartCameraStore, UserDefaults) {
        let suite = "app.vela.ios.tests.startCamera.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (StartCameraStore(defaults: defaults), defaults)
    }

    func testExplicitCameraWinsOverTheLastCameraAndThePosition() {
        let (store, _) = makeStore()
        store.save(paris)
        let camera = StartCamera(explicit: davis, store: store)
        XCTAssertEqual(camera.decision.camera, davis)
        XCTAssertEqual(camera.decision.source, .explicit)

        camera.begin(granted: true)
        XCTAssertNil(camera.fix(latitude: 38.6, longitude: -121.7),
                     "an explicit -VelaStartCamera must never be moved by a fix")
        XCTAssertEqual(camera.decision.source, .explicit)
    }

    func testPositionWinsOverTheLastCameraAndOpensAtCityZoom() {
        let (store, _) = makeStore()
        store.save(paris)
        let camera = StartCamera(explicit: nil, store: store)
        XCTAssertEqual(camera.decision.camera, paris, "the map opens on the last camera first")
        XCTAssertEqual(camera.decision.source, .last)

        camera.begin(granted: true)
        let move = camera.fix(latitude: 38.5449, longitude: -121.7405)
        XCTAssertEqual(move?.source, .position)
        XCTAssertEqual(move?.camera.latitude, 38.5449)
        XCTAssertEqual(move?.camera.longitude, -121.7405)
        XCTAssertEqual(move?.camera.zoom, StartCamera.positionZoom)
        XCTAssertEqual(StartCamera.positionZoom, 14, "a city view, not the default zoom 12")
        XCTAssertEqual(camera.decision.source, .position)
    }

    func testLastCameraWinsWithoutAFix() {
        let (store, _) = makeStore()
        store.save(davis)
        let camera = StartCamera(explicit: nil, store: store)
        XCTAssertEqual(camera.decision.camera, davis)
        XCTAssertEqual(camera.decision.source, .last)
    }

    func testDefaultWhenNothingIsKnownYet() {
        let (store, _) = makeStore()
        let camera = StartCamera(explicit: nil, store: store)
        XCTAssertEqual(camera.decision.source, .fallback)
        XCTAssertEqual(camera.decision.camera, LaunchOptions.fixtures["sf"])
    }

    func testFixAfterTheDeadlineLeavesTheCameraWhereItWas() {
        let (store, _) = makeStore()
        store.save(davis)
        var now = Date(timeIntervalSince1970: 1_000)
        let camera = StartCamera(explicit: nil, store: store, now: { now })
        camera.begin(granted: true)
        now = now.addingTimeInterval(StartCamera.deadline + 0.01)
        XCTAssertNil(camera.fix(latitude: 38.6, longitude: -121.7))
        XCTAssertEqual(camera.decision.camera, davis)
        XCTAssertEqual(camera.decision.source, .last)
    }

    func testFixAtTheDeadlineStillMoves() {
        let (store, _) = makeStore()
        var now = Date(timeIntervalSince1970: 1_000)
        let camera = StartCamera(explicit: nil, store: store, now: { now })
        camera.begin(granted: true)
        now = now.addingTimeInterval(StartCamera.deadline)
        XCTAssertEqual(camera.fix(latitude: 48.8566, longitude: 2.3522)?.source, .position)
    }

    func testAPanCancelsTheLateMoveForGood() {
        let (store, _) = makeStore()
        let camera = StartCamera(explicit: nil, store: store)
        camera.begin(granted: true)
        camera.userPanned()
        XCTAssertNil(camera.fix(latitude: 48.8566, longitude: 2.3522),
                     "a user who already panned keeps the camera")
        XCTAssertTrue(camera.userMoved)
    }

    func testAnExplicitTargetCancelsTheLateMove() {
        let (store, _) = makeStore()
        let camera = StartCamera(explicit: nil, store: store)
        camera.begin(granted: true)
        camera.cancel()
        XCTAssertNil(camera.fix(latitude: 48.8566, longitude: 2.3522),
                     "a link, saved place or route outranks the position")
    }

    func testUndeterminedPermissionWaitsForTheAnswer() {
        let (store, _) = makeStore()
        var now = Date(timeIntervalSince1970: 1_000)
        let camera = StartCamera(explicit: nil, store: store, now: { now })
        camera.begin(granted: false)
        XCTAssertNil(camera.fix(latitude: 48.8566, longitude: 2.3522),
                     "no move before the user answers the prompt")

        now = now.addingTimeInterval(30)
        XCTAssertTrue(camera.permissionAnswered(granted: true))
        now = now.addingTimeInterval(0.5)
        XCTAssertEqual(camera.fix(latitude: 48.8566, longitude: 2.3522)?.source, .position,
                       "a late grant opens a fresh deadline")
    }

    func testDeniedPermissionNeverMoves() {
        let (store, _) = makeStore()
        let camera = StartCamera(explicit: nil, store: store)
        camera.begin(granted: false)
        XCTAssertFalse(camera.permissionAnswered(granted: false))
        XCTAssertNil(camera.fix(latitude: 48.8566, longitude: 2.3522))
    }

    func testOnlyTheFirstFixMovesTheCamera() {
        let (store, _) = makeStore()
        let camera = StartCamera(explicit: nil, store: store)
        camera.begin(granted: true)
        XCTAssertNotNil(camera.fix(latitude: 48.8566, longitude: 2.3522))
        XCTAssertNil(camera.fix(latitude: 48.9, longitude: 2.4),
                     "one animation, not a camera that follows every fix")
    }

    func testInvalidFixesAreIgnored() {
        let (store, _) = makeStore()
        let camera = StartCamera(explicit: nil, store: store)
        camera.begin(granted: true)
        XCTAssertNil(camera.fix(latitude: 0, longitude: 0))
        XCTAssertNil(camera.fix(latitude: 95, longitude: 2))
        XCTAssertNil(camera.fix(latitude: .nan, longitude: 2))
        XCTAssertNil(camera.fix(latitude: 48.8566, longitude: 200))
    }

    func testStoredCameraRoundTrips() {
        let suite = "app.vela.ios.tests.startCamera.roundTrip"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        StartCameraStore(defaults: defaults).save(paris)
        XCTAssertEqual(StartCameraStore(defaults: defaults).load(), paris)
    }

    func testInvalidCameraIsNeverStored() {
        let (store, defaults) = makeStore()
        store.save(paris)
        store.save(LaunchOptions.Camera(latitude: 0, longitude: 0, zoom: 14))
        store.save(LaunchOptions.Camera(latitude: 120, longitude: 2, zoom: 14))
        store.save(LaunchOptions.Camera(latitude: 48, longitude: 2, zoom: 30))
        XCTAssertEqual(store.load(), paris, "an invalid camera must not replace the last good one")
        XCTAssertEqual(StartCameraStore(defaults: defaults).load(), paris)
    }

    func testAStoredCameraFromAnotherVersionIsIgnored() {
        let (_, defaults) = makeStore()
        let future = """
        {"version":2,"latitude":48.8566,"longitude":2.3522,"zoom":12}
        """.data(using: .utf8)!
        defaults.set(future, forKey: StartCameraStore.key)
        XCTAssertNil(StartCameraStore(defaults: defaults).load())
        XCTAssertEqual(StartCameraStore.key, "app.vela.ios.map.last_camera.v1")
    }

    func testRememberWritesThroughTheDecision() {
        let (store, defaults) = makeStore()
        let camera = StartCamera(explicit: nil, store: store)
        camera.remember(latitude: 48.8566, longitude: 2.3522, zoom: 11)
        XCTAssertEqual(StartCameraStore(defaults: defaults).load(),
                       LaunchOptions.Camera(latitude: 48.8566, longitude: 2.3522, zoom: 11))
    }
}
