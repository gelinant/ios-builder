import CoreLocation
import Foundation

/// Launch arguments the UI tests and scripts/ios/ci-ipa.sh pass (docs/ios/TESTING-IOS.md), read
/// once from the process arguments as `-Name value` pairs:
///
/// - `-VelaStartCamera <fixture>|<lat>,<lng>[,<zoom>]`: the first camera. Fixtures: `sf`, `davis`,
///   `sacramento`. Without the argument the map opens on the last camera the user left, then on
///   San Francisco at zoom 12 the first time (START-LOCATION).
/// - `-VelaDeterministic YES`: no UIKit or camera animation, for stable screenshots.
/// - `-VelaFollowUser YES`: follow the user location at launch when permission is already given,
///   for location replays.
/// - `-VelaLanguage fr`: use an in-app language for this launch without persisting it.
/// - `-VelaResetSettings YES`: clear the two settings suites before anything reads them (Debug).
///   The reset also records that the first-run Google question was answered, so existing scenarios
///   start on the map. Pass `-VelaFirstRunConsent YES` with it to keep the question open.
/// - `-VelaTransitFixture YES`: start the recorded San Francisco transit preview (Debug).
/// - `-VelaTransitBoardTest YES`: open the Ferry Building stop board at launch (Debug).
/// - `-VelaVoiceFixture YES`: copy the neural-voice model shipped in the test bundle (Debug).
/// - `-VelaVoiceDisableNeural YES`: force AVSpeechSynthesizer even with a model installed (Debug).
/// - `-VelaStreetViewFixture YES`: open the interactive Street View viewer on its synthetic
///   equirect fixture at launch (Debug), for the runner's no-imagery case (docs/ios/STREET-VIEW.md).
/// - `-VelaDemoReplay latest|<trip id>`: open the recorded-trace demo replay at launch (Debug).
///   It is a labelled replay, never live guidance: no voice, no ETA and no Live Activity.
/// - `-VelaLaunchProbe YES`: mount the read-only PERF-1 launch probe (Diagnostics). It samples the
///   process footprint and the four launch moments and exposes them as one accessibility label;
///   without the flag it has no timer and no view.
/// - `-VelaPerfLegacy YES`: measure the pre-PERF-1 launch path (the region table parsed on the main
///   thread and every facet started before the first frame). It exists so one run can compare both
///   cases; it changes nothing the user sees except the timing of work that normally starts after
///   the first frame.
struct LaunchOptions {
    struct Camera: Equatable {
        let latitude: Double
        let longitude: Double
        let zoom: Double

        var center: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }

    static let fixtures: [String: Camera] = [
        "sf": Camera(latitude: 37.7749, longitude: -122.4194, zoom: 12),
        "davis": Camera(latitude: 38.5449, longitude: -121.7405, zoom: 13),
        "sacramento": Camera(latitude: 38.5816, longitude: -121.4944, zoom: 12),
    ]

    /// The camera the map is built with: the `-VelaStartCamera` target, else the last camera the
    /// user left, else the default. START-LOCATION may then move it onto the user's position once.
    let camera: Camera
    /// The `-VelaStartCamera` target alone. A launch that named none still opens on `camera`, but
    /// does not count as an explicit target for the position decision.
    let explicitCamera: Camera?
    let deterministic: Bool
    let followUser: Bool
    let offlineTest: Bool
    let language: String?
    let resetSettings: Bool
    /// Keep the first-run Google question unanswered even after a Debug settings reset.
    let firstRunConsent: Bool
    let transitFixture: Bool
    let transitBoardTest: Bool
    let voiceFixture: Bool
    let voiceDisableNeural: Bool
    let streetViewFixture: Bool
    /// A recorded trip to replay at launch, or `latest`; nil leaves the map on screen.
    let demoReplay: String?
    /// PERF-1: mount the launch probe; it has no cost without the flag.
    let launchProbe: Bool
    /// PERF-1: measure the old launch path, for a before/after comparison in one run.
    let perfLegacy: Bool

    static let current = LaunchOptions(
        arguments: ProcessInfo.processInfo.arguments,
        lastCamera: StartCameraStore().load())

    /// `lastCamera` is passed explicitly so a test-built argument list describes one launch and
    /// never inherits the simulator's saved camera.
    init(arguments: [String], lastCamera: Camera? = nil) {
        func value(_ name: String) -> String? {
            guard let i = arguments.firstIndex(of: "-" + name), i + 1 < arguments.count else { return nil }
            return arguments[i + 1]
        }
        func flag(_ name: String) -> Bool {
            guard let v = value(name)?.lowercased() else { return false }
            return v == "yes" || v == "true" || v == "1"
        }
        let parsed = Self.parseCamera(value("VelaStartCamera"))
        explicitCamera = parsed
        camera = StartCamera.initial(explicit: parsed, last: lastCamera).camera
        deterministic = flag("VelaDeterministic")
        followUser = flag("VelaFollowUser")
        offlineTest = flag("VelaOfflineTest")
        language = value("VelaLanguage")
        resetSettings = flag("VelaResetSettings")
        firstRunConsent = flag("VelaFirstRunConsent")
        transitFixture = flag("VelaTransitFixture")
        transitBoardTest = flag("VelaTransitBoardTest")
        voiceFixture = flag("VelaVoiceFixture")
        voiceDisableNeural = flag("VelaVoiceDisableNeural")
        streetViewFixture = flag("VelaStreetViewFixture")
        let replay = value("VelaDemoReplay")?.trimmingCharacters(in: .whitespaces)
        demoReplay = (replay?.isEmpty == false) ? replay : nil
        launchProbe = flag("VelaLaunchProbe")
        perfLegacy = flag("VelaPerfLegacy")
    }

    /// A fixture name or `lat,lng[,zoom]`; nil when unreadable or out of range.
    static func parseCamera(_ text: String?) -> Camera? {
        guard let text = text?.trimmingCharacters(in: .whitespaces).lowercased(), !text.isEmpty else { return nil }
        if let fixture = fixtures[text] { return fixture }
        let parts = text.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2 || parts.count == 3, let lat = parts[0], let lng = parts[1],
              (-90...90).contains(lat), (-180...180).contains(lng) else { return nil }
        let zoom: Double? = parts.count == 3 ? parts[2] : MapDefaults.initialZoom
        guard let zoom, (0...22).contains(zoom) else { return nil }
        return Camera(latitude: lat, longitude: lng, zoom: zoom)
    }

    /// Whether camera moves animate.
    var animates: Bool { !deterministic }
}
