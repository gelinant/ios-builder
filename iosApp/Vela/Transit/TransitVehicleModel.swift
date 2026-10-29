import Foundation
import SwiftUI
import UIKit
import VelaCore

/// The vehicles layer's Swift state. It drives the shared `TransitVehicleStore`, whose points are
/// interpolated from the feed's live times along each stretch; the feed has no vehicle GPS, so
/// every card and every label says "Estimated". The layer is off until the user turns it on, the
/// 20-second timer only recomputes from the clock, and no request is sent from a timer when the
/// app is in the background. Production asks Transitous through the same 720-a-day budget as the
/// live panels; `-VelaTransitVehicleFixture` answers from `TransitVehicleFixtures` with no network.
final class TransitVehicleModel: ObservableObject {
    @Published private(set) var vehicles: [TransitVehicle] = []
    @Published private(set) var on = false
    @Published private(set) var loading = false
    @Published private(set) var error = ""
    @Published private(set) var runs = 0
    @Published private(set) var liveTimes = 0
    @Published private(set) var requests = 0
    @Published private(set) var fixture = false

    private let service: TransitVehicleService?
    private var observation: Task<Void, Never>?
    private var ticker: Timer?
    private var started = false
    private var origin: (lat: Double, lng: Double)?
    private var background = false
    private var foregroundToken: NSObjectProtocol?
    private var backgroundToken: NSObjectProtocol?

    init(live: TransitLiveService?, lat: Double, lng: Double) {
        origin = (lat, lng)
        var isFixture = false
        #if DEBUG
        isFixture = ProcessInfo.processInfo.arguments.contains("-VelaTransitVehicleFixture")
        #endif
        fixture = isFixture
        if isFixture || live == nil {
            service = nil
        } else {
            let http = TransitousHttp(
                http: URLSessionVelaHttp(),
                locale: DevicePlatformLocale(),
                text: FoundationTextNormalizer())
            // The same daily counter as the reach and live-line panels, so one layer cannot
            // spend the fair-use budget alone.
            service = TransitVehicleService(http: http, clock: SystemClock(), budget: live?.budget)
        }
    }

    func start() {
        guard !started else { return }
        started = true
        guard let service else { return }
        observation = Task { @MainActor [weak self] in
            for await state in service.vehicles.state {
                self?.apply(state)
            }
        }
        let center = NotificationCenter.default
        foregroundToken = center.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.setBackground(false) }
        }
        backgroundToken = center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.setBackground(true) }
        }
    }

    func setOrigin(lat: Double, lng: Double) {
        origin = (lat, lng)
    }

    /// The layer's on switch. Turning it off cancels the timer and clears the shared store; no
    /// request leaves the device while it is off.
    func setOn(_ value: Bool) {
        guard value != on else { return }
        on = value
        if value {
            #if DEBUG
            if fixture {
                vehicles = TransitVehicleFixtures.vehicles
                runs = TransitVehicleFixtures.runs
                liveTimes = vehicles.count
                loading = false
                error = ""
            } else {
                loading = true
                refresh()
            }
            #else
            loading = true
            refresh()
            #endif
            startTicker()
        } else {
            stopTicker()
            vehicles = []
            runs = 0
            liveTimes = 0
            service?.close()
        }
    }

    /// Sheet dismissal: no timer, no request, nothing drawn from a closed panel.
    func stop() {
        stopTicker()
        observation?.cancel()
        observation = nil
        if let token = foregroundToken { NotificationCenter.default.removeObserver(token) }
        if let token = backgroundToken { NotificationCenter.default.removeObserver(token) }
        foregroundToken = nil
        backgroundToken = nil
        service?.close()
        started = false
        on = false
        vehicles = []
    }

    /// Returns the movement is from the clock: each 20-second beat asks the store to recompute
    /// its points from the stretches it already holds. A data refresh still obeys the store's
    /// four-minute window, so the timer never multiplies the request count.
    private func tick() {
        guard on else { return }
        if fixture {
            // The fixture keeps its fixed clock; nothing moves and no request is possible.
            liveTimes = vehicles.count
            return
        }
        guard let service else { return }
        service.tick()
        if let origin, !background {
            let now = Int64(Date().timeIntervalSince1970)
            service.refresh(
                south: origin.lat - 0.02, west: origin.lng - 0.02,
                north: origin.lat + 0.02, east: origin.lng + 0.02,
                zoom: 15, startEpochSec: now - 120, endEpochSec: now + 600)
        }
    }

    private func refresh() {
        guard let origin, let service else { return }
        let now = Int64(Date().timeIntervalSince1970)
        service.request(
            south: origin.lat - 0.02, west: origin.lng - 0.02,
            north: origin.lat + 0.02, east: origin.lng + 0.02,
            zoom: 15, startEpochSec: now - 120, endEpochSec: now + 600)
        error = ""
        requests += 1
    }

    private func startTicker() {
        guard ticker == nil else { return }
        let timer = Timer(timeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func setBackground(_ value: Bool) {
        background = value
        if value { stopTicker() } else if on { startTicker() }
    }

    private func apply(_ state: TransitVehiclesState) {
        vehicles = state.vehicles
        loading = state.loading
        error = state.error ?? ""
        runs = Int(state.runs)
        liveTimes = Int(state.liveTimes)
    }

    var estimated: Bool { vehicles.allSatisfy { $0.estimated } && !vehicles.isEmpty }

    var debugLine: String {
        "vehicles=\(vehicles.count) runs=\(runs) live_times=\(liveTimes)"
            + " estimated=\(estimated ? 1 : 0) on=\(on ? 1 : 0) fixture=\(fixture ? 1 : 0)"
            + " requests=\(requests) error=\(error.isEmpty ? "none" : error)"
    }
}

/// The vehicles tab of the live panel. The switch is the layer's on control; the caption and
/// every row keep the estimate honest in words and in VoiceOver.
struct TransitVehiclePanel: View {
    @StateObject private var model: TransitVehicleModel
    private let originName: String

    init(live: TransitLiveService?, lat: Double, lng: Double, originName: String) {
        _model = StateObject(wrappedValue: TransitVehicleModel(live: live, lat: lat, lng: lng))
        self.originName = originName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            #if DEBUG
            Text(model.debugLine)
                .font(.caption2.monospaced())
                .accessibilityIdentifier("transit-vehicles-debug")
            #endif
            Toggle("Show vehicles", isOn: Binding(
                get: { model.on },
                set: { model.setOn($0) }))
                .frame(minHeight: 44)
                .accessibilityIdentifier("transit-vehicles-toggle")
            Text("Positions are estimated from each trip's live times along its stretch polyline. Transitous publishes no vehicle GPS, so a marker is not a measured position and can sit between the real vehicle and the stop it serves.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("transit-vehicles-caption")

            if model.loading && model.vehicles.isEmpty {
                ProgressView("Loading live times")
                    .accessibilityIdentifier("transit-vehicles-loading")
            }
            if !model.error.isEmpty {
                Text(model.error == "rate_limited"
                     ? "Transitous asked Vela to slow down."
                     : "Live times are unavailable; the last estimate stays.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("transit-vehicles-error")
            }
            if model.on && model.vehicles.isEmpty && !model.loading {
                Text("No vehicle has live times in this view right now.")
                    .font(.subheadline)
                    .accessibilityIdentifier("transit-vehicles-empty")
            }
            ForEach(model.vehicles, id: \.id) { vehicle in
                TransitVehicleRow(vehicle: vehicle)
            }
            if !model.vehicles.isEmpty {
                Text("\(model.vehicles.count) vehicles around \(originName.isEmpty ? "this point" : originName), estimated from live times, not GPS.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("transit-vehicles-summary")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }
}

/// One row: line badge in the agency or mode color, the direction, the next stop, and a visible
/// "Estimated" word the VoiceOver label repeats.
struct TransitVehicleRow: View {
    let vehicle: TransitVehicle

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(vehicle.label)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(uiColor: UIColor(transitHex: vehicle.colorHex) ?? .systemBlue))
                .clipShape(Capsule())
            VStack(alignment: .leading, spacing: 2) {
                Text("towards \(vehicle.headsign)")
                    .font(.subheadline.weight(.semibold))
                Text("Next stop: \(vehicle.nextStopName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let delay = vehicle.delayMinutes?.int32Value {
                    Text(delay == 0 ? "On time" : "\(abs(delay)) min \(delay > 0 ? "late" : "early")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Text("Estimated")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.orange)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityIdentifier("transit-vehicle")
    }

    private var label: String {
        var parts = ["Line \(vehicle.label)", "towards \(vehicle.headsign)",
                     "next stop \(vehicle.nextStopName)",
                     "estimated from live times, not GPS"]
        if let delay = vehicle.delayMinutes?.int32Value {
            parts.append(delay == 0 ? "on time" : "\(abs(delay)) minutes \(delay > 0 ? "late" : "early")")
        }
        return parts.joined(separator: ", ")
    }
}

#if DEBUG
/// The deterministic rows behind `-VelaTransitVehicleFixture`: four labels and directions from
/// the captured Berlin `map/trips` reply of 2026-10-28. Their positions sit on the corridor of
/// the real stretch and stand in for a mid-segment interpolation; they are not measured.
enum TransitVehicleFixtures {
    static let runs = 6

    static let vehicles: [TransitVehicle] = [
        TransitVehicles.shared.mapped(
            id: "fixture-s7", label: "S7", mode: "TRAIN", colorHex: "#816da6",
            feedColorHex: "#816da6", headsign: "S+U Alexanderplatz Bhf (Berlin)",
            fromStopName: "S Ostkreuz Bhf (Berlin)", nextStopName: "S+U Alexanderplatz Bhf (Berlin)",
            lat: 52.5140, lng: 13.4180, bearing: 300, fraction: 0.55,
            delayMinutes: 0, hasDelay: true, destinationEpochSec: 0),
        TransitVehicles.shared.mapped(
            id: "fixture-u2", label: "U2", mode: "SUBWAY", colorHex: "#da421e",
            feedColorHex: "#da421e", headsign: "U Rosa-Luxemburg-Platz (Berlin)",
            fromStopName: "S+U Alexanderplatz Bhf (Berlin)", nextStopName: "U Rosa-Luxemburg-Platz (Berlin)",
            lat: 52.5225, lng: 13.4125, bearing: 310, fraction: 0.30,
            delayMinutes: 0, hasDelay: false, destinationEpochSec: 0),
        TransitVehicles.shared.mapped(
            id: "fixture-m4", label: "M4", mode: "TRAM", colorHex: "#437c93",
            feedColorHex: nil, headsign: "S+U Alexanderplatz Bhf/Gontardstr. (Berlin)",
            fromStopName: "S+U Alexanderplatz Bhf (Berlin)", nextStopName: "S+U Alexanderplatz Bhf/Gontardstr. (Berlin)",
            lat: 52.5203, lng: 13.4046, bearing: 90, fraction: 0.60,
            delayMinutes: 0, hasDelay: false, destinationEpochSec: 0),
        TransitVehicles.shared.mapped(
            id: "fixture-100", label: "100", mode: "BUS", colorHex: "#0f6cbd",
            feedColorHex: nil, headsign: "Memhardstr. (Berlin)",
            fromStopName: "S+U Alexanderplatz Bhf/Memhardstr. (Berlin)", nextStopName: "Memhardstr. (Berlin)",
            lat: 52.5210, lng: 13.4100, bearing: 270, fraction: 0.20,
            delayMinutes: 3, hasDelay: true, destinationEpochSec: 0),
    ]
}
#endif
