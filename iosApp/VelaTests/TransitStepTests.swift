import XCTest
import VelaCore
@testable import Vela

/// GO-STEPS: the Live Activity intent, the command router and the activity content after a step.
@MainActor
final class TransitStepTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testIntentMapsToTheStepCommandAndItsSession() async throws {
        let saved = TransitStepRouter.handler
        defer { TransitStepRouter.handler = saved }
        var received: [(TransitStepCommand, Int64)] = []
        TransitStepRouter.handler = { received.append(($0, $1)) }

        _ = try await TransitStepIntent(.previous, sessionId: 7).perform()
        _ = try await TransitStepIntent(.next, sessionId: 8).perform()

        XCTAssertEqual(received.map(\.0), [.previous, .next])
        XCTAssertEqual(received.map(\.1), [7, 8])
    }

    func testCommandMovesTheSessionAndChangesTheActivityContent() {
        let session = TransitSession.companion.detached()
        XCTAssertTrue(session.start(trip: TransitPreview.shared.sf, destinationName: "Ferry Building"))
        let id = Int64(session.state.value.sessionId)
        var reducer = TransitActivityReducer()
        let before = TransitActivityStateMapper.map(TransitActivityInput(session.state.value), now: now)
        XCTAssertEqual(reducer.publish(before, now: now), .start(before))
        XCTAssertNil(before.content.previousStepTitle)
        XCTAssertEqual(before.content.nextStepTitle, "Board K at Metro Van Ness Station")

        XCTAssertTrue(TransitStepCommands.run(.next, sessionId: id, session: session))
        let after = TransitActivityStateMapper.map(
            TransitActivityInput(session.state.value), now: now.addingTimeInterval(1))
        XCTAssertEqual(after.content.legIndex, 1)
        XCTAssertNotEqual(after.content.instruction, before.content.instruction)
        XCTAssertEqual(after.content.previousStepTitle, "Walk to Metro Van Ness Station")
        XCTAssertEqual(reducer.publish(after, now: now.addingTimeInterval(1)), .update(after),
                       "the step change did not reach the activity at once")

        XCTAssertTrue(TransitStepCommands.run(.previous, sessionId: id, session: session))
        let back = TransitActivityStateMapper.map(
            TransitActivityInput(session.state.value), now: now.addingTimeInterval(2))
        XCTAssertEqual(back.content.legIndex, 0)
        XCTAssertEqual(reducer.publish(back, now: now.addingTimeInterval(2)), .update(back))
    }

    func testCommandWithoutAMatchingSessionFailsGracefully() {
        let session = TransitSession.companion.detached()
        XCTAssertFalse(TransitStepCommands.run(.next, sessionId: 1, session: session),
                       "a step ran without a session")
        XCTAssertTrue(session.start(trip: TransitPreview.shared.sf, destinationName: "Ferry Building"))
        let id = Int64(session.state.value.sessionId)
        XCTAssertFalse(TransitStepCommands.run(.next, sessionId: id + 1, session: session),
                       "an older activity moved a newer trip")
        XCTAssertEqual(session.state.value.legIndex, 0)
    }

    func testArrivalHasNoStepButtons() {
        let session = TransitSession.companion.detached()
        XCTAssertTrue(session.start(trip: TransitPreview.shared.sf, destinationName: "Ferry Building"))
        for _ in 0..<4 { _ = session.nextStep() }
        let arrived = TransitActivityStateMapper.map(TransitActivityInput(session.state.value), now: now)
        XCTAssertTrue(arrived.content.arrived)
        XCTAssertNil(arrived.content.previousStepTitle)
        XCTAssertNil(arrived.content.nextStepTitle)
    }
}
