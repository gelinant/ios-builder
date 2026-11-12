import ActivityKit
import XCTest
@testable import Vela

final class TransitActivityTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testMappingKeepsScheduledAndLiveTimesSeparate() {
        var input = activeInput()
        input.scheduledDeparture = "9:24 AM"
        input.estimatedDeparture = "9:28 AM"
        input.scheduledArrival = "9:29 AM"
        input.delayMinutes = 4
        let state = TransitActivityStateMapper.map(input, now: now).content
        XCTAssertEqual(state.instruction, "Board at Metro Van Ness Station")
        XCTAssertEqual(state.scheduledDeparture, "9:24 AM")
        XCTAssertEqual(state.estimatedDeparture, "9:28 AM")
        XCTAssertEqual(state.scheduledArrival, "9:29 AM")
        XCTAssertNil(state.estimatedArrival)
        XCTAssertEqual(state.delayMinutes, 4)
        XCTAssertEqual(state.lineColorHex, "#437c93")
        XCTAssertEqual(state.stopsRemaining, 4)
    }

    func testWalkingAndAlightingInstructions() {
        var input = activeInput()
        input.legKind = "WALK"
        input.legIndex = 0
        input.walkingTarget = "Metro Van Ness Station"
        input.nextStop = input.walkingTarget
        input.stopsRemaining = -1
        XCTAssertEqual(
            TransitActivityStateMapper.map(input, now: now).content.instruction,
            "Walk to Metro Van Ness Station")

        input.legKind = "TRAM"
        input.legIndex = 1
        input.boarded = true
        input.nextStop = "Metro Embarcadero Station"
        input.alightStop = input.nextStop
        input.stopsRemaining = 1
        XCTAssertEqual(
            TransitActivityStateMapper.map(input, now: now).content.instruction,
            "Get off at Metro Embarcadero Station")
    }

    func testSemanticChangesBypassFiveSecondThrottle() {
        let first = TransitActivityStateMapper.map(activeInput(), now: now)
        var changed = activeInput()
        changed.boarded = true
        changed.nextStop = "Metro Powell Station/Downtown"
        changed.stopsRemaining = 2
        let candidate = TransitActivityStateMapper.map(changed, now: now.addingTimeInterval(1))
        XCTAssertTrue(TransitActivityUpdatePolicy.shouldUpdate(
            previous: first, candidate: candidate, now: now.addingTimeInterval(1)))
    }

    func testProgressOnlyChangeWaitsFiveSeconds() {
        let first = TransitActivityStateMapper.map(activeInput(), now: now)
        var changed = activeInput()
        changed.progress += 0.05
        let candidate = TransitActivityStateMapper.map(changed, now: now.addingTimeInterval(1))
        XCTAssertFalse(TransitActivityUpdatePolicy.shouldUpdate(
            previous: first, candidate: candidate, now: now.addingTimeInterval(1)))
        XCTAssertTrue(TransitActivityUpdatePolicy.shouldUpdate(
            previous: first, candidate: candidate, now: now.addingTimeInterval(5)))
    }

    func testReducerStartsUpdatesArrivesAndEnds() {
        var reducer = TransitActivityReducer()
        let first = TransitActivityStateMapper.map(activeInput(), now: now)
        XCTAssertEqual(reducer.publish(first, now: now), .start(first))
        XCTAssertNil(reducer.publish(first, now: now))

        var moved = activeInput()
        boarded(&moved)
        let update = TransitActivityStateMapper.map(moved, now: now.addingTimeInterval(1))
        XCTAssertEqual(reducer.publish(update, now: now.addingTimeInterval(1)), .update(update))

        var arrived = activeInput()
        arrived.arrived = true
        arrived.progress = 1
        let arrival = TransitActivityStateMapper.map(arrived, now: now.addingTimeInterval(2))
        let dismissal = now.addingTimeInterval(2 + TransitActivityTiming.arrivalDismissalDelay)
        XCTAssertEqual(
            reducer.publish(arrival, now: now.addingTimeInterval(2)),
            .arrive(arrival, dismissalDate: dismissal))
        var ended = activeInput()
        ended.active = false
        XCTAssertEqual(
            reducer.publish(TransitActivityStateMapper.map(ended, now: now), now: now.addingTimeInterval(3)),
            .end)
        XCTAssertEqual(reducer.phase, .idle)
    }

    func testNewSessionStartsInsteadOfUpdatingTheOldOne() {
        var reducer = TransitActivityReducer()
        let first = TransitActivityStateMapper.map(activeInput(), now: now)
        XCTAssertEqual(reducer.publish(first, now: now), .start(first))
        var next = activeInput()
        next.sessionId += 1
        let replacement = TransitActivityStateMapper.map(next, now: now.addingTimeInterval(1))
        XCTAssertEqual(reducer.publish(replacement, now: now.addingTimeInterval(1)), .start(replacement))
    }

    func testStaleActivityHasAMaximumAge() {
        let state = TransitActivityStateMapper.map(activeInput(), now: now).content
        XCTAssertTrue(TransitActivityStalePolicy.shouldAdopt(
            state, now: now.addingTimeInterval(TransitActivityTiming.staleAfter - 1)))
        XCTAssertFalse(TransitActivityStalePolicy.shouldAdopt(
            state, now: now.addingTimeInterval(TransitActivityTiming.staleAfter)))
    }

    @MainActor
    func testActivityKitStartsUpdatesAndEndsWhenSupported() async throws {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            throw XCTSkip("Live Activities are disabled or unsupported on this test host")
        }
        for existing in Activity<TransitActivityAttributes>.activities {
            await existing.end(nil, dismissalPolicy: .immediate)
        }
        let controller = TransitActivityController()
        controller.start(now: now)
        addTeardownBlock { @MainActor in
            for existing in Activity<TransitActivityAttributes>.activities {
                await existing.end(nil, dismissalPolicy: .immediate)
            }
        }

        controller.publish(activeInput(), now: now)
        let activity = try XCTUnwrap(Activity<TransitActivityAttributes>.activities.first {
            $0.content.state.instruction == "Board at Metro Van Ness Station"
        }, "transit start did not request an Activity")
        XCTAssertEqual(activity.content.state.stopsRemaining, 4)

        var moved = activeInput()
        boarded(&moved)
        controller.publish(moved, now: now.addingTimeInterval(1))
        let updated = await waitForActivity {
            activity.content.state.nextStop == "Metro Powell Station/Downtown"
                && activity.content.state.stopsRemaining == 2
        }
        XCTAssertTrue(updated, "ActivityKit did not receive the changed transit ContentState")

        var ended = activeInput()
        ended.active = false
        controller.publish(ended, now: now.addingTimeInterval(2))
        let didEnd = await waitForActivity { activity.activityState != .active }
        XCTAssertTrue(didEnd, "End did not end the transit Activity")
        XCTAssertEqual(controller.updateCount, 1)
        XCTAssertEqual(controller.endCount, 1)
    }

    private func boarded(_ input: inout TransitActivityInput) {
        input.boarded = true
        input.nextStop = "Metro Powell Station/Downtown"
        input.stopsRemaining = 2
        input.progress = 0.5
    }

    private func activeInput() -> TransitActivityInput {
        var input = TransitActivityInput()
        input.active = true
        input.destinationName = "Ferry Building"
        input.sessionId = 7
        input.legIndex = 1
        input.legCount = 3
        input.legKind = "TRAM"
        input.lineName = "K"
        input.lineColorHex = "#437c93"
        input.lineTextColorHex = "#FFFFFF"
        input.direction = "Embarcadero Station"
        input.nextStop = "Metro Van Ness Station"
        input.alightStop = "Metro Embarcadero Station"
        input.stopsRemaining = 4
        input.overallArrivalText = "9:39 AM"
        input.overallArrivalEpochSec = Int64(now.timeIntervalSince1970 + 720)
        input.progress = 1.0 / 3.0
        return input
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
