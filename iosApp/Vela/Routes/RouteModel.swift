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
}

/// One step of the selected route, copied out of the Kotlin `StepRow`.
struct RouteStep: Identifiable, Equatable {
    let id: Int
    let kind: String
    let instruction: String
    let meters: Double
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

    static func == (a: RouteLine, b: RouteLine) -> Bool {
        a.index == b.index && a.coordinates.count == b.coordinates.count
            && a.coordinates.first?.latitude == b.coordinates.first?.latitude
            && a.coordinates.last?.longitude == b.coordinates.last?.longitude
            && a.traffic.count == b.traffic.count
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
        case .drive: return "Drive"
        case .walk: return "Walk"
        case .bicycle: return "Bike"
        case .transit: return "Transit"
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
    @Published private(set) var lines: [RouteLine] = []
    @Published private(set) var modeSeconds: [RouteMode: Double] = [:]
    @Published private(set) var message: String?
    @Published private(set) var destinationName = ""
    @Published private(set) var originName: String?
    @Published private(set) var fromMapCenter = false
    @Published private(set) var reversed = false
    @Published private(set) var avoidTolls = false
    @Published private(set) var avoidHighways = false
    @Published private(set) var avoidFerries = false
    @Published private(set) var avoidSupported = false
    @Published private(set) var showsSteps = false

    private let session: MapSession?
    private var observing: Task<Void, Never>?
    private var routeIds: [ObjectIdentifier] = []

    init(session: MapSession?) {
        self.session = session
    }

    var hasRoute: Bool { activeIndex >= 0 }

    func start() {
        guard let store = session?.route, observing == nil else { return }
        observing = Task { @MainActor [weak self] in
            for await state in store.state {
                self?.apply(state)
            }
        }
    }

    func openFromPlace() { session?.openDirections() }
    func close() { session?.route.close() }
    func select(_ index: Int) { session?.route.select(index: Int32(index)) }
    func setMode(_ m: RouteMode) { session?.route.setModeNamed(name: m.rawValue) }
    func swap() { session?.route.swap() }
    func retry() { session?.route.retry() }
    func setShowsSteps(_ on: Bool) { session?.route.showSteps(on: on) }
    func setAvoidTolls(_ on: Bool) { session?.route.setAvoidTolls(on: on) }
    func setAvoidHighways(_ on: Bool) { session?.route.setAvoidHighways(on: on) }
    func setAvoidFerries(_ on: Bool) { session?.route.setAvoidFerries(on: on) }

    func locationChanged(latitude: Double, longitude: Double) {
        session?.route.onLocation(lat: latitude, lng: longitude)
    }

    func mapCenterChanged(latitude: Double, longitude: Double) {
        session?.route.onMapCenter(lat: latitude, lng: longitude)
    }

    /// Debug builds: the state as `key=value` words for the UI tests.
    var debugLine: String {
        let active = activeIndex >= 0 && activeIndex < choices.count ? choices[activeIndex] : nil
        return "routes=\(choices.count) active=\(activeIndex) mode=\(mode.rawValue) loading=\(loading ? 1 : 0)"
            + " seconds=\(Int(active?.seconds ?? 0)) meters=\(Int(active?.meters ?? 0)) steps=\(steps.count)"
            + " traffic=\(lines.first(where: { $0.index == activeIndex })?.traffic.count ?? 0)"
            + " center=\(fromMapCenter ? 1 : 0) error=\(message == nil ? 0 : 1)"
    }

    private func apply(_ state: RouteState) {
        isOpen = state.open
        loading = state.loading
        mode = RouteMode(rawValue: state.modeName) ?? .drive
        reversed = state.reversed
        fromMapCenter = state.fromMapCenter
        avoidTolls = state.avoidTolls
        avoidHighways = state.avoidHighways
        avoidFerries = state.avoidFerries
        avoidSupported = state.avoidSupported
        showsSteps = state.showSteps
        destinationName = state.destination?.name ?? ""
        originName = state.origin?.name
        choices = state.rows().enumerated().map { i, r in
            RouteChoice(id: i, seconds: r.seconds, meters: r.meters, via: r.via,
                        delaySeconds: r.delaySeconds, hasTraffic: r.hasTraffic)
        }
        activeIndex = Int(state.activeIndex)
        steps = state.steps().enumerated().map { i, s in
            RouteStep(id: i, kind: s.kind, instruction: s.instruction, meters: s.meters)
        }
        var seconds: [RouteMode: Double] = [:]
        for m in RouteMode.allCases {
            let s = state.secondsOf(modeName: m.rawValue)
            if s >= 0 { seconds[m] = s }
        }
        modeSeconds = seconds
        message = errorText(for: state.error)
        let ids = state.routes.map { ObjectIdentifier($0) }
        if ids != routeIds {
            routeIds = ids
            lines = buildLines(count: ids.count)
        }
    }

    private func buildLines(count: Int) -> [RouteLine] {
        guard let store = session?.route else { return [] }
        return (0..<count).map { i in
            let traffic = store.trafficLines(index: Int32(i)).map { t in
                RouteLine.Traffic(level: Int(t.level), coordinates: Self.coordinates(t.points))
            }
            return RouteLine(index: i, coordinates: Self.coordinates(store.line(index: Int32(i))), traffic: traffic)
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
            return "No \(mode.label.lowercased()) route found"
        }
        if error is RouteErrorModeUnavailable {
            return "Transit directions are not on iOS yet"
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
        let metric = Locale.current.measurementSystem != .us
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
}
