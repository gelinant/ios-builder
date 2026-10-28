import CoreLocation
import Foundation
import VelaCore

/// One route of the chooser, copied out of the Kotlin `RouteRow`. Swift holds indices, never a
/// Kotlin `Route` (docs/ios/PRESENTATION-MAP.md 5, trap 2).
struct RouteChoice: Identifiable, Equatable {
    let id: Int
    let seconds: Double
    let meters: Double
    let via: String?
    let delaySeconds: Double
    let hasTraffic: Bool
    let typicalLowSeconds: Double?
    let typicalHighSeconds: Double?
    /// Plate cameras this route passes; nil until the camera pass has counted them.
    let cameras: Int?
}

struct RouteWaypoint: Identifiable, Equatable {
    let id: Int
    let name: String
    let address: String?
    let latitude: Double
    let longitude: Double
}

enum RouteTimeMode: Int, CaseIterable, Identifiable {
    case now = 0
    case depart = 1
    case arrive = 2

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .now: return VelaL10n.text("place_leave_now")
        case .depart: return VelaL10n.text("place_depart_at")
        case .arrive: return VelaL10n.text("place_arrive_by")
        }
    }
}

/// One step of the selected route, copied out of the Kotlin `StepRow`.
struct RouteStep: Identifiable, Equatable {
    struct Lane: Equatable {
        let arrows: [String]
        let valid: Bool
    }

    let id: Int
    let kind: String
    let instruction: String
    let meters: Double
    let ref: String?
    let laneHint: String?
    let lanes: [Lane]
    let exit: Int
}

/// One transit itinerary, copied out of the Kotlin `TransitRow`.
struct TransitChoice: Identifiable, Equatable {
    struct Leg: Equatable {
        let kind: String
        let line: String?
        let color: String?
        let textColor: String?
        let durationText: String?
        let departText: String?
        let arriveText: String?
        let from: String?
        let to: String?
        let headsign: String?
        let stops: Int
        let delayText: String?
    }

    let id: Int
    let departText: String?
    let arriveText: String?
    let durationText: String?
    let seconds: Double
    let legs: [Leg]
}

/// A route's line as the map draws it, and its traffic stretches.
struct RouteLine: Equatable {
    struct Traffic: Equatable {
        let level: Int
        let coordinates: [CLLocationCoordinate2D]

        static func == (a: Traffic, b: Traffic) -> Bool {
            a.level == b.level && a.coordinates.count == b.coordinates.count
        }
    }

    let index: Int
    let coordinates: [CLLocationCoordinate2D]
    let traffic: [Traffic]
    let stops: [CLLocationCoordinate2D]

    init(index: Int, coordinates: [CLLocationCoordinate2D], traffic: [Traffic], stops: [CLLocationCoordinate2D] = []) {
        self.index = index
        self.coordinates = coordinates
        self.traffic = traffic
        self.stops = stops
    }

    static func == (a: RouteLine, b: RouteLine) -> Bool {
        a.index == b.index && a.coordinates.count == b.coordinates.count
            && a.coordinates.first?.latitude == b.coordinates.first?.latitude
            && a.coordinates.last?.latitude == b.coordinates.last?.latitude
            && a.coordinates.last?.longitude == b.coordinates.last?.longitude
            && a.traffic.count == b.traffic.count && a.stops.count == b.stops.count
    }
}

/// The travel modes of the chips, by their Kotlin `TravelMode` names.
enum RouteMode: String, CaseIterable, Identifiable {
    case drive = "DRIVE"
    case walk = "WALK"
    case bicycle = "BICYCLE"
    case transit = "TRANSIT"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .drive: return "car.fill"
        case .walk: return "figure.walk"
        case .bicycle: return "bicycle"
        case .transit: return "tram.fill"
        }
    }

    var label: String {
        switch self {
        case .drive: return VelaL10n.text("place_mode_drive")
        case .walk: return VelaL10n.text("place_mode_walk")
        case .bicycle: return VelaL10n.text("place_mode_bike")
        case .transit: return VelaL10n.text("place_mode_transit")
        }
    }
}

/// SwiftUI's side of the Kotlin `RouteStore`: forwards the intents and mirrors the state, read
/// through SKIE. Main thread only.
final class RouteModel: ObservableObject {
    @Published private(set) var isOpen = false
    @Published private(set) var loading = false
    @Published private(set) var mode: RouteMode = .drive
    @Published private(set) var choices: [RouteChoice] = []
    @Published private(set) var activeIndex = -1
    @Published private(set) var steps: [RouteStep] = []
    @Published private(set) var transit: [TransitChoice] = []
    @Published private(set) var lines: [RouteLine] = []
    @Published private(set) var modeSeconds: [RouteMode: Double] = [:]
    @Published private(set) var message: String?
    @Published private(set) var destinationName = ""
    @Published private(set) var originName: String?
    @Published private(set) var fromMapCenter = false
    @Published private(set) var reversed = false
    @Published private(set) var waypoints: [RouteWaypoint] = []
    @Published private(set) var canAddWaypoint = true
    @Published private(set) var timeMode: RouteTimeMode = .now
    @Published private(set) var timeEpochSec: Int64 = 0
    @Published private(set) var avoidTolls = false
    @Published private(set) var avoidHighways = false
    @Published private(set) var avoidFerries = false
    @Published private(set) var avoidSupported = false
    @Published private(set) var bikeSafe = true
    @Published private(set) var googleOff = false
    @Published private(set) var trafficOnTap = false
    @Published private(set) var trafficRequested = false
    @Published private(set) var avoidCameras = false
    @Published private(set) var cameraSideStreets = false
    @Published private(set) var canAvoidCameras = false
    @Published private(set) var camerasAvoided = 0
    @Published private(set) var cameraDetourSeconds: Double = 0
    @Published private(set) var cameraDetourMeters: Double = 0
    @Published private(set) var cameraBaselineIsFastest = false
    @Published private(set) var showsSteps = false

    private let session: MapSession?
    private var observing: Task<Void, Never>?
    private var routeIds: [ObjectIdentifier] = []

    init(session: MapSession?) {
        self.session = session
    }

    var hasRoute: Bool { activeIndex >= 0 }

    /// The selected transit itinerary, nil outside transit.
    var activeTransit: TransitChoice? {
        mode == .transit && activeIndex >= 0 && activeIndex < transit.count ? transit[activeIndex] : nil
    }

    var activeChoice: RouteChoice? {
        activeIndex >= 0 && activeIndex < choices.count ? choices[activeIndex] : nil
    }

    var timeDate: Date {
        timeEpochSec > 0 ? Date(timeIntervalSince1970: TimeInterval(timeEpochSec)) : RouteFormat.nextFiveMinutes()
    }

    func start() {
        #if DEBUG
        RouteCameraTestSupport.enableIfRequested()
        RouteBikeTestSupport.enableIfRequested()
        #endif
        guard let store = session?.route, observing == nil else { return }
        observing = Task { @MainActor [weak self] in
            for await state in store.state {
                self?.apply(state)
            }
        }
    }

    func openFromPlace() { session?.openDirections() }

    /// Opens the chooser for an incoming directions link. The origin is set only when the link
    /// named a point (a name-only origin is resolved by MapScreen before this call), and the stops
    /// arrive already resolved in the link's own order.
    func openIncomingDirections(name: String, latitude: Double, longitude: Double,
                                originName: String? = nil,
                                originLatitude: Double? = nil, originLongitude: Double? = nil,
                                mode: String? = nil, stops: [VelaIncomingPoint] = []) {
        guard stops.allSatisfy({ $0.latitude != nil && $0.longitude != nil }) else { return }
        session?.route.directionsFromPointWithStops(
            name: name, lat: latitude, lng: longitude,
            originName: originName ?? "", originLat: originLatitude ?? 0,
            originLng: originLongitude ?? 0, hasOrigin: originLatitude != nil && originLongitude != nil,
            modeName: mode,
            stops: stops.map {
                LinkStop(name: $0.name ?? "", lat: $0.latitude ?? 0, lng: $0.longitude ?? 0)
            })
    }

    func close() { session?.route.close() }
    func select(_ index: Int) { session?.route.select(index: Int32(index)) }
    func setMode(_ m: RouteMode) { session?.route.setModeNamed(name: m.rawValue) }
    func swap() { session?.route.swap() }
    func retry() { session?.route.retry() }
    func setShowsSteps(_ on: Bool) { session?.route.showSteps(on: on) }
    func setAvoidTolls(_ on: Bool) { session?.route.setAvoidTolls(on: on) }
    func setAvoidHighways(_ on: Bool) { session?.route.setAvoidHighways(on: on) }
    func setAvoidFerries(_ on: Bool) { session?.route.setAvoidFerries(on: on) }
    func setBikeSafe(_ on: Bool) { session?.route.setBikeSafe(on: on) }
    func requestTraffic() { session?.route.requestTraffic() }
    func setTrafficOnTap(_ on: Bool) { session?.route.setTrafficOnTap(on: on) }
    func setAvoidCameras(_ on: Bool) { session?.route.setAvoidCameras(on: on) }
    func setCameraSideStreets(_ on: Bool) { session?.route.setCameraSideStreets(on: on) }

    /// Called by the picker's Start: navigation keeps its own live traffic re-checks.
    func prepareNavigation() { session?.route.prepareNavigation() }

    func useCurrentLocationAsOrigin() { session?.route.setStart(p: nil) }
    func useMapCenterAsOrigin() { session?.route.setStartToMapCenter() }
    func useSearchedOrigin(_ place: Place) { session?.route.setStart(p: place) }

    func useSavedOrigin(_ place: SavedMapMarker) {
        session?.route.setStartPlace(
            id: place.id, name: place.name, address: nil, lat: place.latitude, lng: place.longitude)
    }

    func addSearchedWaypoint(_ place: Place) { session?.route.addWaypoint(p: place) }
    func addMapCenterWaypoint() { session?.route.addWaypointAtMapCenter() }

    func addSavedWaypoint(_ place: SavedMapMarker) {
        session?.route.addWaypointPlace(
            id: place.id, name: place.name, address: nil, lat: place.latitude, lng: place.longitude)
    }

    func moveWaypoint(from: Int, to: Int) {
        session?.route.moveWaypoint(from: Int32(from), to: Int32(to))
    }

    func removeWaypoint(_ index: Int) { session?.route.removeWaypoint(index: Int32(index)) }

    func setTime(_ mode: RouteTimeMode, date: Date?) {
        let epoch = mode == .now ? 0 : Int64((date ?? RouteFormat.nextFiveMinutes()).timeIntervalSince1970.rounded(.down))
        session?.route.setTime(mode: Int32(mode.rawValue), epochSec: epoch)
    }

    func findPlaces(_ query: String) async throws -> [Place] {
        guard let store = session?.route else { return [] }
        return try await store.findPlaces(query: query)
    }

    func locationChanged(latitude: Double, longitude: Double) {
        session?.route.onLocation(lat: latitude, lng: longitude)
    }

    func mapCenterChanged(latitude: Double, longitude: Double) {
        session?.route.onMapCenter(lat: latitude, lng: longitude)
    }

    /// Debug builds: the state as `key=value` words for the UI tests. `netGoogle` and `netOpen`
    /// count the HTTP requests since the chooser opened, so a NoGoogle scenario can prove that
    /// routing reached no Google host while it did reach the open ones.
    var debugLine: String {
        let active = activeIndex >= 0 && activeIndex < choices.count ? choices[activeIndex] : nil
        #if DEBUG
        let net = DebugRequestCounter.shared.sinceRouteOpen
        let netLine = " netGoogle=\(net.google) netOpen=\(net.open)"
        #else
        let netLine = ""
        #endif
        return "routes=\(choices.count) active=\(activeIndex) mode=\(mode.rawValue) loading=\(loading ? 1 : 0)"
            + " seconds=\(Int(active?.seconds ?? 0)) meters=\(Int(active?.meters ?? 0)) steps=\(steps.count)"
            + " traffic=\(lines.first(where: { $0.index == activeIndex })?.traffic.count ?? 0)"
            + " transit=\(transit.count) legs=\(activeTransit?.legs.count ?? 0)"
            + " center=\(fromMapCenter ? 1 : 0) error=\(message == nil ? 0 : 1)"
            + " stops=\(waypoints.count) timeMode=\(timeMode.rawValue) timeEpoch=\(timeEpochSec)"
            + " reversed=\(reversed ? 1 : 0) customOrigin=\(originName == nil ? 0 : 1)"
            + " bikeSafe=\(bikeSafe ? 1 : 0) googleOff=\(googleOff ? 1 : 0)"
            + " trafficOnTap=\(trafficOnTap ? 1 : 0) trafficRequested=\(trafficRequested ? 1 : 0)"
            + " trafficLive=\(active?.hasTraffic == true ? 1 : 0)"
            + " cameraAvoid=\(avoidCameras ? 1 : 0) cameraCan=\(canAvoidCameras ? 1 : 0)"
            + " cameras=\(active?.cameras ?? -1) cameraAvoided=\(camerasAvoided)"
            + " cameraExtraS=\(Int(cameraDetourSeconds)) cameraExtraM=\(Int(cameraDetourMeters))"
            + " cameraSide=\(cameraSideStreets ? 1 : 0)" + netLine
    }

    private func apply(_ state: RouteState) {
        if state.open && !isOpen {
            #if DEBUG
            DebugRequestCounter.shared.markRouteOpen()
            #endif
        }
        isOpen = state.open
        loading = state.loading
        mode = RouteMode(rawValue: state.modeName) ?? .drive
        reversed = state.reversed
        fromMapCenter = state.fromMapCenter
        waypoints = state.waypoints.enumerated().map { index, place in
            RouteWaypoint(id: index, name: place.name, address: place.address,
                          latitude: place.location.lat, longitude: place.location.lng)
        }
        canAddWaypoint = state.canAddWaypoint
        timeMode = RouteTimeMode(rawValue: Int(state.timeMode)) ?? .now
        timeEpochSec = state.timeEpoch
        avoidTolls = state.avoidTolls
        avoidHighways = state.avoidHighways
        avoidFerries = state.avoidFerries
        avoidSupported = state.avoidSupported
        bikeSafe = state.bikeSafe
        googleOff = state.googleOff
        trafficOnTap = state.trafficOnTap
        trafficRequested = state.trafficRequested
        avoidCameras = state.avoidCameras
        cameraSideStreets = state.cameraSideStreets
        canAvoidCameras = state.canAvoidCameras
        camerasAvoided = Int(state.camerasAvoided)
        cameraDetourSeconds = state.cameraDetourSeconds
        cameraDetourMeters = state.cameraDetourMeters
        cameraBaselineIsFastest = state.cameraBaselineIsFastest
        showsSteps = state.showSteps
        destinationName = state.destination?.name ?? ""
        originName = state.origin?.name
        choices = state.rows().enumerated().map { i, r in
            RouteChoice(id: i, seconds: r.seconds, meters: r.meters, via: r.via,
                        delaySeconds: r.delaySeconds, hasTraffic: r.hasTraffic,
                        typicalLowSeconds: r.typicalLowSeconds?.doubleValue,
                        typicalHighSeconds: r.typicalHighSeconds?.doubleValue,
                        cameras: r.cameras?.intValue)
        }
        activeIndex = Int(state.activeIndex)
        steps = state.steps().enumerated().map { i, s in
            RouteStep(id: i, kind: s.kind, instruction: s.instruction, meters: s.meters, ref: s.ref,
                      laneHint: s.laneHint,
                      lanes: s.lanes.map { RouteStep.Lane(arrows: $0.indications.split(separator: ",").map(String.init), valid: $0.valid) },
                      exit: Int(s.exit))
        }
        transit = state.transitRows().enumerated().map { i, t in
            TransitChoice(
                id: i, departText: t.departText, arriveText: t.arriveText, durationText: t.durationText,
                seconds: t.seconds,
                legs: t.legs.map { l in
                    TransitChoice.Leg(kind: l.kind, line: l.line, color: l.color, textColor: l.textColor,
                                      durationText: l.durationText, departText: l.departText, arriveText: l.arriveText,
                                      from: l.from, to: l.to, headsign: l.headsign, stops: Int(l.stops),
                                      delayText: l.delayText)
                })
        }
        var seconds: [RouteMode: Double] = [:]
        for m in RouteMode.allCases {
            let s = state.secondsOf(modeName: m.rawValue)
            if s >= 0 { seconds[m] = s }
        }
        modeSeconds = seconds
        message = errorText(for: state.error)
        let ids = state.routes.map { ObjectIdentifier($0) } + state.transit.map { ObjectIdentifier($0) }
        if ids != routeIds {
            routeIds = ids
            lines = buildLines(count: ids.count)
        }
    }

    private func buildLines(count: Int) -> [RouteLine] {
        guard let store = session?.route else { return [] }
        let stops = Self.coordinates(store.waypointPoints())
        return (0..<count).map { i in
            let traffic = store.trafficLines(index: Int32(i)).map { t in
                RouteLine.Traffic(level: Int(t.level), coordinates: Self.coordinates(t.points))
            }
            return RouteLine(
                index: i, coordinates: Self.coordinates(store.line(index: Int32(i))), traffic: traffic, stops: stops)
        }
    }

    private static func coordinates(_ flat: KotlinDoubleArray) -> [CLLocationCoordinate2D] {
        let n = Int(flat.size) / 2
        var out: [CLLocationCoordinate2D] = []
        out.reserveCapacity(n)
        for j in 0..<n {
            out.append(CLLocationCoordinate2D(latitude: flat.get(index: Int32(2 * j)),
                                              longitude: flat.get(index: Int32(2 * j + 1))))
        }
        return out
    }

    private func errorText(for error: (any RouteError)?) -> String? {
        guard let error else { return nil }
        if error is RouteErrorNoOrigin {
            return "Your location is not known yet"
        }
        if error is RouteErrorNoRoute {
            return googleOff
                ? "No \(mode.label.lowercased()) route found. Google is off, so only open services were asked."
                : "No \(mode.label.lowercased()) route found"
        }
        if error is RouteErrorModeUnavailable {
            return googleOff
                ? "\(mode.label) needs an open service that is not available in this build, and Google is off."
                : "\(mode.label) directions are not available in this build"
        }
        if error is RouteErrorNeedsRecalibration {
            return "Directions need an update: Google changed its answers"
        }
        if let failed = error as? RouteErrorFailed, let reason = failed.reason {
            return "Routing failed: \(reason)"
        }
        return "Routing failed"
    }
}

/// Times and lengths in the device's language and units.
enum RouteFormat {
    static func duration(_ seconds: Double) -> String {
        let f = DateComponentsFormatter()
        f.unitsStyle = .short
        f.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute]
        let rounded = max(60, (seconds / 60).rounded() * 60)
        return f.string(from: rounded) ?? "\(Int(rounded / 60)) min"
    }

    static func distance(_ meters: Double) -> String {
        let f = MeasurementFormatter()
        f.unitOptions = .providedUnit
        f.unitStyle = .medium
        let n = NumberFormatter()
        let imperial = AppGraph.session.settings?.imperial ?? (Locale.current.measurementSystem == .us)
        let metric = !imperial
        if metric {
            if meters < 1000 {
                n.maximumFractionDigits = 0
                f.numberFormatter = n
                return f.string(from: Measurement(value: (meters / 10).rounded() * 10, unit: UnitLength.meters))
            }
            n.maximumFractionDigits = meters < 10_000 ? 1 : 0
            f.numberFormatter = n
            return f.string(from: Measurement(value: meters / 1000, unit: UnitLength.kilometers))
        }
        let miles = meters / 1609.344
        if miles < 0.1 {
            n.maximumFractionDigits = 0
            f.numberFormatter = n
            return f.string(from: Measurement(value: (meters * 3.28084 / 10).rounded() * 10, unit: UnitLength.feet))
        }
        n.maximumFractionDigits = miles < 10 ? 1 : 0
        f.numberFormatter = n
        return f.string(from: Measurement(value: miles, unit: UnitLength.miles))
    }

    static func nextFiveMinutes(now: Date = Date()) -> Date {
        Date(timeIntervalSince1970: (now.timeIntervalSince1970 / 300).rounded(.up) * 300)
    }

    static func moment(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = Calendar.current.isDateInToday(date) ? .none : .short
        return f.string(from: date)
    }

    /// The keyless driving source has no per-departure forecast. A future pick uses only the
    /// selected route's typical range; Leave now alone may use its live traffic duration.
    static func driveTimeSummary(mode: RouteTimeMode, date: Date, choice: RouteChoice?) -> (String, String)? {
        guard let choice else { return nil }
        if mode == .now {
            let arrival = moment(Date().addingTimeInterval(choice.seconds))
            return ("Arrive at \(arrival)", choice.hasTraffic ? "Based on current live traffic" : "Estimated arrival, no live traffic")
        }
        let low = choice.typicalLowSeconds ?? choice.seconds
        let high = choice.typicalHighSeconds ?? choice.seconds
        let typical = choice.typicalLowSeconds != nil && choice.typicalHighSeconds != nil
        let note = typical ? "Typical traffic range, not a live departure forecast" : "Estimate only, no live departure forecast"
        func window(_ first: Double, _ second: Double) -> String {
            let a = moment(date.addingTimeInterval(first))
            let b = moment(date.addingTimeInterval(second))
            return abs(first - second) < 1 ? a : "\(a) to \(b)"
        }
        switch mode {
        case .now:
            return nil
        case .depart:
            return ("Depart \(moment(date)) · arrive \(window(low, high))", note)
        case .arrive:
            return ("Arrive by \(moment(date)) · leave \(window(-high, -low))", note)
        }
    }
}
