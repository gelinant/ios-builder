import SwiftUI
import UIKit
import VelaCore

/// The trips sheet: the opt-in switch, the saved drives and the way to diagnostics.
struct TripsView: View {
    @StateObject private var model: TripsModel
    @State private var showsDiagnostics = false
    @Environment(\.dismiss) private var dismiss

    init(store: TripsStore?) {
        _model = StateObject(wrappedValue: TripsModel(store: store))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Save my trips", isOn: Binding(
                        get: { model.recording },
                        set: { model.setRecording($0) }))
                        .accessibilityIdentifier("trips-recording-toggle")
                    Text("Recorded drives stay on this phone. Sharing trims both ends first.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    #if DEBUG
                    Text("recording=\(model.recording ? 1 : 0) trips=\(model.trips.count)")
                        .font(.caption2)
                        .opacity(0.01)
                        .accessibilityIdentifier("trips-debug")
                    #endif
                }
                Section {
                    if model.trips.isEmpty {
                        Text("No recorded trips yet. Start navigation with saving on.")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("trips-empty")
                    }
                    ForEach(model.trips, id: \.id) { trip in
                        NavigationLink {
                            TripDetailView(
                                model: model.detailModel(trip, onChanged: { model.reload() }),
                                trips: model)
                        } label: {
                            TripRow(trip: trip)
                        }
                        .accessibilityIdentifier("trip-row")
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                model.delete(trip.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Trips")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Diagnostics") { showsDiagnostics = true }
                        .accessibilityIdentifier("trips-diagnostics")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("trips-done")
                }
            }
            .onAppear { model.reload() }
            .sheet(isPresented: $showsDiagnostics) {
                DiagnosticsView()
            }
        }
    }
}

private struct TripRow: View {
    let trip: TripSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(trip.label)
                    .font(.headline)
                    .lineLimit(1)
                if trip.partial {
                    Text("Partial")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.orange.opacity(0.2), in: Capsule())
                        .foregroundStyle(.orange)
                }
            }
            Text("\(TripsModel.dateText(trip.startedAt)) · \(TripsModel.distanceText(trip.distanceM)) · \(TripsModel.durationText(trip.durationMs))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Start \(TripsModel.timeText(trip.startedAt)) · End \(TripsModel.timeText(trip.startedAt + trip.durationMs)) · \(Int(trip.fixes)) fixes")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

/// One saved drive: the recorded line, the speed profile, the stops and the share trim.
struct TripDetailView: View {
    @ObservedObject var model: TripDetailModel
    @ObservedObject var trips: TripsModel
    @Environment(\.dismiss) private var dismiss
    @State private var share: SharePayload?
    @State private var confirmsDelete = false
    @State private var showsRename = false
    @State private var renameText = ""
    @State private var showsExportError = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TripDetailMap(points: model.detail?.points ?? [])
                    .frame(height: 230)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("trip-detail-map")

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.currentLabel)
                        .font(.title3.weight(.semibold))
                        .accessibilityIdentifier("trip-detail-label")
                    Text(TripsModel.dateText(model.summary.startedAt))
                        .foregroundStyle(.secondary)
                    if model.summary.partial {
                        Text("This recording was interrupted. Keep it to turn it into a normal trip.")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                        Button("Keep partial trip") { model.keepPartial() }
                            .accessibilityIdentifier("trip-keep")
                    }
                }

                HStack(spacing: 22) {
                    stat("Distance", TripsModel.distanceText(model.summary.distanceM))
                    stat("Duration", TripsModel.durationText(model.summary.durationMs))
                    stat("Fixes", "\(Int(model.summary.fixes))")
                        .accessibilityIdentifier("trip-fixes")
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Speed profile")
                        .font(.headline)
                    SpeedProfile(points: model.detail?.points ?? [])
                        .frame(height: 110)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Speed profile")
                        .accessibilityIdentifier("trip-speed-profile")
                    HStack {
                        Text("Average \(TripsModel.speedText(model.detail?.averageSpeedMps ?? 0))")
                        Spacer()
                        Text("Max \(TripsModel.speedText(model.detail?.maxSpeedMps ?? 0))")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if let detail = model.detail, !detail.stops.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Stops")
                            .font(.headline)
                        ForEach(Array(detail.stops.enumerated()), id: \.offset) { index, stop in
                            Text("Stop \(index + 1) · \(max(1, Int((stop.endMs - stop.startMs) / 1000))) s")
                                .font(.subheadline)
                                .accessibilityIdentifier("trip-stop")
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Share")
                        .font(.headline)
                    Picker("Trim ends", selection: Binding(
                        get: { model.radius },
                        set: { model.updateTrim($0) })) {
                            Text("200 m").tag(200.0)
                            Text("400 m").tag(400.0)
                            Text("800 m").tag(800.0)
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("trip-trim")
                    Text(model.trimmedSummary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("trip-trim-summary")
                    HStack {
                        Button("Share GPX") { export(gpx: true) }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("trip-share-gpx")
                        Button("Share Vela CSV") { export(gpx: false) }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("trip-share-csv")
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Trip")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("trip-detail")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Rename") {
                        renameText = model.currentLabel
                        showsRename = true
                    }
                    .accessibilityIdentifier("trip-rename")
                    Button("Delete", role: .destructive) { confirmsDelete = true }
                        .accessibilityIdentifier("trip-delete")
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityIdentifier("trip-menu")
            }
        }
        .alert("Rename trip", isPresented: $showsRename) {
            TextField("Name", text: $renameText)
                .accessibilityIdentifier("trip-rename-field")
            Button("Cancel", role: .cancel) {}
            Button("Save") { model.rename(renameText) }
        }
        .alert("Delete this trip?", isPresented: $confirmsDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                model.delete()
                dismiss()
            }
        }
        .alert("Nothing to share", isPresented: $showsExportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This drive is too short to trim, so it is not exported.")
        }
        .sheet(item: $share) { payload in
            ActivitySheet(items: payload.items)
        }
    }

    private func export(gpx: Bool) {
        guard let url = model.exportFile(gpx: gpx) else {
            showsExportError = true
            return
        }
        share = SharePayload(items: [url])
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.medium))
        }
        .accessibilityElement(children: .combine)
    }
}

/// The speed over the drive, filled under the line. Times come from the rebased recording.
struct SpeedProfile: View {
    let points: [TripPoint]

    var body: some View {
        Canvas { context, size in
            guard points.count > 1 else { return }
            let maxSpeed = max(1.0, points.map(\.speedMps).max() ?? 1.0)
            let lastTime = max(1.0, Double(points.last?.tMs ?? 1))
            func point(_ p: TripPoint) -> CGPoint {
                CGPoint(
                    x: Double(p.tMs) / lastTime * size.width,
                    y: size.height - min(1.0, p.speedMps / maxSpeed) * (size.height - 6) - 3)
            }
            var line = Path()
            var area = Path()
            let first = point(points[0])
            area.move(to: CGPoint(x: first.x, y: size.height))
            area.addLine(to: first)
            line.move(to: first)
            for p in points.dropFirst() {
                let next = point(p)
                line.addLine(to: next)
                area.addLine(to: next)
            }
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.closeSubpath()
            context.fill(area, with: .color(.accentColor.opacity(0.22)))
            context.stroke(line, with: .color(.accentColor), lineWidth: 2)
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct SharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
