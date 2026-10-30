import Foundation
import MapLibre
import VelaCore

/// MapLibre iOS loads tiles through its own `NSURLSession`, not the app's HTTP client, so the
/// calibrated browser identity never reaches a Google raster otherwise. `MLNNetworkConfiguration`
/// exposes a delegate whose `willSendRequest` is the documented hook; requests to Google hosts get
/// the same Safari headers as place photos, everything else (OpenFreeMap, glyphs, sprites) is left
/// exactly as MapLibre built it. The Android app's MapLibre fetches carry no browser identity at
/// all, so this is an iOS-only improvement, not a parity requirement.
final class MapTileNetwork: NSObject, MLNNetworkConfigurationDelegate {
    static let shared = MapTileNetwork()

    private var googleHeaders: [(String, String)] = []
    private let lock = NSLock()
    private var rasterRequestCount = 0

    /// Must run before the first `MLNMapView` is created. The shared configuration keeps a weak
    /// delegate, so [shared] is the long-lived owner.
    func install() {
        let headers = AppGraph.session.rasterTileHeaders().map { ($0.name, $0.value) }
        lock.lock()
        googleHeaders = headers
        lock.unlock()
        MLNNetworkConfiguration.sharedManager.delegate = self
    }

    /// Requests seen for a raster host (Google traffic and deep imagery, Esri satellite), for the
    /// debug line and the UI scenario. Other MapLibre traffic (OpenFreeMap, glyphs) is not counted.
    var rasterRequests: Int {
        lock.lock()
        defer { lock.unlock() }
        return rasterRequestCount
    }

    func willSend(_ request: NSMutableURLRequest) -> NSMutableURLRequest {
        guard let host = request.url?.host?.lowercased() else { return request }
        let google = host == "google.com" || host.hasSuffix(".google.com")
        let esri = host == "services.arcgisonline.com" || host.hasSuffix(".arcgisonline.com")
        if google || esri {
            lock.lock()
            rasterRequestCount += 1
            let headers = google ? googleHeaders : []
            lock.unlock()
            for (name, value) in headers {
                request.setValue(value, forHTTPHeaderField: name)
            }
        }
        return request
    }
}
