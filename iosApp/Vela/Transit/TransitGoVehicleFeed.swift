import Foundation
import UIKit
import VelaCore

/// The estimated vehicles of the one line GO shows. It drives the same `TransitVehicleService`
/// as the live panel: points come from `TransitVehicles.markers`, interpolated from the feed's
/// live times, and every one stays "Estimated". A 20-second beat recomputes the points from the
/// clock; the store refuses a new `map/trips` call inside its four-minute window, and the calls
/// count against the live panels' 720-a-day budget. Nothing runs without a line, and nothing is
/// sent while the app is in the background. The panel's map hub is never written, so GO's
/// vehicles stay on GO's map.
final class TransitGoVehicleFeed {
    private(set) var vehicles: [TransitVehicle] = []
    /// Called on the main queue when the line's points change.
    var onChange: (() -> Void)?

    private let service: TransitVehicleService?
    private let fixture: ((Int64) -> [TransitVehicle])?
    private var observation: Task<Void, Never>?
    private var ticker: Timer?
    private var line = ""
    private var box: TransitGoMapBox?
    private var background = false
    private var tokens: [NSObjectProtocol] = []

    /// `budget` is the live panels' counter; `fixture` answers for the feed in the Debug scene,
    /// given the clock in epoch seconds.
    init(budget: TransitRequestBudget?, fixture: ((Int64) -> [TransitVehicle])? = nil) {
        self.fixture = fixture
        if fixture != nil {
            service = nil
        } else {
            let http = TransitousHttp(
                http: URLSessionVelaHttp(),
                locale: DevicePlatformLocale(),
                text: FoundationTextNormalizer())
            service = TransitVehicleService(http: http, clock: SystemClock(), budget: budget)
        }
        let center = NotificationCenter.default
        tokens.append(center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.background = true
            self?.stopTicker()
        })
        tokens.append(center.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.background = false
            if !self.line.isEmpty { self.startTicker() }
        })
    }

    deinit {
        stopTicker()
        observation?.cancel()
        service?.close()
        for token in tokens { NotificationCenter.default.removeObserver(token) }
    }

    /// Follows [line] inside [box]. An empty line stops the beat and clears the points; a new box
    /// for the same line is only used by the next allowed request. The store is never reset on a
    /// line change, so leaving and reentering the 500 m radius cannot bypass its window.
    func follow(line: String, box: TransitGoMapBox?) {
        self.box = box
        guard line != self.line else { return }
        self.line = line
        if line.isEmpty {
            stopTicker()
            vehicles = []
            onChange?()
            return
        }
        observe()
        refresh()
        startTicker()
    }

    /// The screen went away: no beat and no request until it follows a line again.
    func pause() {
        stopTicker()
        line = ""
    }

    private func observe() {
        guard observation == nil, let service else { return }
        observation = Task { @MainActor [weak self] in
            for await state in service.vehicles.state {
                self?.publish(state.vehicles)
            }
        }
    }

    /// One beat: points from the clock, then a request only if the store's window allows it.
    private func refresh() {
        guard !line.isEmpty else { return }
        let now = Int64(Date().timeIntervalSince1970)
        if let fixture {
            publish(fixture(now))
            return
        }
        guard let service else { return }
        service.tick()
        guard let box, !background else { return }
        service.refresh(
            south: box.south, west: box.west, north: box.north, east: box.east,
            zoom: 15, startEpochSec: now - 120, endEpochSec: now + 600)
    }

    private func publish(_ all: [TransitVehicle]) {
        vehicles = TransitGoMap.shared.vehiclesOn(vehicles: all, label: line)
        onChange?()
    }

    private func startTicker() {
        guard ticker == nil, !background else { return }
        let timer = Timer(timeInterval: 20, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }
}
