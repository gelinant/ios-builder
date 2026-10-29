import SwiftUI
import VelaCore

/// The map's layers sheet: the overlays this build can draw from common data, the PoI categories
/// and icon size, the two Google rasters, and the local style choices.
struct LayersView: View {
    @ObservedObject var model: LayersModel
    @ObservedObject private var threeD = Map3DState.shared
    @ObservedObject private var globe = GlobeState.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    layerToggle("Painted road markings", key: "painted",
                                detail: "Surface, lane, bike, bus, crossing, stop and arrow markings at close zoom.")
                    layerToggle("Speed cameras", key: "speed",
                                detail: "Fixed OSM speed cameras from Overpass.")
                    layerToggle("ALPR cameras", key: "alpr",
                                detail: "Plate readers mapped by DeFlock in OpenStreetMap.")
                    layerToggle("Traffic lights and crossings", key: "controls",
                                detail: "Signals, stop signs, level crossings and speed humps at close zoom.")
                    layerToggle("UK fuel prices", key: "fuel",
                                detail: "Fuel Finder forecourts, only where the UK data covers the view.")
                    layerToggle("Bridge openings", key: "bridges",
                                detail: "Planned and current openings from the Dutch NDW feed.")
                } header: {
                    Text(VelaL10n.text("mapscreen_layers_chip"))
                } footer: {
                    Text(VelaL10n.text("map_each_layer_loads_only_while_it"))
                }

                Section {
                    layerToggle("Live traffic", key: "traffic",
                                detail: "Google's congestion colours and incidents, up to zoom 16.")
                    layerToggle("Satellite", key: "satellite",
                                detail: "Esri World Imagery, with Google's imagery past zoom 19.")
                } header: {
                    Text(VelaL10n.text("map_google_layers"))
                } footer: {
                    Text(VelaL10n.text("map_both_rasters_need_a_network_connection"))
                }

                PaintedPackSection()

                Section {
                    sourceRow("Vela data", source: "vela", id: "poi-source-vela",
                              detail: "The bundled Vela pack: 337 places around Davis, California. No basemap place layer.")
                    sourceRow("Map tiles", source: "tiles", id: "poi-source-tiles",
                              detail: "OpenStreetMap places already in the OpenFreeMap vector tiles.")
                    sourceRow("Both", source: "both", id: "poi-source-both",
                              detail: "The Vela pack where it covers the view, the vector tiles elsewhere.")
                } header: {
                    Text(VelaL10n.text("settings_places_source"))
                } footer: {
                    Text(VelaL10n.text("map_the_vela_pack_covers_davis_only"))
                }

                Section {
                    buttonRow("Show places", isOn: model.showPlaces, id: "poi-places") {
                        model.setShowPlaces(!model.showPlaces)
                    }
                    categoryToggle("Food and drink", key: "food", id: "poi-food")
                    categoryToggle("Fuel and charging", key: "fuel", id: "poi-fuel")
                    categoryToggle("Transit stops", key: "transit", id: "poi-transit")
                    categoryToggle("Parking", key: "parking", id: "poi-parking")
                    categoryToggle("Parks, shops and civic places", key: "other", id: "poi-other")
                    Picker(VelaL10n.text("map_density"), selection: Binding(
                        get: { model.poiDensity },
                        set: { model.setDensity($0) })) {
                        Text(VelaL10n.text("settings_house_numbers_normal")).tag("normal")
                        Text(VelaL10n.text("map_compact")).tag("compact")
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("poi-density")
                    Picker(VelaL10n.text("map_icon_size"), selection: Binding(
                        get: { model.poiIconScale },
                        set: { model.setIconScale($0) })) {
                        Text(VelaL10n.text("settings_poi_size_small")).tag(0.7)
                        Text(VelaL10n.text("settings_poi_size_default")).tag(1.0)
                        Text(VelaL10n.text("settings_poi_size_large")).tag(1.25)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("poi-icon-size")
                } header: {
                    Text(VelaL10n.text("settings_map_places"))
                } footer: {
                    Text(VelaL10n.text("map_compact_raises_the_zoom_at_which"))
                }

                Section {
                    ForEach(MapLook.allCases, id: \.self) { look in
                        buttonRow(look.title, isOn: model.style.look == look,
                                  id: "map-look-\(look.rawValue)") {
                            model.setLook(look)
                        }
                    }
                } header: {
                    Text(VelaL10n.text("settings_map_look"))
                } footer: {
                    Text(VelaL10n.text("map_every_look_is_a_local_style"))
                }

                Section {
                    ForEach(MapAppearance.allCases, id: \.self) { appearance in
                        buttonRow(appearance.title, isOn: model.style.appearance == appearance,
                                  id: "map-appearance-\(appearance.rawValue)") {
                            model.setAppearance(appearance)
                        }
                    }
                } header: {
                    Text(VelaL10n.text("map_map_appearance"))
                }

                Section {
                    ForEach(MapNamesMode.preferenceValues, id: \.self) { mode in
                        buttonRow(mode.title, isOn: model.style.names == mode,
                                  id: "map-names-\(mode.rawValue)") {
                            model.setNames(mode)
                        }
                    }
                } header: {
                    Text(VelaL10n.text("settings_map_names"))
                }

                Section {
                    ForEach(HouseNumberLevel.allCases, id: \.self) { level in
                        buttonRow(level.title, isOn: model.style.houseNumbers == level,
                                  id: "map-house-\(level.rawValue)") {
                            model.setHouseNumbers(level)
                        }
                    }
                } header: {
                    Text(VelaL10n.text("settings_house_numbers"))
                } footer: {
                    Text(VelaL10n.text("map_numbers_fade_in_from_on_the", String(describing: (String(format: "%.1f", model.style.houseNumbers.minZoom)))))
                }

                Section {
                    cameraSourceRow("Automatic", source: "auto", id: "camera-source-auto",
                                    detail: "Live query while online, the pack inside a downloaded region.")
                    cameraSourceRow("Live query", source: "live", id: "camera-source-live",
                                    detail: "Overpass for the current view. Needs a network.")
                    cameraSourceRow("Offline pack", source: "pack", id: "camera-source-pack",
                                    detail: "Bundled plate cameras and the downloaded region pack. No network.")
                    Text(model.packText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("camera-pack-status")
                } header: {
                    Text(VelaL10n.text("map_camera_source"))
                } footer: {
                    Text(VelaL10n.text("map_the_bundled_plate_camera_pack_is", String(describing: (CameraPack.maxAgeDays))))
                }

                Section {
                    layerToggle("Trees and canopy", key: "trees",
                                detail: "OSM trees as canopy discs from zoom 17, plus forest and park polygons from the vector tiles.")
                } header: {
                    Text(VelaL10n.text("map_trees"))
                } footer: {
                    Text(VelaL10n.text("map_isolated_trees_come_from_openstreetmap_through"))
                }

                Section {
                    buttonRow("3D", isOn: threeD.isOn, id: "layer-3d") {
                        Map3DSettings.set(!threeD.isOn)
                    }
                    #if DEBUG
                    Text(threeD.debugLine)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("map-3d-debug")
                    #endif
                } header: {
                    Text(VelaL10n.text("map3d_title"))
                } footer: {
                    Text(VelaL10n.text("map3d_hint"))
                }

                Section {
                    if globe.available {
                        buttonRow(GlobeCopy.title, isOn: globe.projection == .globe, id: "layer-globe") {
                            MapGlobeSettings.set(globe.projection == .globe ? .mercator : .globe)
                        }
                    } else {
                        Text(GlobeCopy.unavailable)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("globe-unavailable")
                    }
                    #if DEBUG
                    Text(globe.debugLine)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("globe-debug")
                    #endif
                } header: {
                    Text(GlobeCopy.title)
                } footer: {
                    Text(GlobeCopy.footer)
                }

                WorldLayerSection()

                Section {
                    Text(model.debugLine)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("layers-sheet-debug")
                }
            }
            .onDisappear { model.republish() }
            .navigationTitle(VelaL10n.text("map_map_layers"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(VelaL10n.text("settings_trip_select_done")) { dismiss() }
                        .accessibilityIdentifier("layers-close")
                }
            }
        }
    }

    /// The two painted-mark sources. The pack is optional and absent by default, so the sheet
    /// always says which source is drawing and names the download before it is requested.
    private struct PaintedPackSection: View {
        @State private var installed = PaintedPack.isInstalled
        @State private var downloading = false
        @State private var failed = false

        var body: some View {
            Section {
                HStack {
                    Text(VelaL10n.text("map_data_source"))
                    Spacer()
                    Text(installed ? VelaL10n.text("map_painted_pack") : VelaL10n.text("map_map_data_live_osm"))
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("painted-pack-status")
                .accessibilityValue(Text(installed ? "pack" : "tiles"))

                if !installed {
                    Button {
                        download()
                    } label: {
                        HStack {
                            Text(VelaL10n.text("map_download_painted_pack_mb", String(describing: (PaintedPack.sizeMB))))
                            Spacer()
                            if downloading { ProgressView() }
                        }
                    }
                    .disabled(downloading)
                    .accessibilityIdentifier("painted-pack-download")
                }
                if failed {
                    Text(VelaL10n.text("map_download_failed_check_the_connection_and"))
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text(VelaL10n.text("map_road_markings_data"))
            } footer: {
                Text(VelaL10n.text("map_the_optional_pack_is_a_california"))
            }
        }

        private func download() {
            downloading = true
            failed = false
            Task {
                do {
                    guard let url = URL(string: VelaLinks.shared.paintedRoads()) else {
                        throw URLError(.badURL)
                    }
                    try await PaintedPack.download(from: url)
                    installed = PaintedPack.isInstalled
                } catch {
                    failed = true
                }
                downloading = false
            }
        }
    }

    private func layerToggle(_ title: String, key: String, detail: String) -> some View {
        let on = model.enabled.contains(key)
        return Button {
            model.setLayer(key, !on)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(statusText(key, detail: detail))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(on ? Color.accentColor : Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("layer-\(key)")
        .accessibilityValue(Text(on ? "on" : "off"))
    }

    private func sourceRow(
        _ title: String, source: String, id: String, detail: String
    ) -> some View {
        let on = model.poiSource == source
        return Button {
            model.setPoiSource(source)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(on ? Color.accentColor : Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityValue(Text(on ? "on" : "off"))
    }

    private func cameraSourceRow(
        _ title: String, source: String, id: String, detail: String
    ) -> some View {
        let on = model.cameraSource == source
        return Button {
            model.setCameraSource(source)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(on ? Color.accentColor : Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityValue(Text(on ? "on" : "off"))
    }

    private func categoryToggle(_ title: String, key: String, id: String) -> some View {
        buttonRow(title, isOn: model.categories.contains(key), id: id) {
            model.setCategory(key, !model.categories.contains(key))
        }
    }

    /// A checkmark row rather than a Toggle: the whole row is the control, so a tap anywhere
    /// flips it, including from XCUITest (a Toggle's accessibility frame covers its label, which
    /// does not toggle in a Form).
    private func buttonRow(
        _ title: String, isOn: Bool, id: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityValue(Text(isOn ? "on" : "off"))
    }

    private func statusText(_ key: String, detail: String) -> String {
        if key == "speed" || key == "alpr", model.cameraSourceMode == .pack {
            return model.packText
        }
        let status = model.snapshot(key)
        switch status.phase {
        case "loading": return "Loading"
        case "ready": return status.count == 1 ? "1 shown" : "\(status.count) shown"
        case "error": return "Failed. Pan the map to retry."
        case "zoom": return "Zoom in to load"
        case "offline": return "Downloaded region: canopy only"
        case "unavailable":
            return key == "fuel" ? "Only available in the UK" : "Only available in the Netherlands"
        case "idle": return "Waiting for the map"
        default: return detail
        }
    }
}
