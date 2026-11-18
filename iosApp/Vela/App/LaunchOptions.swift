import CoreLocation
import Foundation
#if DEBUG
import UIKit
import VelaCore
#endif

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
/// - `-VelaResetSettings YES`: clear the settings and units suites before anything reads them
///   (Debug), and this file also clears the world layer suite, so the map layer switches start
///   off. The reset also records that the first-run Google question was answered, so existing
///   scenarios start on the map. Pass `-VelaFirstRunConsent YES` with it to keep the question open.
/// - `-VelaResetNavigation YES`: drop the persisted drive a killed process left behind, so a UI
///   scenario starts on the map with its browser chrome and no restored sheet. The scenarios that
///   test the resume itself omit this argument.
/// - `-VelaTransitFixture YES`: start the recorded San Francisco transit preview (Debug).
/// - `-VelaTransitBoardTest YES`: open the Ferry Building stop board at launch (Debug).
/// - `-VelaVoiceFixture YES`: copy the neural-voice model shipped in the test bundle (Debug).
/// - `-VelaVoiceDisableNeural YES`: force AVSpeechSynthesizer even with a model installed (Debug).
/// - `-VelaStreetViewFixture YES`: open the interactive Street View viewer on its synthetic
///   equirect fixture at launch (Debug), for the runner's no-imagery case (docs/ios/STREET-VIEW.md).
/// - `-VelaPlaceFixture YES`: open the recorded Davis place without a search or a Google request
///   (Debug). The search, photo, review-feed and Street View HTTP answers come from the
///   `PlaceFixtureURLProtocol` below and the hidden pages are replaced by a Swift fallback, so the
///   place sheet always has photos, reviews and Google's star histogram. See
///   `docs/ios/TESTING-IOS.md`.
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
    /// Drop the persisted drive and its restored sheet before the navigation stores are read.
    let resetNavigation: Bool
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
        resetNavigation = flag("VelaResetNavigation")
        if resetNavigation { Self.clearNavigationRecord() }
        if resetSettings { Self.clearWorldLayerSwitches() }
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
        #if DEBUG
        // Registered before `AppGraph` builds the HTTP sessions, so they inherit the fixture.
        PlaceFixtureLaunch.installIfRequested(arguments)
        #endif
    }

    /// The suite `NavStore` opens for the drive a process kill interrupted. Clearing it before the
    /// session starts leaves the map as the only launch surface; the restored route and its sheet
    /// are process state and come from this record alone.
    private static let navigationResumeSuite = "app.vela.ios.vela_nav_resume"

    private static func clearNavigationRecord() {
        let defaults = UserDefaults(suiteName: navigationResumeSuite)
        defaults?.removePersistentDomain(forName: navigationResumeSuite)
        defaults?.synchronize()
    }

    /// The world layer switches live in their own suite (`WorldLayerSettings.STORE`), so clearing
    /// only the settings and units suites left aviation, maritime, wiki and satellite on for the
    /// next class. A scenario launched with each switch off starts with every layer off, as the
    /// first launch of a device does. The options are read once, inside `AppGraph`, before the
    /// Kotlin stores open, so no world reader can see the old switches.
    private static let worldLayersSuite = "app.vela.ios.vela_world"

    private static func clearWorldLayerSwitches() {
        let defaults = UserDefaults(suiteName: worldLayersSuite)
        defaults?.removePersistentDomain(forName: worldLayersSuite)
        defaults?.synchronize()
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

#if DEBUG
/// The deterministic place fixture behind `-VelaPlaceFixture YES` (docs/ios/TESTING-IOS.md).
///
/// The place is the recorded Davis listing that `PlaceBranches.fixture()` already keeps for the
/// branch scenario. Everything the sheet asks Google for is answered here instead:
///
/// - `PlaceFixtureURLProtocol` serves the `hspqX` photo page, an empty `qv9Egd` feed and empty
///   search/Street View replies, plus the fixture avatar and photo pixels.
/// - `PlaceFixtureWebFallback` replaces the hidden Google page for the reviews, so the panel gets
///   the same reviews and the same `[5-star ... 1-star]` histogram on every run.
///
/// Nothing here is compiled into Release. The fixture is inert without the launch argument.
enum PlaceFixtureLaunch {
    static func installIfRequested(_ arguments: [String]) {
        guard let index = arguments.firstIndex(of: "-VelaPlaceFixture"),
              index + 1 < arguments.count,
              ["yes", "true", "1"].contains(arguments[index + 1].lowercased()) else { return }
        PlaceFixtureURLProtocol.enabled = true
        _ = URLProtocol.registerClass(PlaceFixtureURLProtocol.self)
        // `LaunchOptions.current` is built inside `AppGraph.session`; opening the place from a later
        // main-loop turn keeps the session initializer out of itself.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            open(remaining: 40)
        }
    }

    /// A custom URLSession does not reliably pick up a protocol registered globally on iOS 26.
    /// The app's HTTP session and the image loader install the fixture in their protocolClasses,
    /// the same way the Overpass fixtures do.
    static func configure(session configuration: URLSessionConfiguration) {
        guard PlaceFixtureURLProtocol.enabled else { return }
        configuration.protocolClasses =
            [PlaceFixtureURLProtocol.self] + (configuration.protocolClasses ?? [])
    }

    /// The sheet's own `start()` gates `select`; retry briefly until the map screen has called it.
    private static func open(remaining: Int) {
        guard remaining > 0, let place = PlaceBranches.shared.fixture().first else { return }
        let store = AppGraph.session.place
        store.web = PlaceFixtureWebFallback.shared
        store.select(p: place)
        if store.state.value.selected == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                open(remaining: remaining - 1)
            }
        }
    }
}

/// The HTTP answers of the place fixture. Only requests to Google hosts are claimed, and only while
/// the launch argument is on: a normal Debug launch keeps using the real session.
final class PlaceFixtureURLProtocol: URLProtocol {
    fileprivate(set) static var enabled = false

    private static let photoCount = 8

    override class func canInit(with request: URLRequest) -> Bool {
        guard enabled, let url = request.url, url.scheme == "https", let host = url.host else {
            return false
        }
        return host == "www.google.com"
            || host.hasSuffix(".googleusercontent.com")
            || host == "maps.googleapis.com"
            || host.hasSuffix(".googleapis.com")
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let text = url.absoluteString
        if let host = url.host, host.hasSuffix(".googleusercontent.com") {
            reply(Self.png(Self.imageIndex(url)), type: "image/png", url: url)
        } else if text.contains("rpcids=hspqX") {
            reply(Self.photoPage(), type: "application/json", url: url)
        } else if text.contains("rpcids=qv9Egd") {
            reply(Self.emptyFeed(), type: "application/json", url: url)
        } else {
            // The search endpoint, Street View metadata and the session warm-up: an empty 200 makes
            // every parse return nothing, without a live Google request and without a long timeout.
            reply(Data(), type: "text/plain", url: url)
        }
    }

    override func stopLoading() {}

    private func reply(_ body: Data, type: String, url: URL) {
        let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": type])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    /// The `batchexecute` `hspqX` envelope with eight Google-user-content photos and their dates.
    /// `PhotosParser` keeps only `googleusercontent` URLs, so the fixture uses that host and the
    /// protocol above serves their pixels.
    private static func photoPage() -> Data {
        var entries: [[Any]] = []
        for index in 0..<photoCount {
            var entry = [Any](repeating: NSNull(), count: 22)
            entry[6] = ["https://lh5.googleusercontent.com/fixture/place-\(index + 1)=w600-h450"]
            // The date lives at [21][6][8] = [year, month, day, hour].
            var posted = [Any](repeating: NSNull(), count: 9)
            posted[8] = [2026, (index % 4) + 5, 1, 12]
            var date = [Any](repeating: NSNull(), count: 7)
            date[6] = posted
            entry[21] = date
            entries.append(entry)
        }
        let payload: [Any] = [entries, NSNull(), NSNull(), NSNull(), NSNull(), NSNull()]
        let row: [Any] = ["wrb.fr", "hspqX", json(payload), NSNull(), NSNull(), NSNull(), "generic"]
        return Data((")]}'\n\n" + json([row]) + "\n").utf8)
    }

    /// The feed's own empty answer: `end` is true and the list is absent, so `PlaceStore` asks the
    /// fixture page for the reviews instead of Google.
    private static func emptyFeed() -> Data {
        let payload = "[null,null,null,null,null,true]"
        let row: [Any] = ["wrb.fr", "qv9Egd", payload, NSNull(), NSNull(), NSNull(), "generic"]
        return Data((")]}'\n\n" + json([row]) + "\n").utf8)
    }

    private static func json(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    private static func imageIndex(_ url: URL) -> Int {
        let digits = url.lastPathComponent.split(whereSeparator: { !$0.isNumber }).first ?? ""
        return (Int(digits) ?? 1) - 1
    }

    /// A 32 pt solid PNG. The avatars must decode to a non-black pixel (PlaceUITests samples them),
    /// and the gallery photos must be real images rather than a gray placeholder.
    private static func png(_ index: Int) -> Data {
        let size = 32
        let palette: [(UInt8, UInt8, UInt8)] = [
            (0x2E, 0x7D, 0x32), (0xC6, 0x28, 0x28), (0x15, 0x65, 0xC0),
            (0xEF, 0x6C, 0x00), (0x6A, 0x1B, 0x9A), (0x00, 0x83, 0x8F),
        ]
        let color = palette[abs(index) % palette.count]
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            pixels[offset] = color.0
            pixels[offset + 1] = color.1
            pixels[offset + 2] = color.2
            pixels[offset + 3] = 255
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(
                width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false,
                intent: .defaultIntent),
              let data = UIImage(cgImage: image).pngData() else { return Data() }
        return data
    }
}

/// The reviews page, without a hidden WebView. The first scrape answers twelve reviews, the next
/// one eighteen, so "More reviews" still proves that a page merge adds rows. Every answer carries
/// Google's star histogram, which the fixture feed itself cannot provide.
final class PlaceFixtureWebFallback: NSObject, PlaceWebFallback {
    static let shared = PlaceFixtureWebFallback()

    private static let histogram = "[120,42,18,6,3]"
    private var scrapes = 0

    func reviews(request: WebReviewsRequest, sink: WebReviewsSink) -> any Cancellable {
        scrapes += 1
        let count = scrapes == 1 ? 12 : 18
        let handle = WebFetchHandle()
        DispatchQueue.main.async {
            guard !handle.cancelled else {
                sink.onResult(payload: nil)
                return
            }
            let payload = Self.reviewsJSON(count: count)
            sink.onHistogram(json: Self.histogram)
            sink.onProgress(count: Int32(count))
            sink.onPartial(payload: payload)
            sink.onResult(payload: payload)
        }
        return handle
    }

    /// The category walk is not run on CI (W-2); an empty answer leaves the RPC photos in place.
    func photos(request: WebPhotosRequest, sink: WebPhotosSink) -> any Cancellable {
        let handle = WebFetchHandle()
        DispatchQueue.main.async {
            guard !handle.cancelled else { return }
            sink.onResult(payload: nil)
        }
        return handle
    }

    /// The place is complete from the branch fixture, so the details page has nothing to add.
    func details(request: WebDetailsRequest, sink: WebDetailsSink) -> any Cancellable {
        let handle = WebFetchHandle()
        DispatchQueue.main.async {
            guard !handle.cancelled else { return }
            sink.onResult(payload: nil)
        }
        return handle
    }

    /// The JSON the reviews scraper's bridge sends: `a` author, `r` stars, `d` age, `t` text,
    /// `av` avatar URL, `p` review photos.
    private static func reviewsJSON(count: Int) -> String {
        let ratings = [5, 5, 4, 4, 3]
        let items: [[String: Any]] = (0..<count).map { index in
            [
                "a": "Fixture Reviewer \(index + 1)",
                "r": ratings[index % ratings.count],
                "d": "\(index + 1) weeks ago",
                "t": "Deterministic review \(index + 1) for the place fixture.",
                "av": "https://lh5.googleusercontent.com/fixture/avatar-\(index + 1)=s128",
                "p": [],
            ]
        }
        let data = (try? JSONSerialization.data(withJSONObject: items)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}
#endif
