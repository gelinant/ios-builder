#if DEBUG
import Foundation

/// Debug-only HTTP request counter, split between Google hosts and every other host, so a UI
/// scenario can prove that "Use Vela without Google" made no Google request while routing. The
/// counters reset at the moment the route chooser opens: requests from an earlier search or from
/// calibration are not charged to the route. Compiled in Debug only; the Release archive has no
/// counter and no debug line.
final class DebugRequestCounter {
    static let shared = DebugRequestCounter()

    private let lock = NSLock()
    private var google = 0
    private var open = 0
    private var googleAtRouteOpen = 0
    private var openAtRouteOpen = 0

    private init() {}

    /// Counts one request. A request whose host cannot be read counts as neither.
    func record(_ url: URL?) {
        guard let host = url?.host?.lowercased() else { return }
        lock.lock()
        if Self.isGoogle(host) { google += 1 } else { open += 1 }
        lock.unlock()
    }

    /// Called when the route chooser opens, before its first fetch.
    func markRouteOpen() {
        lock.lock()
        googleAtRouteOpen = google
        openAtRouteOpen = open
        lock.unlock()
    }

    /// Requests since the chooser opened, by kind.
    var sinceRouteOpen: (google: Int, open: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (google - googleAtRouteOpen, open - openAtRouteOpen)
    }

    /// Whether [host] is Google's. The keyless data endpoints, Street View tiles and the consent
    /// page all sit on google.com or one of its subdomains; googleapis.com carries the Street View
    /// and photo hosts. A lookalike such as notgoogle.com stays out.
    static func isGoogle(_ host: String) -> Bool {
        let names = ["google.com", "googleapis.com", "googlevideo.com", "gstatic.com",
                     "googleusercontent.com", "ggpht.com"]
        return names.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}
#endif
