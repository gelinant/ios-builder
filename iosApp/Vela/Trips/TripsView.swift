import SwiftUI
import UIKit
import VelaCore

/// The trips sheet: the opt-in switch, the saved drives and the way to diagnostics.
struct TripsView: View {
    @StateObject private var model: TripsModel
    @ObservedObject private var folder = TraceFolderStore.shared
    @State private var activeSheet: TripsSheet?
    @Environment(\.dismiss) private var dismiss

    /// One sheet at a time; two `.sheet` modifiers on the same view made the second one refuse
    /// to present once a folder picker joined Diagnostics.
    private enum TripsSheet: String, Identifiable {
        case diagnostics, folder
        var id: String { rawValue }
    }

    init(store: TripsStore?) {
        _model = StateObject(wrappedValue: TripsModel(store: store))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(VelaL10n.text("root_diag_trips_title"), isOn: Binding(
                        get: { model.recording },
                        set: { model.setRecording($0) }))
                        .accessibilityIdentifier("trips-recording-toggle")
                    Text(VelaL10n.text("trips_recorded_drives_stay_on_this_phone"))
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
                    Text(VelaL10n.text("trips_trace_folder"))
                        .font(.headline)
                        .accessibilityIdentifier("trips-trace-folder-title")
                    if folder.hasFolder, let name = folder.folderName {
                        Text(name)
                            .font(.subheadline)
                            .accessibilityIdentifier("trips-trace-folder-name")
                    } else {
                        Text(VelaL10n.text("trips_no_folder_chosen_finished_drives_stay"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("trips-trace-folder-none")
                    }
                    Button(folder.hasFolder ? VelaL10n.text("trips_change_folder") : VelaL10n.text("trips_choose_folder")) {
                        activeSheet = .folder
                    }
                    .accessibilityIdentifier("trips-trace-folder-choose")
                    if folder.hasFolder {
                        Button(VelaL10n.text("trips_forget_folder"), role: .destructive) { folder.forget() }
                            .accessibilityIdentifier("trips-trace-folder-forget")
                    }
                    if let error = folder.lastError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("trips-trace-folder-error")
                    }
                    Text(VelaL10n.text("trips_ios_gives_vela_access_only_to"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("trips-trace-folder-note")
                }
                Section {
                    if model.trips.isEmpty {
                        Text(VelaL10n.text("trips_no_recorded_trips_yet_start_navigation"))
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
                                Label(VelaL10n.text("parking_history_delete"), systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle(VelaL10n.text("trips_trips"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(VelaL10n.text("settings_diagnostics")) { activeSheet = .diagnostics }
                        .accessibilityIdentifier("trips-diagnostics")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(VelaL10n.text("settings_trip_select_done")) { dismiss() }
                        .accessibilityIdentifier("trips-done")
                }
            }
            .onAppear { model.reload() }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .diagnostics:
                    DiagnosticsView()
                case .folder:
                    TraceFolderPicker { url in
                        activeSheet = nil
                        _ = folder.remember(url)
                    }
                }
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
                    Text(VelaL10n.text("trips_partial"))
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
            Text(VelaL10n.text("trips_start_end_fixes", String(describing: (TripsModel.timeText(trip.startedAt))), String(describing: (TripsModel.timeText(trip.startedAt + trip.durationMs))), String(describing: (Int(trip.fixes)))))
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
    @ObservedObject private var folder = TraceFolderStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var share: SharePayload?
    @State private var confirmsDelete = false
    @State private var showsRename = false
    @State private var renameText = ""
    @State private var showsExportError = false
    @State private var showsReplay = false
    @State private var traceNotice: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TripDetailMap(points: model.detail?.points ?? [])
                    .frame(height: 230)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("trip-detail-map")
                Button {
                    showsReplay = true
                } label: {
                    Label(VelaL10n.text("trips_replay_demo"), systemImage: "play.circle")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("trip-replay")

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.currentLabel)
                        .font(.title3.weight(.semibold))
                        .accessibilityIdentifier("trip-detail-label")
                    Text(TripsModel.dateText(model.summary.startedAt))
                        .foregroundStyle(.secondary)
                    if model.summary.partial {
                        Text(VelaL10n.text("trips_this_recording_was_interrupted_keep_it"))
                            .font(.footnote)
                            .foregroundStyle(.orange)
                        Button(VelaL10n.text("trips_keep_partial_trip")) { model.keepPartial() }
                            .accessibilityIdentifier("trip-keep")
                    }
                }

                HStack(spacing: 22) {
                    stat(VelaL10n.text("trips_distance"), TripsModel.distanceText(model.summary.distanceM))
                    stat(VelaL10n.text("trips_duration"), TripsModel.durationText(model.summary.durationMs))
                    stat(VelaL10n.text("trips_fix_count"), "\(Int(model.summary.fixes))")
                        .accessibilityIdentifier("trip-fixes")
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(VelaL10n.text("trips_speed_profile"))
                        .font(.headline)
                    SpeedProfile(points: model.detail?.points ?? [])
                        .frame(height: 110)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(VelaL10n.text("trips_speed_profile"))
                        .accessibilityIdentifier("trip-speed-profile")
                    HStack {
                        Text(VelaL10n.text("trips_average", String(describing: (TripsModel.speedText(model.detail?.averageSpeedMps ?? 0)))))
                        Spacer()
                        Text(VelaL10n.text("trips_max", String(describing: (TripsModel.speedText(model.detail?.maxSpeedMps ?? 0)))))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if let detail = model.detail, !detail.stops.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(VelaL10n.text("stops_editor_title"))
                            .font(.headline)
                        ForEach(Array(detail.stops.enumerated()), id: \.offset) { index, stop in
                            Text(VelaL10n.text("trips_stop_1000_s", String(describing: (index + 1)), String(describing: (max(1, Int((stop.endMs - stop.startMs) / 1000))))))
                                .font(.subheadline)
                                .accessibilityIdentifier("trip-stop")
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(VelaL10n.text("settings_trip_share"))
                        .font(.headline)
                    Picker(VelaL10n.text("trips_trim_ends"), selection: Binding(
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
                        Button(VelaL10n.text("trips_share_gpx")) { export(gpx: true) }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("trip-share-gpx")
                        Button(VelaL10n.text("trips_share_vela_csv")) { export(gpx: false) }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("trip-share-csv")
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(VelaL10n.text("trips_full_trace"))
                        .font(.headline)
                    Text(VelaL10n.text("trips_saves_every_fix_to_the_trace"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("trip-save-full-note")
                    Button(VelaL10n.text("trips_save_full_trace")) { saveFullTrace() }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("trip-save-full")
                }
            }
            .padding()
        }
        .navigationTitle(VelaL10n.text("mapvm_trip_default_name"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("trip-detail")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(VelaL10n.text("settings_trip_rename")) {
                        renameText = model.currentLabel
                        showsRename = true
                    }
                    .accessibilityIdentifier("trip-rename")
                    Button(VelaL10n.text("parking_history_delete"), role: .destructive) { confirmsDelete = true }
                        .accessibilityIdentifier("trip-delete")
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityIdentifier("trip-menu")
            }
        }
        .alert(VelaL10n.text("trips_rename_trip"), isPresented: $showsRename) {
            TextField(VelaL10n.text("route_save_hint"), text: $renameText)
                .accessibilityIdentifier("trip-rename-field")
            Button(VelaL10n.text("settings_cancel"), role: .cancel) {}
            Button(VelaL10n.text("place_save")) { model.rename(renameText) }
        }
        .alert(VelaL10n.text("trips_delete_this_trip"), isPresented: $confirmsDelete) {
            Button(VelaL10n.text("settings_cancel"), role: .cancel) {}
            Button(VelaL10n.text("parking_history_delete"), role: .destructive) {
                model.delete()
                dismiss()
            }
        }
        .alert(VelaL10n.text("trips_nothing_to_share"), isPresented: $showsExportError) {
            Button(VelaL10n.text("map_ok"), role: .cancel) {}
        } message: {
            Text(VelaL10n.text("trips_this_drive_is_too_short_to"))
        }
        .sheet(item: $share) { payload in
            ActivitySheet(items: payload.items)
        }
        .fullScreenCover(isPresented: $showsReplay) {
            TripReplayView(
                tripID: model.summary.id, store: AppGraph.session.trips,
                onClose: { showsReplay = false })
        }
        .alert(VelaL10n.text("trips_full_trace"), isPresented: Binding(
            get: { traceNotice != nil },
            set: { if !$0 { traceNotice = nil } })) {
            Button(VelaL10n.text("map_ok"), role: .cancel) {}
        } message: {
            Text(traceNotice ?? "")
        }
    }

    private func saveFullTrace() {
        guard folder.hasFolder else {
            traceNotice = "Choose a trace folder in Trips first. iOS only lets Vela write to a folder you pick."
            return
        }
        let ok = folder.save(
            store: AppGraph.session.trips, tripID: model.summary.id,
            startedAt: model.summary.startedAt)
        traceNotice = ok
            ? "Saved \(folder.lastSavedFile ?? "the trace") to \(folder.folderName ?? "the folder")."
            : (folder.lastError ?? "The trace could not be saved.")
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
