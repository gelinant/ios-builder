import Foundation
import VelaCore

/// The map's remote tiles for hosts without CORS headers go through `WebMapResources`, the app's
/// URLSession, rather than the WebView, so the calibrated browser identity can reach a Google
/// raster. Requests to Google hosts get the same Safari headers as place photos; everything else
/// (the elevation tiles, Esri) is left as built. The Android app's MapLibre fetches carry no
/// browser identity at all, so this is an iOS-only improvement, not a parity requirement.
final class MapTileNetwork: NSObject {
    static let shared = MapTileNetwork()

    private var googleHeaders: [(String, String)] = []
    private let lock = NSLock()
    private var rasterRequestCount = 0

    /// Loads the headers once, before the first map view asks for a tile.
    func install() {
        let headers = AppGraph.session.rasterTileHeaders().map { ($0.name, $0.value) }
        lock.lock()
        googleHeaders = headers
        lock.unlock()
    }

    /// Requests seen for a raster host (Google traffic and deep imagery, Esri satellite), for the
    /// debug line and the UI scenario. Other map traffic (OpenFreeMap, glyphs) is not counted.
    var rasterRequests: Int {
        lock.lock()
        defer { lock.unlock() }
        return rasterRequestCount
    }

    func prepare(_ request: inout URLRequest) {
        guard let host = request.url?.host?.lowercased() else { return }
        let google = host == "google.com" || host.hasSuffix(".google.com")
        let esri = host == "services.arcgisonline.com" || host.hasSuffix(".arcgisonline.com")
        guard google || esri else { return }
        lock.lock()
        rasterRequestCount += 1
        let headers = google ? googleHeaders : []
        lock.unlock()
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
    }
}
