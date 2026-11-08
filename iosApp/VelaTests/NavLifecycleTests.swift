import XCTest
@testable import Vela

/// N-3: system events may cut speech or move the camera, never end or restart the drive.
final class NavLifecycleTests: XCTestCase {
    func testBackgroundAndScreenLockLeaveTheDriveAlone() {
        XCTAssertEqual(
            NavLifecyclePolicy.action(.background, navigating: true, paused: false, cameraDetached: false),
            NavLifecyclePolicy.Action.none)
        XCTAssertEqual(
            NavLifecyclePolicy.action(.background, navigating: true, paused: true, cameraDetached: true),
            NavLifecyclePolicy.Action.none)
    }

    func testForegroundRefollowsOnlyLiveGuidance() {
        XCTAssertEqual(
            NavLifecyclePolicy.action(.foreground, navigating: true, paused: false, cameraDetached: false),
            NavLifecyclePolicy.Action.followCamera)
        XCTAssertEqual(
            NavLifecyclePolicy.action(.foreground, navigating: true, paused: true, cameraDetached: false),
            NavLifecyclePolicy.Action.none,
            "a paused drive keeps its frozen camera")
        XCTAssertEqual(
            NavLifecyclePolicy.action(.foreground, navigating: true, paused: false, cameraDetached: true),
            NavLifecyclePolicy.Action.none,
            "a driver who panned keeps the detached camera")
        XCTAssertEqual(
            NavLifecyclePolicy.action(.foreground, navigating: false, paused: false, cameraDetached: false),
            NavLifecyclePolicy.Action.none)
    }

    func testACallCutsSpeechThenRearmsWithoutPausing() {
        XCTAssertEqual(
            NavLifecyclePolicy.action(.audioInterruptionBegan, navigating: true, paused: false, cameraDetached: false),
            NavLifecyclePolicy.Action.cutSpeech)
        XCTAssertEqual(
            NavLifecyclePolicy.action(.audioInterruptionEnded, navigating: true, paused: false, cameraDetached: false),
            NavLifecyclePolicy.Action.rearmAudio)
    }

    func testBluetoothRouteChangeRearmsAudioOnly() {
        XCTAssertEqual(
            NavLifecyclePolicy.action(.audioRouteChanged, navigating: true, paused: false, cameraDetached: false),
            NavLifecyclePolicy.Action.rearmAudio)
    }

    func testInactiveGuidanceIgnoresEveryEvent() {
        let events: [NavLifecyclePolicy.Event] = [
            .background, .foreground, .audioInterruptionBegan, .audioInterruptionEnded, .audioRouteChanged,
        ]
        for event in events {
            XCTAssertEqual(
                NavLifecyclePolicy.action(event, navigating: false, paused: false, cameraDetached: false),
                NavLifecyclePolicy.Action.none)
        }
    }
}
