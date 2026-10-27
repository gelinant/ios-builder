import Foundation
import VelaCore

/// What opens the Street View viewer: a place's point and the pano its sheet already shows, or
/// the debug fixture the CI scenario falls back to when Google has no imagery on the runner.
struct StreetViewRequest: Identifiable {
    let id = UUID()
    let name: String
    let latitude: Double
    let longitude: Double
    let address: String?
    let panoId: String?
    let faceBearingDeg: Double?
    var fixture = false

    static var fixtureRequest: StreetViewRequest {
        StreetViewRequest(
            name: "Vela Street View fixture",
            latitude: 38.5449, longitude: -121.7405,
            address: nil, panoId: nil, faceBearingDeg: 0,
            fixture: true)
    }

    /// The request for the open place sheet, faced toward the place from its pano.
    static func place(name: String, latitude: Double, longitude: Double, address: String?,
                      panoId: String?, yawDeg: Double?) -> StreetViewRequest {
        StreetViewRequest(
            name: name, latitude: latitude, longitude: longitude, address: address,
            panoId: panoId, faceBearingDeg: yawDeg)
    }
}

/// SwiftUI's side of the Kotlin `StreetViewStore`: mirrors the pano, the load and the error.
/// Main thread only.
final class StreetViewModel: ObservableObject {
    @Published private(set) var pano: StreetViewPano?
    @Published private(set) var loading = false
    @Published private(set) var error: String?

    let request: StreetViewRequest
    private let store: StreetViewStore?
    private var observing: Task<Void, Never>?
    private var started = false

    init(store: StreetViewStore?, request: StreetViewRequest) {
        self.store = store
        self.request = request
    }

    /// The facing direction the viewer opens on: Google's yaw for the place, else down the street.
    var facingDeg: Double {
        guard let pano else { return request.faceBearingDeg ?? 0 }
        if let facing = pano.initialFacingDeg { return facing.doubleValue }
        return request.faceBearingDeg ?? pano.headingDeg
    }

    func start() {
        guard !started else { return }
        started = true
        if request.fixture {
            pano = StreetViewFixture.shared.pano()
            return
        }
        guard let store else {
            error = "no_imagery"
            return
        }
        if observing == nil {
            observing = Task { @MainActor [weak self] in
                guard let self else { return }
                for await state in store.state {
                    self.pano = state.pano
                    self.loading = state.loading
                    self.error = state.error
                }
            }
        }
        store.open(
            latitude: request.latitude, longitude: request.longitude,
            address: request.address, panoId: request.panoId,
            faceBearingDeg: request.faceBearingDeg ?? .nan)
    }

    /// One step down the street. The target pano id comes from the metadata's own neighbor graph,
    /// so the hop lands on that capture and not on another year at the same spot.
    func walk(_ link: StreetViewLink) {
        store?.walk(panoId: link.panoId, faceBearingDeg: link.bearingDeg)
    }

    func close() {
        observing?.cancel()
        observing = nil
        if !request.fixture { store?.close() }
    }
}
