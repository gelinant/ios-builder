import Foundation
import Network
import VelaCore

/// NWPathMonitor is the iOS counterpart of Android's connectivity callback. Search still falls back
/// to installed data when a request fails, so an initially stale satisfied path is harmless.
final class OfflineNetworkMonitor {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "app.vela.ios.offline-network")

    init(store: OfflineStore) {
        monitor.pathUpdateHandler = { [weak store] path in
            DispatchQueue.main.async {
                store?.setNetworkAvailable(available: path.status == .satisfied)
            }
        }
        monitor.start(queue: queue)
    }

    deinit { monitor.cancel() }
}
