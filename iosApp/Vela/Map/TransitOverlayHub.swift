import Foundation
import VelaCore

/// The one mailbox between the transit panels and the map. The live panel and the vehicles panel
/// already own their models and their requests; they write the results here, and `MapController`
/// reads them. The map therefore never asks for anything, and a panel that closes keeps its last
/// payload on the map instead of blanking it. A new payload replaces the previous one, so opening
/// a panel again redraws the same layer rather than stacking a second copy.
///
/// Main thread only: the models publish from their `@MainActor` observations and from their on
/// switch, and the controller reads from a main-queue notification.
final class TransitOverlayHub {
    static let shared = TransitOverlayHub()
    static let changed = Notification.Name("vela.transit.overlays.changed")

    /// The live lines of T-2, exactly the descriptors the panel holds.
    private(set) var lines: [TransitLiveLine] = []
    /// The reachability hull, when the panel asked for one.
    private(set) var reach: TransitReachArea?
    /// The estimated vehicles of TRANSIT-INTERP, already interpolated by the panel model.
    private(set) var vehicles: [TransitVehicle] = []
    /// The vehicles switch as the panel last left it, so a reopened panel shows the same state.
    private(set) var vehiclesOn = false

    private(set) var linesRevision = 0
    private(set) var reachRevision = 0
    private(set) var vehiclesRevision = 0

    private init() {}

    /// Replaces the drawn lines. An empty list is a deliberate clear, not a failed answer; the
    /// panels only send what the feed or the fixture produced.
    func publish(lines models: [TransitLiveLine]) {
        lines = models
        linesRevision += 1
        notify()
    }

    func publish(reach area: TransitReachArea?) {
        reach = area
        reachRevision += 1
        notify()
    }

    /// Replaces the estimated vehicles and records the switch. Turning the layer off publishes an
    /// empty list, which removes the markers; closing the panel publishes nothing.
    func publish(vehicles models: [TransitVehicle], on: Bool) {
        vehicles = models
        vehiclesOn = on
        vehiclesRevision += 1
        notify()
    }

    private func notify() {
        NotificationCenter.default.post(name: Self.changed, object: self)
    }
}
