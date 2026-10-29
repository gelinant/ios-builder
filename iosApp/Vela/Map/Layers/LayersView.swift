import SwiftUI
import VelaCore

/// The map's layers sheet: the overlays this build can draw from common data, the PoI categories
/// and icon size, the two Google rasters, and the local style choices.
struct LayersView: View {
    @ObservedObject var model: LayersModel
    @ObservedObject private var threeD = Map3DState.shared
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
                    Text("Layers")
                } footer: {
                    Text("Each layer loads only while it is on and the map is close enough to read it.")
                }

                Section {
                    layerToggle("Live traffic", key: "traffic",
                                detail: "Google's congestion colours and incidents, up to zoom 16.")
                    layerToggle("Satellite", key: "satellite",
                                detail: "Esri World Imagery, with Google's imagery past zoom 19.")
                } header: {
                    Text("Google layers")
                } footer: {
                    Text("Both rasters need a network connection. They are never enabled over a downloaded region, where the vector map is the offline map.")
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
                    Text("Place icons on the map")
                } footer: {
                    Text("The Vela pack covers Davis only; it draws with no remote request and no Google. The vector tiles are OpenFreeMap, not Google. Outside the pack, Both shows the tile places.")
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
                    Picker("Density", selection: Binding(
                        get: { model.poiDensity },
                        set: { model.setDensity($0) })) {
                        Text("Normal").tag("normal")
                        Text("Compact").tag("compact")
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("poi-density")
                    Picker("Icon size", selection: Binding(
                        get: { model.poiIconScale },
                        set: { model.setIconScale($0) })) {
                        Text("Small").tag(0.7)
                        Text("Default").tag(1.0)
                        Text("Large").tag(1.25)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("poi-icon-size")
                } header: {
                    Text("Places on the map")
                } footer: {
                    Text("Compact raises the zoom at which lower-priority place groups appear. Icon size scales both place families and their labels, as the Android setting does. Basemap labels keep MapLibre's own collision rules.")
                }

                Section {
                    ForEach(MapLook.allCases, id: \.self) { look in
                        buttonRow(look.title, isOn: model.style.look == look,
                                  id: "map-look-\(look.rawValue)") {
                            model.setLook(look)
                        }
                    }
                } header: {
                    Text("Map look")
                } footer: {
                    Text("Every look is a local style built from the bundled Liberty base. The Vela look can be light or dark; the others keep their own palettes.")
                }

                Section {
                    ForEach(MapAppearance.allCases, id: \.self) { appearance in
                        buttonRow(appearance.title, isOn: model.style.appearance == appearance,
                                  id: "map-appearance-\(appearance.rawValue)") {
                            model.setAppearance(appearance)
                        }
                    }
                } header: {
                    Text("Map appearance")
                }

                Section {
                    ForEach(MapNamesMode.preferenceValues, id: \.self) { mode in
                        buttonRow(mode.title, isOn: model.style.names == mode,
                                  id: "map-names-\(mode.rawValue)") {
                            model.setNames(mode)
                        }
                    }
                } header: {
                    Text("Names on the map")
                }

                Section {
                    ForEach(HouseNumberLevel.allCases, id: \.self) { level in
                        buttonRow(level.title, isOn: model.style.houseNumbers == level,
                                  id: "map-house-\(level.rawValue)") {
                            model.setHouseNumbers(level)
                        }
                    }
                } header: {
                    Text("House numbers")
                } footer: {
                    Text("Numbers fade in from \(String(format: "%.1f", model.style.houseNumbers.minZoom)) on the bundled vector data.")
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
                    Text("Camera source")
                } footer: {
                    Text("The bundled plate-camera pack is DeFlock data from OpenStreetMap, dated 2026-07-21. Speed cameras come from the pack written when a region is downloaded. A pack older than \(CameraPack.maxAgeDays) days draws nothing.")
                }

                Section {
                    layerToggle("Trees and canopy", key: "trees",
                                detail: "OSM trees as canopy discs from zoom 17, plus forest and park polygons from the vector tiles.")
                } header: {
                    Text("Trees")
                } footer: {
                    Text("Isolated trees come from OpenStreetMap through Overpass, at most 500 and never below zoom 17. Forest and park fills are already in the vector tiles and need no request. In a downloaded region only the polygons are drawn.")
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
                    Text("3D")
                } footer: {
                    Text("Buildings rise from zoom 16 when the map is tilted past 20 degrees, over shaded relief from AWS Terrain Tiles. Turning 3D on tilts the camera once; a two-finger vertical drag changes the pitch. Off is today's flat map and fetches no elevation tile. Relief needs a network and is not drawn over a downloaded region. MapLibre Native has no sky, atmosphere or terrain mesh here, and the pitch stops at 60 degrees.")
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
            .navigationTitle("Map layers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
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
                    Text("Data source")
                    Spacer()
                    Text(installed ? "Painted pack" : "Map data (live OSM)")
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("painted-pack-status")
                .accessibilityValue(Text(installed ? "pack" : "tiles"))

                if !installed {
                    Button {
                        download()
                    } label: {
                        HStack {
                            Text("Download painted pack (\(PaintedPack.sizeMB) MB)")
                            Spacer()
                            if downloading { ProgressView() }
                        }
                    }
                    .disabled(downloading)
                    .accessibilityIdentifier("painted-pack-download")
                }
                if failed {
                    Text("Download failed. Check the connection and try again.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Road markings data")
            } footer: {
                Text("The optional pack is a California bake of OSM markings; outside California the map draws the live OSM answer for the view. Nothing is invented: a road without lane, cycleway, busway or one-way tags stays bare. OSM covers western Europe and North America best; elsewhere most roads carry no marking data.")
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
