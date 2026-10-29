import SwiftUI
import VelaCore

/// The framed-area picker (OFF-AREA): the map dimmed outside a fixed frame, a hint above it and a
/// card below with the live estimate, what the download includes and the confirmation. The frame's
/// insets match the Kotlin estimator (`OfflineArea`), so the rectangle the user sees is the one the
/// store plans for. Pan and pinch reach the map; only the card takes taps.
struct OfflineAreaOverlay: View {
    @ObservedObject var model: OfflineModel

    private let left = 0.07
    private let right = 0.07
    private let top = 0.18
    private let bottom = 0.34

    var body: some View {
        GeometryReader { geometry in
            let frame = CGRect(
                x: geometry.size.width * left,
                y: geometry.size.height * top,
                width: geometry.size.width * (1 - left - right),
                height: geometry.size.height * (1 - top - bottom))
            ZStack(alignment: .top) {
                AreaScrim(frame: frame, size: geometry.size, corner: 16)
                    .allowsHitTesting(false)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(VelaL10n.text("offline_area_frame"))
                    .accessibilityIdentifier("offline-area-frame")
                Text(VelaL10n.text("offline_pan_and_pinch_to_choose_the"))
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .padding(.top, 8)
                    .accessibilityIdentifier("offline-area-hint")
                VStack {
                    Spacer()
                    card
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                }
            }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(VelaL10n.text("offline_download_this_area"))
                    .font(.headline)
                Spacer()
                Button {
                    model.cancelAreaPick()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel(VelaL10n.text("offline_cancel_area_picker"))
                .accessibilityIdentifier("area-close")
            }

            estimate

            if let plan = model.areaPlan {
                Text(plan.regionName.isEmpty
                     ? VelaL10n.text("offline_no_offline_map_covers_this_frame")
                     : VelaL10n.text("offline_whole_region", String(describing: (plan.regionName))))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("area-region")
                Text(VelaL10n.text("offline_free_space", String(describing: (Self.bytes(plan.freeBytes)))))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("area-free-space")
                if plan.reasonKey == "no_space" {
                    Text(VelaL10n.text("offline_not_enough_free_space_needed_available", String(describing: (Self.megabytes(plan.neededBytes))), String(describing: (Self.bytes(plan.freeBytes)))))
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("area-refusal")
                } else if plan.reasonKey == "installed" {
                    Text(VelaL10n.text("offline_already_downloaded_turn_on_cameras_or"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("area-installed")
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: $model.areaPlaces) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(VelaL10n.text("settings_places"))
                        Text(VelaL10n.text("offline_place_pack_and_place_search_data"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("area-include-places")
                Toggle(isOn: $model.areaCameras) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(VelaL10n.text("settings_cameras_group"))
                        Text(VelaL10n.text("offline_speed_and_plate_cameras_from_openstreetmap"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("area-include-cameras")
                Toggle(isOn: $model.areaAddresses) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(VelaL10n.text("offline_addresses"))
                        Text(VelaL10n.text("offline_street_addresses_around_the_frame_for"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("area-include-addresses")
            }

            Text(VelaL10n.text("offline_includes_the_map_places_and_addresses"))
                .font(.caption)
                .accessibilityIdentifier("area-routing-note")

            HStack {
                Spacer()
                Button(VelaL10n.text("settings_cancel")) { model.cancelAreaPick() }
                    .accessibilityIdentifier("area-cancel")
                Button(VelaL10n.text("settings_download")) { model.confirmArea() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.areaPlan?.canDownload != true)
                    .accessibilityIdentifier("area-download")
            }

            #if DEBUG
            Text(model.areaDebugLine)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("area-debug")
            #endif
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
    }

    @ViewBuilder private var estimate: some View {
        if model.areaEstimating || model.areaPlan == nil {
            Text(VelaL10n.text("offline_estimating"))
                .font(.title3.weight(.semibold))
                .accessibilityIdentifier("area-estimate")
        } else if let plan = model.areaPlan {
            if plan.reasonKey == "no_region" {
                Text(VelaL10n.text("offline_no_offline_map_covers_this_frame"))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("area-estimate")
            } else if plan.reasonKey == "installed" {
                Text(VelaL10n.text("offline_already_downloaded"))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("area-estimate")
            } else {
                Text(VelaL10n.text("offline_estimated_download", String(describing: (Self.megabytes(plan.neededBytes)))))
                    .font(.title3.weight(.semibold))
                    .accessibilityIdentifier("area-estimate")
            }
        }
    }

    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    static func megabytes(_ bytes: Int64) -> String {
        let mb = max(1, Int((bytes + 1024 * 1024 - 1) / (1024 * 1024)))
        if mb >= 1024 { return String(format: "%.1f GB", Double(mb) / 1024) }
        return "\(mb) MB"
    }
}

/// The dimmed outside plus the bright frame border. One path with the even-odd rule so the hole is
/// a hole; the map stays visible and reachable through it.
private struct AreaScrim: View {
    let frame: CGRect
    let size: CGSize
    let corner: CGFloat

    var body: some View {
        ZStack {
            Path { path in
                path.addRect(CGRect(origin: .zero, size: size))
                path.addRoundedRect(in: frame, cornerSize: CGSize(width: corner, height: corner))
            }
            .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))
            Path { path in
                path.addRoundedRect(in: frame, cornerSize: CGSize(width: corner, height: corner))
            }
            .stroke(Color.accentColor, lineWidth: 3)
        }
    }
}

/// The compact progress card over the map after confirmation. It keeps reading the store's state,
/// so closing the sheet, reopening it or waiting on the map all show the same download.
struct OfflineAreaProgressCard: View {
    @ObservedObject var model: OfflineModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer()
                Button {
                    model.hideAreaReport()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel(VelaL10n.text("offline_hide_area_download"))
                .accessibilityIdentifier("area-hide")
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("area-progress-stage")
            if model.areaDownloading {
                ProgressView(value: Double(model.progress), total: 100) {
                    Text("\(model.progress)%")
                        .font(.caption)
                }
                .accessibilityIdentifier("area-progress")
                HStack {
                    Spacer()
                    Button(VelaL10n.text("settings_cancel"), role: .cancel) { model.cancel() }
                        .accessibilityIdentifier("area-cancel-download")
                }
            }
            if !model.areaDownloading && (model.areaCameras || model.areaAddresses) {
                Text(VelaL10n.text("offline_camera_data_address_data", String(describing: (rows(model.areaCameraRows))), String(describing: (rows(model.areaAddressRows)))))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("area-data")
            }
            #if DEBUG
            Text(model.areaDebugLine)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("area-progress-debug")
            #endif
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
        .accessibilityIdentifier("area-progress-card")
    }

    private var title: String {
        if model.errorKey == "no_space" { return "Not enough free space" }
        if model.errorKey == "no_region" { return "No offline map covers this area" }
        if model.errorKey == "download_failed" { return "Area download failed" }
        if model.areaDownloading { return "Downloading area" }
        if model.areaReady { return "Area ready" }
        return "Area download"
    }

    private var detail: String {
        if let error = model.errorKey {
            if error == "no_space" || error == "no_region" { return "Nothing was installed." }
            // A failed piece is not a successful area: say how far it got and that the rest is kept.
            return "\(model.completedPieces) of \(model.pieceCount) pieces are complete and will be reused."
        }
        if model.areaDownloading {
            return "\(stageLabel) \(model.completedPieces) of \(model.pieceCount) pieces"
        }
        return "The map is saved. Offline routing is not included."
    }

    private var stageLabel: String {
        switch model.areaDataStage {
        case "cameras": return "Camera data"
        case "addresses": return "Address data"
        default: break
        }
        switch model.stage {
        case "pack": return "Place pack"
        case "places": return "Places archive"
        case "glyphs": return "Map fonts"
        case "basemap": return "Offline basemap"
        default: return "Preparing"
        }
    }

    private func rows(_ count: Int) -> String {
        if count < 0 { return "no answer" }
        return "\(count) rows"
    }
}
