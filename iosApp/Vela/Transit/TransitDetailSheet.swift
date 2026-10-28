import SwiftUI
import UIKit

/// The selected transit itinerary in detail: every walk and ride, the board and alight stops with
/// their times, the intermediate stops the planner returned, and any service alerts and fare the
/// feed carried. Start hands the same itinerary to the process-owned TransitSession.
struct TransitDetailSheet: View {
    @ObservedObject var model: TransitModel
    let onClose: () -> Void
    let onStart: () -> Void

    @State private var showsTrip = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let detail = model.detail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        summary(detail)
                        if !detail.alerts.isEmpty {
                            alerts(detail.alerts)
                        }
                        ForEach(detail.legs) { leg in
                            legView(leg)
                        }
                        #if DEBUG
                        Text(model.optionsDebugLine)
                            .font(.caption2.monospaced())
                            .accessibilityIdentifier("transit-detail-debug")
                        #endif
                        Text("Times are scheduled unless the feed marked the run live. Vela does not estimate the missing ones.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                }
            } else {
                Spacer()
                ProgressView()
                Spacer()
            }
            Divider()
            HStack(spacing: 12) {
                Button("Close") { onClose() }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("steps-close")
                Spacer()
                Button {
                    showsTrip = true
                } label: {
                    Label("Trip view", systemImage: "list.bullet.rectangle")
                }
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
                .disabled(model.tripScreenTrip == nil)
                .accessibilityIdentifier("transit-trip-open")
                Button {
                    onStart()
                } label: {
                    Label("Start transit", systemImage: "tram.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.detail == nil)
                .accessibilityIdentifier("transit-start")
            }
            .padding(12)
        }
        .background(Color(uiColor: .systemBackground))
        .accessibilityIdentifier("steps-sheet")
        .fullScreenCover(isPresented: $showsTrip) {
            TransitTripScreen(
                model: model.trip,
                destination: model.destinationName,
                onClose: {
                    model.trip.close()
                    showsTrip = false
                })
            .onAppear {
                if let trip = model.tripScreenTrip { model.trip.open(trip: trip) }
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Trip details")
                    .font(.headline)
                Text(model.destinationName.isEmpty ? "Transit" : model.destinationName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func summary(_ detail: TransitDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                if let depart = detail.departureText {
                    Label(depart, systemImage: "arrow.up.right")
                        .font(.subheadline.weight(.semibold))
                }
                if let duration = detail.durationText {
                    Text(duration)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let arrive = detail.arrivalText {
                    Label(arrive, systemImage: "arrow.down.left")
                        .font(.subheadline.weight(.semibold))
                }
            }
            if let agency = detail.agency, !agency.isEmpty {
                Text(agency)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let fare = detail.fare, !fare.isEmpty {
                Label(fare, systemImage: "creditcard")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func alerts(_ alerts: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Service alerts", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            ForEach(Array(alerts.enumerated()), id: \.offset) { _, alert in
                Text(alert)
                    .font(.caption)
                    .accessibilityIdentifier("transit-detail-alert")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    private func legView(_ leg: TransitDetailLeg) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                if leg.isWalk {
                    Image(systemName: "figure.walk")
                        .font(.title3)
                        .frame(width: 34)
                } else {
                    TransitLinePill(label: leg.line ?? "Transit", color: leg.color)
                        .frame(minWidth: 34)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(leg.isWalk ? "Walk" : (leg.headsign.map { "towards \($0)" } ?? "Ride"))
                        .font(.subheadline.weight(.semibold))
                    HStack(spacing: 8) {
                        if let duration = leg.durationText {
                            Text(duration)
                        }
                        if let distance = leg.distanceText, !distance.isEmpty {
                            Text(distance)
                        }
                        if let delay = leg.delayText, !delay.isEmpty {
                            Text(delay).foregroundStyle(.orange)
                        }
                        if leg.stopCount > 0 {
                            Text("\(leg.stopCount) stops")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            if let board = leg.board {
                stopRow("Board", board)
            }
            if leg.intermediate.count > 0, !leg.isWalk {
                ForEach(leg.intermediate) { stop in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.secondary.opacity(0.5))
                            .frame(width: 5, height: 5)
                            .padding(.leading, 14)
                        Text(stop.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        if let time = stop.timeText ?? stop.scheduledText {
                            Text(time)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if let alight = leg.alight {
                stopRow("Get off", alight)
            }
        }
        .padding(10)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier("transit-detail-leg")
    }

    private func stopRow(_ title: String, _ stop: TransitDetailStop) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .frame(width: 48, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(stop.name)
                    .font(.subheadline)
                    .strikethrough(stop.canceled)
                if let code = stop.code, !code.isEmpty {
                    Text("Stop \(code)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if let scheduled = stop.scheduledText, let time = stop.timeText, scheduled != time {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(time)
                        .font(.caption.monospacedDigit())
                    Text(scheduled)
                        .font(.caption2.monospacedDigit())
                        .strikethrough()
                        .foregroundStyle(.secondary)
                }
            } else if let time = stop.timeText ?? stop.scheduledText {
                Text(time)
                    .font(.caption.monospacedDigit())
            }
        }
    }
}
