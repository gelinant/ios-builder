import Foundation
import VelaCore

/// SwiftUI's mirror of the live calibration version (`IosCalibration.version`, through SKIE):
/// 0 before the session starts, then the cached or compiled bundle's, then the refreshed one's.
/// Debug builds show it on the map (accessibility identifier `calibration-debug`). Main thread only.
final class CalibrationModel: ObservableObject {
    @Published private(set) var version = 0

    private let calibration: IosCalibration?
    private var observing: Task<Void, Never>?

    init(calibration: IosCalibration?) {
        self.calibration = calibration
    }

    func start() {
        guard let calibration, observing == nil else { return }
        observing = Task { @MainActor [weak self] in
            for await value in calibration.version {
                self?.version = value.intValue
            }
        }
    }

    deinit {
        observing?.cancel()
    }
}
