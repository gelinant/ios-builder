import ActivityKit
import XCTest
@testable import Vela

final class LiveActivityTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testMappingCarriesGuidanceEtaModeAndProgress() throws {
        let input = NavActivityInput(
            active: true,
            travelMode: "DRIVE",
            maneuverKind: "TURN_RIGHT",
            instruction: "Turn right",
            streetName: "10th Street",
            distanceToNextMeters: 120,
            routeDistanceMeters: 2_000,
            remainingDistanceMeters: 500,
            remainingDurationSeconds: 90,
            destinationName: "Fixture destination")
        let sample = try XCTUnwrap(NavActivityStateMapper.map(input, now: now))
        let state = sample.content
        XCTAssertEqual(state.maneuverKind, "TURN_RIGHT")
        XCTAssertEqual(state.instruction, "Turn right")
        XCTAssertEqual(state.streetName, "10th Street")
        XCTAssertEqual(state.distanceToNextManeuverMeters, 120)
        XCTAssertEqual(state.remainingDistanceMeters, 500)
        XCTAssertEqual(state.remainingDurationSeconds, 90)
        XCTAssertEqual(state.arrivalDate, now.addingTimeInterval(90))
        XCTAssertEqual(state.mode, .drive)
        XCTAssertEqual(state.progress, 0.75, accuracy: 0.0001)
        XCTAssertFalse(state.offRoute)
        XCTAssertFalse(state.arrived)
    }

    func testMappingSupportsWalkingAndRejectsOtherModes() throws {
        var input = NavActivityInput(active: true, travelMode: "WALK", routeDistanceMeters: 100)
        input.remainingDistanceMeters = 125
        let walking = try XCTUnwrap(NavActivityStateMapper.map(input, now: now))
        XCTAssertEqual(walking.content.mode, .walk)
        XCTAssertEqual(walking.content.progress, 0)
        input.travelMode = "BICYCLE"
        XCTAssertNil(NavActivityStateMapper.map(input, now: now))
    }

    func testInstructionAndRerouteChangesBypassThrottle() throws {
        let first = try XCTUnwrap(NavActivityStateMapper.map(activeInput(), now: now))
        var changed = activeInput()
        changed.instruction = "Keep left"
        let instruction = try XCTUnwrap(NavActivityStateMapper.map(
            changed, now: now.addingTimeInterval(1)))
        XCTAssertTrue(NavActivityUpdatePolicy.shouldUpdate(
            previous: first, candidate: instruction, now: now.addingTimeInterval(1)))

        changed = activeInput()
        changed.routeRevision += 1
        let reroute = try XCTUnwrap(NavActivityStateMapper.map(
            changed, now: now.addingTimeInterval(1)))
        XCTAssertTrue(NavActivityUpdatePolicy.shouldUpdate(
            previous: first, candidate: reroute, now: now.addingTimeInterval(1)))

        changed = activeInput()
        changed.offRoute = true
        let offRoute = try XCTUnwrap(NavActivityStateMapper.map(
            changed, now: now.addingTimeInterval(1)))
        XCTAssertTrue(NavActivityUpdatePolicy.shouldUpdate(
            previous: first, candidate: offRoute, now: now.addingTimeInterval(1)))
    }

    func testDistanceAndFiveSecondThrottle() throws {
        let first = try XCTUnwrap(NavActivityStateMapper.map(activeInput(), now: now))
        var smallInput = activeInput()
        smallInput.distanceToNextMeters -= 10
        smallInput.remainingDistanceMeters -= 10
        let small = try XCTUnwrap(NavActivityStateMapper.map(
            smallInput, now: now.addingTimeInterval(4)))
        XCTAssertFalse(NavActivityUpdatePolicy.shouldUpdate(
            previous: first, candidate: small, now: now.addingTimeInterval(4)))
        XCTAssertTrue(NavActivityUpdatePolicy.shouldUpdate(
            previous: first, candidate: small, now: now.addingTimeInterval(5)))

        var largeInput = activeInput()
        largeInput.distanceToNextMeters -= NavActivityTiming.distanceThresholdMeters
        let large = try XCTUnwrap(NavActivityStateMapper.map(
            largeInput, now: now.addingTimeInterval(1)))
        XCTAssertTrue(NavActivityUpdatePolicy.shouldUpdate(
            previous: first, candidate: large, now: now.addingTimeInterval(1)))
    }

    func testReducerStartsUpdatesArrivesOnceAndEnds() throws {
        let first = try XCTUnwrap(NavActivityStateMapper.map(activeInput(), now: now))
        var reducer = NavActivityReducer()
        XCTAssertEqual(reducer.publish(first, now: now), .start(first))
        XCTAssertEqual(reducer.publish(first, now: now), nil)

        var arrivedInput = activeInput()
        arrivedInput.arrived = true
        arrivedInput.remainingDistanceMeters = 0
        arrivedInput.remainingDurationSeconds = 0
        let arrival = try XCTUnwrap(NavActivityStateMapper.map(
            arrivedInput, now: now.addingTimeInterval(2)))
        let dismissal = now.addingTimeInterval(2 + NavActivityTiming.arrivalDismissalDelay)
        XCTAssertEqual(
            reducer.publish(arrival, now: now.addingTimeInterval(2)),
            .arrive(arrival, dismissalDate: dismissal))
        XCTAssertEqual(reducer.publish(arrival, now: now.addingTimeInterval(3)), nil)
        let inactive = try XCTUnwrap(NavActivityStateMapper.map(NavActivityInput(), now: now))
        XCTAssertEqual(reducer.publish(inactive, now: now.addingTimeInterval(3)), .end)
        XCTAssertEqual(reducer.phase, .idle)
        XCTAssertEqual(reducer.publish(inactive, now: now.addingTimeInterval(4)), nil)
    }

    func testReducerEndsNavigationWithoutArrival() throws {
        let first = try XCTUnwrap(NavActivityStateMapper.map(activeInput(), now: now))
        let inactive = try XCTUnwrap(NavActivityStateMapper.map(NavActivityInput(), now: now))
        var reducer = NavActivityReducer()
        XCTAssertEqual(reducer.publish(first, now: now), .start(first))
        XCTAssertEqual(reducer.publish(inactive, now: now.addingTimeInterval(1)), .end)
        XCTAssertEqual(reducer.phase, .idle)
    }

    func testStaleActivityAdoptionHasAMaximumAge() throws {
        let fresh = try XCTUnwrap(NavActivityStateMapper.map(activeInput(), now: now)).content
        XCTAssertTrue(NavActivityStalePolicy.shouldAdopt(
            fresh, now: now.addingTimeInterval(NavActivityTiming.staleAfter - 1)))
        XCTAssertFalse(NavActivityStalePolicy.shouldAdopt(
            fresh, now: now.addingTimeInterval(NavActivityTiming.staleAfter)))
        XCTAssertEqual(
            NavActivityStalePolicy.expiration(of: fresh),
            now.addingTimeInterval(NavActivityTiming.staleAfter))
    }

    func testAppAndExtensionDeclareLiveActivities() throws {
        let info = try XCTUnwrap(Bundle.main.infoDictionary)
        XCTAssertEqual(info["NSSupportsLiveActivities"] as? Bool, true)
        let url = Bundle.main.bundleURL.appendingPathComponent("PlugIns/NavActivityExtension.appex")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "widget extension not embedded")
        let bundle = try XCTUnwrap(Bundle(url: url))
        XCTAssertEqual(bundle.bundleIdentifier, "app.vela.ios.navactivity")
        let extensionInfo = try XCTUnwrap(bundle.infoDictionary)
        let point = try XCTUnwrap(extensionInfo["NSExtension"] as? [String: Any])
        XCTAssertEqual(point["NSExtensionPointIdentifier"] as? String, "com.apple.widgetkit-extension")
    }

    @MainActor
    func testActivityKitStartsUpdatesAndEndsWhenSupported() async throws {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            throw XCTSkip("Live Activities are disabled or unsupported on this test host")
        }
        for existing in Activity<NavActivityAttributes>.activities {
            await existing.end(nil, dismissalPolicy: .immediate)
        }
        let controller = NavActivityController()
        controller.start(now: now)
        addTeardownBlock { @MainActor in
            for existing in Activity<NavActivityAttributes>.activities {
                await existing.end(nil, dismissalPolicy: .immediate)
            }
        }

        controller.publish(activeInput(), now: now)
        let activity = try XCTUnwrap(Activity<NavActivityAttributes>.activities.first {
            $0.content.state.instruction == "Turn right"
        }, "navigation start did not request an Activity")
        XCTAssertEqual(activity.content.state.remainingDistanceMeters, 1_000)

        var moved = activeInput()
        moved.distanceToNextMeters -= 40
        moved.remainingDistanceMeters -= 40
        moved.remainingDurationSeconds -= 5
        controller.publish(moved, now: now.addingTimeInterval(1))
        let updated = await waitForActivity {
            activity.content.state.remainingDistanceMeters == 960
        }
        XCTAssertTrue(updated, "ActivityKit did not receive the changed ContentState")

        controller.publish(NavActivityInput(), now: now.addingTimeInterval(2))
        let ended = await waitForActivity {
            activity.activityState != .active
        }
        XCTAssertTrue(ended, "End did not end the Activity")
        XCTAssertEqual(controller.updateCount, 1)
        XCTAssertEqual(controller.endCount, 1)
    }

    private func activeInput() -> NavActivityInput {
        NavActivityInput(
            active: true,
            maneuverKind: "TURN_RIGHT",
            instruction: "Turn right",
            streetName: "10th Street",
            distanceToNextMeters: 120,
            routeDistanceMeters: 2_000,
            remainingDistanceMeters: 1_000,
            remainingDurationSeconds: 120,
            destinationName: "Fixture destination")
    }

    @MainActor
    private func waitForActivity(_ condition: @escaping () -> Bool) async -> Bool {
        for _ in 0..<40 {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return condition()
    }
}
