import CoreLocation
import Foundation
import SwiftUI
import UIKit
import VelaCore

/// The stop a line is opened at. A board row or a trip leg has the Transitous id; a search result
/// or a map label may only have a name and a coordinate, and the board is then resolved by
/// proximity. No value is or guessed: [stopId] is nil when the surface has none.
struct TransitLineStopRef: Equatable {
    let stopId: String?
    let parentId: String?
    let name: String
    let latitude: Double
    let longitude: Double
    let siblingIds: [String]

    init(stopId: String?, parentId: String? = nil, name: String,
         latitude: Double, longitude: Double, siblingIds: [String] = []) {
        self.stopId = stopId
        self.parentId = parentId
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.siblingIds = siblingIds
    }
}

/// One open of the line sheet.
struct TransitLineRequest: Identifiable, Equatable {
    let id = UUID()
    let line: String
    let direction: String?
    let stop: TransitLineStopRef?
}

/// What "See the whole line on the map" publishes: the feed's shape when it sent one, else the
/// stop chain, plus the estimated vehicle point and the line's identity. The map layer owns the
/// drawing; this type only carries the request.
struct TransitLineMapRequest {
    let label: String
    let direction: String
    let colorHex: String
    let colorSource: String
    let live: Bool
    let estimated: Bool
    let shapeSource: String
    let stops: [CLLocationCoordinate2D]
    let shape: [CLLocationCoordinate2D]
    let vehicle: CLLocationCoordinate2D?
    let fraction: Double
    let stopNames: [String]
}

extension Notification.Name {
    /// The one map hook of the line sheet. A map owner listens for it and draws the request.
    static let velaTransitLineMapRequest = Notification.Name("vela.transit.line.mapRequest")
}

/// THE entry point for "tap transit anywhere". Any surface that knows a line, a direction and a
/// stop calls `TransitLineLink.shared.open(line:direction:stop:)`; the link presents the sheet and
/// owns its lifetime, so no host view has to add a `.sheet`. Main-actor bound: the call comes from
/// a tap.
@MainActor
final class TransitLineLink: ObservableObject {
    static let shared = TransitLineLink()

    @Published private(set) var request: TransitLineRequest?
    @Published private(set) var lastMapRequest: TransitLineMapRequest?

    private var host: UIViewController?
    private lazy var service = TransitLineService(
        http: TransitousHttp(
            http: URLSessionVelaHttp(),
            locale: DevicePlatformLocale(),
            text: FoundationTextNormalizer()),
        clock: SystemClock())

    private init() {}

    /// Opens the line sheet for one line in one direction at one stop. Passing [direction] nil
    /// lets the feed's board decide (its first direction for the line at that stop).
    func open(line: String, direction: String? = nil, stop: TransitLineStopRef?) {
        guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let request = TransitLineRequest(line: line, direction: direction, stop: stop)
        self.request = request
        let model = TransitLineModel(request: request, service: service)
        let sheet = TransitLineSheet(model: model) { [weak self] in
            self?.close()
        }
        let controller = UIHostingController(rootView: sheet)
        controller.modalPresentationStyle = .pageSheet
        controller.view.accessibilityIdentifier = "transit-line-host"
        if let presentation = controller.sheetPresentationController {
            presentation.detents = [.large()]
            presentation.prefersGrabberVisible = true
        }
        host = controller
        topViewController()?.present(controller, animated: !LaunchOptions.current.deterministic)
    }

    func close() {
        let controller = host
        host = nil
        request = nil
        controller?.dismiss(animated: !LaunchOptions.current.deterministic)
    }

    /// Publishes the whole line for the map layer. No map file is touched by this lot.
    func publish(_ request: TransitLineMapRequest) {
        lastMapRequest = request
        NotificationCenter.default.post(name: .velaTransitLineMapRequest, object: request)
    }

    #if DEBUG
    /// The Debug UI scenario opens the sheet on the recorded K board at Metro Van Ness Station.
    /// Production never calls this; the launch argument is absent from a normal run.
    func startFixtureIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-VelaTransitLineFixture") else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            open(
                line: "K",
                direction: "Embarcadero Station",
                stop: TransitLineStopRef(
                    stopId: "us-ca-SF-bayarea_15419",
                    name: "Metro Van Ness Station",
                    latitude: 37.775127,
                    longitude: -122.419250))
        }
    }
    #endif

    private func topViewController(_ base: UIViewController? = nil) -> UIViewController? {
        let root = base ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController
        if let navigation = root as? UINavigationController {
            return topViewController(navigation.visibleViewController)
        }
        if let tabs = root as? UITabBarController {
            return topViewController(tabs.selectedViewController)
        }
        if let presented = root?.presentedViewController {
            return topViewController(presented)
        }
        return root
    }
}
