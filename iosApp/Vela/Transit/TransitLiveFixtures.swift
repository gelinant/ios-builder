#if DEBUG
import Foundation
import VelaCore

/// The recorded values behind `-VelaTransitAdvancedFixture`. They are extracts of two captures
/// taken from `api.transitous.org` on 2026-10-28 with the app User-Agent:
///
/// - reachability: `GET /api/v1/one-to-all?one=37.7955,-122.3937&maxTravelTime=10` (San Francisco,
///   around the Ferry Building the trip fixture uses);
/// - lines: `GET /api/v1/map/trips?min=52.520,13.405&max=52.524,13.412&zoom=16&...&precision=5`
///   (Berlin, 12:00-12:05 UTC), plus the `ICE 376` stretch of the 11:35-11:44 capture for the red
///   delay band.
///
/// The full replies are committed as `TransitFixtures` in `core-common`; these are the handful of
/// rows the screenshot needs. No value is invented: each color, realtime flag and delay comes from
/// the captured stretch. The five local lines keep a real path so the preview can draw them; the
/// long-distance rows keep their real delay and no path.
enum TransitLiveFixtures {
    static let reachOriginName = "Ferry Building"
    static let reachLat = 37.7955
    static let reachLng = -122.3937

    static let reachStops: [TransitReachStop] = [
        TransitReachStop(name: "San Francisco", stopId: "us-Amtrak_SFC", lat: 37.788650, lng: -122.398865, minutes: 9, transfers: 1),
        TransitReachStop(name: "North Point St & Kearny St", stopId: "us-ca-SF-bayarea_15462", lat: 37.807350, lng: -122.407900, minutes: 10, transfers: 1),
        TransitReachStop(name: "The Embarcadero & Green St", stopId: "us-ca-SF-bayarea_14518", lat: 37.800600, lng: -122.398920, minutes: 7, transfers: 1),
        TransitReachStop(name: "San Francisco Ferry Terminal", stopId: "us-ca-SF-bayarea_72012", lat: 37.794390, lng: -122.390930, minutes: 6, transfers: 0),
        TransitReachStop(name: "Market St & Grant Ave", stopId: "us-ca-SF-bayarea_15674", lat: 37.786390, lng: -122.405160, minutes: 10, transfers: 1),
        TransitReachStop(name: "Sansome St & Clay St", stopId: "us-ca-SFMTA_16328", lat: 37.794470, lng: -122.401490, minutes: 10, transfers: 1),
        TransitReachStop(name: "Union St & Montgomery St", stopId: "us-ca-SF-bayarea_16776", lat: 37.800960, lng: -122.404510, minutes: 10, transfers: 1),
        TransitReachStop(name: "Market St & Drumm St", stopId: "us-ca-SF-bayarea_15669", lat: 37.793470, lng: -122.396180, minutes: 5, transfers: 0),
        TransitReachStop(name: "Main St & Folsom St", stopId: "us-ca-SF-bayarea_17992", lat: 37.789810, lng: -122.392290, minutes: 10, transfers: 1),
        TransitReachStop(name: "Embarcadero & Sansome St", stopId: "us-ca-SF-bayarea_17281", lat: 37.805150, lng: -122.403230, minutes: 9, transfers: 1),
        TransitReachStop(name: "Kearny St & Bush St", stopId: "us-ca-SF-bayarea_14818", lat: 37.791000, lng: -122.403980, minutes: 10, transfers: 1),
        TransitReachStop(name: "The Embarcadero & Washington St", stopId: "us-ca-SF-bayarea_14532", lat: 37.797090, lng: -122.395670, minutes: 5, transfers: 0),
        TransitReachStop(name: "Mission St & 3rd St", stopId: "us-ca-SF-bayarea_15531", lat: 37.786510, lng: -122.401570, minutes: 10, transfers: 1),
        TransitReachStop(name: "Transit Center Bay B", stopId: "us-ca-SFMTA_17914", lat: 37.790092, lng: -122.395690, minutes: 9, transfers: 1),
    ]

    private static func path(_ coordinates: [(Double, Double)]) -> [[LatLng]] {
        [coordinates.map { LatLng(lat: $0.0, lng: $0.1) }]
    }

    private static func line(
        _ label: String, _ mode: String, _ color: String, _ feed: String?, _ destination: String,
        _ segments: Int, _ delay: Int?, _ live: Bool, _ paths: [[LatLng]]
    ) -> TransitLiveLine {
        TransitLiveLines.shared.mappedLine(
            label: label, mode: mode, colorHex: color, feedColorHex: feed,
            destination: destination, segmentCount: Int32(segments),
            delayMinutes: Int32(delay ?? 0), hasDelay: delay != nil, live: live, paths: paths)
    }

    static let lines: [TransitLiveLine] = [
        line("S9", "TRAIN", "#992746", "#992746", "S+U Alexanderplatz Bhf (Berlin)", 4, 0, true,
             path([
                (52.514250, 13.419530), (52.514730, 13.418270), (52.515400, 13.417380),
                (52.515760, 13.417140), (52.516230, 13.416870),
             ])),
        line("S7", "TRAIN", "#816da6", "#816da6", "S+U Alexanderplatz Bhf (Berlin)", 2, 0, true,
             path([
                (52.522660, 13.402460), (52.522790, 13.403060), (52.522920, 13.403530),
                (52.523140, 13.404300),
             ])),
        line("S3", "TRAIN", "#0066ad", "#0066ad", "S+U Jannowitzbrücke (Berlin)", 2, nil, false,
             path([
                (52.521520, 13.411230), (52.521050, 13.412150), (52.520510, 13.412880),
                (52.520260, 13.413270),
             ])),
        line("U2", "SUBWAY", "#da421e", "#da421e", "U Rosa-Luxemburg-Platz (Berlin)", 6, nil, false,
             path([
                (52.521760, 13.414250), (52.522050, 13.413760), (52.522970, 13.411780),
                (52.523910, 13.410170),
             ])),
        // No routeColor in the capture: the mode color, and the row says so.
        line("M4", "TRAM", "#437c93", nil, "S+U Alexanderplatz Bhf/Gontardstr. (Berlin)", 9, nil, false,
             path([
                (52.520520, 13.404130), (52.520220, 13.404520), (52.520160, 13.404650),
                (52.520130, 13.404770),
             ])),
        // Long-distance rows: the captured delay is shown, no path is drawn.
        line("FlixBus 070", "BUS", "#73d700", "#73d700", "Hamburg central bus station", 1, 3, true, []),
        line("IC 2270", "TRAIN", "#1a57c2", nil, "Schwerin Hauptbahnhof", 1, 4, true, []),
        line("ICE 376", "TRAIN", "#1a57c2", nil, "S+U Berlin Hauptbahnhof", 1, 15, true, []),
    ]

    static func reachArea(minutes: Int) -> TransitReachArea {
        TransitReach.shared.areaOf(
            originName: reachOriginName,
            originLat: reachLat,
            originLng: reachLng,
            maxMinutes: Int32(minutes),
            stops: reachStops,
            nowMillis: Int64(Date().timeIntervalSince1970 * 1000))
    }
}
#endif
