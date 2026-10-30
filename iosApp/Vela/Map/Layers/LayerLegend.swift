import Foundation
import SwiftUI
import UIKit
import VelaCore

/// LAYER-INFO: one contract per layer, used both by the map symbol and by the info surface (card
/// or sheet row). A field list is declared once; the map label and the card lines are rendered
/// from the same values with the same terms and units, so the two cannot drift. The legend reads
/// the same contract for its title, colour, unit, source and data age.
///
/// Freshness follows one rule everywhere: live data shows a relative age ("2 min ago"), a
/// schedule shows an absolute clock, and a layer with no timestamp says "No data" instead of
/// showing a stale value.

enum LayerFreshness: Equatable {
    case live
    case schedule
}

/// One data field carried by a layer. `unit` is a symbol or word shown after the value in both
/// places; an empty unit means the value is a name or an index that reads on its own.
struct LayerInfoField: Equatable {
    let id: String
    let unit: String
}

/// One rendered value, always paired with the field it belongs to.
struct LayerInfoValue: Equatable {
    let id: String
    let text: String
    let unit: String
}

struct LayerInfoContract {
    let id: String
    let title: String
    let symbol: String
    let color: Color
    let unit: String
    let source: String
    let freshness: LayerFreshness
    let fields: [LayerInfoField]

    /// The fields the symbol draws, derived from the one list.
    var mapFieldIDs: [String] { fields.map(\.id) }
    /// The fields the info surface shows, derived from the same list.
    var infoFieldIDs: [String] { fields.map(\.id) }

    /// The map symbol label: every field, in declared order, with its unit.
    func mapLabel(_ values: [LayerInfoValue]) -> String {
        Self.join(values, fields: fields)
    }

    /// One line per field, with the same values, terms and units as the map label.
    func infoLines(_ values: [LayerInfoValue]) -> [(id: String, text: String)] {
        fields.compactMap { field in
            guard let value = values.first(where: { $0.id == field.id }) else { return nil }
            return (field.id, Self.term(value))
        }
    }

    /// A single joined line, for a symbol or a compact row.
    static func join(_ values: [LayerInfoValue], fields: [LayerInfoField]) -> String {
        fields.compactMap { field in
            values.first(where: { $0.id == field.id }).map(term)
        }.joined(separator: " · ")
    }

    static func term(_ value: LayerInfoValue) -> String {
        value.unit.isEmpty ? value.text : "\(value.text) \(value.unit)"
    }

    func value(_ id: String, _ text: String) -> LayerInfoValue {
        let unit = fields.first(where: { $0.id == id })?.unit ?? ""
        return LayerInfoValue(id: id, text: text, unit: unit)
    }
}

/// The nine layers named by the parity contract, plus the other overlays the sheet can turn on.
/// Every id matches either a `LayersModel` switch, a `WorldLayersHub` layer id, or both.
enum LayerInfoID: String, CaseIterable {
    case aviation, maritime, energy, radar, satellite, wiki
    case cameras, transit, traffic
    case satelliteImagery = "satellite-imagery"
    case painted, controls, fuel, bridges, trees

    /// The nine layers the user asked to keep in step.
    static let parity: [LayerInfoID] = [
        .aviation, .maritime, .energy, .radar, .satellite, .wiki,
        .cameras, .transit, .traffic,
    ]
}

enum LayerInfoCatalog {
    private static func color(_ hex: UInt32) -> Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }

    static func contract(_ id: LayerInfoID) -> LayerInfoContract {
        switch id {
        case .aviation:
            return LayerInfoContract(
                id: id.rawValue,
                title: VelaL10n.text("world_layer_aircraft"),
                symbol: "airplane",
                color: color(0x1A73E8),
                unit: "ft",
                source: "adsb.lol, ODbL 1.0",
                freshness: .live,
                fields: [
                    LayerInfoField(id: "ident", unit: ""),
                    LayerInfoField(id: "altitude", unit: "ft"),
                    LayerInfoField(id: "heading", unit: "deg"),
                    LayerInfoField(id: "speed", unit: "kt"),
                ])
        case .maritime:
            return LayerInfoContract(
                id: id.rawValue,
                title: VelaL10n.text("world_layer_ships"),
                symbol: "ferry",
                color: color(0x216BAD),
                unit: "kn",
                source: "Digitraffic AIS, CC BY 4.0; AISHub with a member key",
                freshness: .live,
                fields: [
                    LayerInfoField(id: "name", unit: ""),
                    LayerInfoField(id: "type", unit: ""),
                    LayerInfoField(id: "speed", unit: "kn"),
                    LayerInfoField(id: "course", unit: "deg"),
                    LayerInfoField(id: "mmsi", unit: ""),
                ])
        case .energy:
            return LayerInfoContract(
                id: id.rawValue,
                title: VelaL10n.text("world_layer_energy"),
                symbol: "bolt.fill",
                color: color(0xF9A825),
                unit: "gCO2/kWh",
                source: "NESO Carbon Intensity, CC BY 4.0",
                freshness: .live,
                fields: [
                    LayerInfoField(id: "region", unit: ""),
                    LayerInfoField(id: "index", unit: ""),
                    LayerInfoField(id: "forecast", unit: "gCO2/kWh"),
                ])
        case .radar:
            return LayerInfoContract(
                id: id.rawValue,
                title: VelaL10n.text("layer_radar"),
                symbol: "antenna.radiowaves.left.and.right",
                color: color(0xC62828),
                unit: "min",
                source: "Cloudflare Radar, CC BY-NC 4.0",
                freshness: .live,
                fields: [
                    LayerInfoField(id: "kind", unit: ""),
                    LayerInfoField(id: "location", unit: ""),
                    LayerInfoField(id: "age", unit: "min"),
                ])
        case .satellite:
            return LayerInfoContract(
                id: id.rawValue,
                title: VelaL10n.text("world_layer_satellites"),
                symbol: "satellite",
                color: color(0x6A1B9A),
                unit: "km",
                source: "CelesTrak TLE, propagated with SGP4",
                freshness: .live,
                fields: [
                    LayerInfoField(id: "name", unit: ""),
                    LayerInfoField(id: "altitude", unit: "km"),
                    LayerInfoField(id: "velocity", unit: "km/s"),
                ])
        case .wiki:
            return LayerInfoContract(
                id: id.rawValue,
                title: VelaL10n.text("world_layer_wikivoyage"),
                symbol: "book",
                color: color(0x216B8C),
                unit: "",
                source: "Wikivoyage, CC BY-SA 4.0; Wikidata, CC0 1.0",
                freshness: .live,
                fields: [LayerInfoField(id: "title", unit: "")])
        case .cameras:
            return LayerInfoContract(
                id: id.rawValue,
                title: VelaL10n.text("layer_cameras"),
                symbol: "camera.fill",
                color: color(0xD93025),
                unit: "mph",
                source: "OpenStreetMap via Overpass; DeFlock for plate readers",
                freshness: .live,
                fields: [])
        case .transit:
            return LayerInfoContract(
                id: id.rawValue,
                title: VelaL10n.text("layer_transit_vehicles"),
                symbol: "bus.fill",
                color: color(0x188038),
                unit: "min",
                source: "Transitous, CC BY 4.0",
                freshness: .live,
                fields: [])
        case .traffic:
            return LayerInfoContract(
                id: id.rawValue,
                title: VelaL10n.text("map_layers_traffic"),
                symbol: "car.fill",
                color: color(0xE8710A),
                unit: "min",
                source: "Google traffic",
                freshness: .live,
                fields: [])
        case .satelliteImagery:
            return LayerInfoContract(
                id: id.rawValue,
                title: VelaL10n.text("map_layers_satellite"),
                symbol: "globe.americas.fill",
                color: color(0x5F6368),
                unit: "",
                source: "Esri World Imagery; Google past zoom 19",
                freshness: .live,
                fields: [])
        case .painted:
            return LayerInfoContract(
                id: id.rawValue,
                title: VelaL10n.text("layer_painted_marks"),
                symbol: "road.lanes",
                color: color(0x5F6368),
                unit: "",
                source: "OpenStreetMap via Overpass; optional PMTiles pack",
                freshness: .live,
                fields: [])
        case .controls:
            return LayerInfoContract(
                id: id.rawValue,
                title: VelaL10n.text("layer_traffic_controls"),
                symbol: "exclamationmark.triangle.fill",
                color: color(0xB06000),
                unit: "",
                source: "OpenStreetMap via Overpass",
                freshness: .live,
                fields: [])
        case .fuel:
            return LayerInfoContract(
                id: id.rawValue,
                title: VelaL10n.text("layer_fuel_prices"),
                symbol: "fuelpump.fill",
                color: color(0x188038),
                unit: "p",
                source: "UK Fuel Finder, Open Government Licence v3.0",
                freshness: .live,
                fields: [])
        case .bridges:
            return LayerInfoContract(
                id: id.rawValue,
                title: VelaL10n.text("layer_bridge_openings"),
                symbol: "water.waves",
                color: color(0x1565C0),
                unit: "min",
                source: "NDW bridge openings",
                freshness: .live,
                fields: [])
        case .trees:
            return LayerInfoContract(
                id: id.rawValue,
                title: VelaL10n.text("map_trees"),
                symbol: "tree.fill",
                color: color(0x2E7D32),
                unit: "m",
                source: "OpenStreetMap via Overpass; vector tiles",
                freshness: .live,
                fields: [])
        }
    }
}

/// The parity contract as a pure check: a layer whose map fields and info fields differ, whose
/// field ids repeat, or whose field has no stable id fails. `LayerInfoParityTests` runs one test
/// per layer; the overlay runs the same check in Debug and reports `legend_parity`.
enum LayerInfoParity {
    static func failures() -> [String] {
        LayerInfoID.allCases.flatMap { id -> [String] in
            let contract = LayerInfoCatalog.contract(id)
            var out: [String] = []
            if contract.mapFieldIDs != contract.infoFieldIDs {
                out.append("\(id.rawValue): map \(contract.mapFieldIDs) != info \(contract.infoFieldIDs)")
            }
            if Set(contract.fields.map(\.id)).count != contract.fields.count {
                out.append("\(id.rawValue): duplicate field id")
            }
            if contract.fields.contains(where: { $0.id.isEmpty }) {
                out.append("\(id.rawValue): empty field id")
            }
            return out
        }
    }

    /// Renders a fixture value set through both paths and checks every field id appears on both
    /// sides with the same term and unit.
    static func renderFailures() -> [String] {
        LayerInfoID.allCases.flatMap { id -> [String] in
            let contract = LayerInfoCatalog.contract(id)
            let values = contract.fields.map {
                LayerInfoValue(id: $0.id, text: "v-\($0.id)", unit: $0.unit)
            }
            let label = contract.mapLabel(values)
            let lines = contract.infoLines(values)
            var out: [String] = []
            if lines.count != contract.fields.count {
                out.append("\(id.rawValue): \(lines.count) info lines for \(contract.fields.count) fields")
            }
            for line in lines where !label.contains(line.text) {
                out.append("\(id.rawValue): map label misses \(line.id)")
            }
            return out
        }
    }
}

/// The timestamp rule. Live data is relative, a schedule is an absolute clock, and a missing
/// timestamp never borrows an old value.
enum LayerAge {
    static func text(updatedAt: Date?, freshness: LayerFreshness, now: Date = Date()) -> String {
        guard let updatedAt else { return VelaL10n.text("layer_no_data") }
        switch freshness {
        case .schedule:
            return updatedAt.formatted(date: .omitted, time: .shortened)
        case .live:
            let seconds = max(0, Int(now.timeIntervalSince(updatedAt)))
            if seconds < 60 { return VelaL10n.text("layer_age_now") }
            if seconds < 3_600 { return VelaL10n.text("layer_age_minutes", seconds / 60) }
            return VelaL10n.text("layer_age_hours", seconds / 3_600)
        }
    }
}

struct LayerLegendEntry: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let color: Color
    let unit: String
    let source: String
    let age: String

    var spoken: String {
        [title, unit.isEmpty ? nil : unit, source, age]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

/// Resolves the active layers and their data age from the two existing owners. No request is
/// made here: the legend reflects switches, timestamps and states already in memory.
enum LayerLegendEntries {
    static func make(
        model: LayersModel,
        hub: WorldLayersHub = .shared,
        now: Date = Date()
    ) -> [LayerLegendEntry] {
        var out: [LayerLegendEntry] = []
        func add(_ id: LayerInfoID, updatedAt: Date?) {
            let contract = LayerInfoCatalog.contract(id)
            out.append(LayerLegendEntry(
                id: id.rawValue,
                title: contract.title,
                symbol: contract.symbol,
                color: contract.color,
                unit: contract.unit,
                source: contract.source,
                age: LayerAge.text(updatedAt: updatedAt, freshness: contract.freshness, now: now)))
        }

        let enabled = model.enabled
        if enabled.contains("painted") { add(.painted, updatedAt: model.updatedAt("painted")) }
        if enabled.contains("speed") || enabled.contains("alpr") {
            let stamps = ["speed", "alpr"].compactMap { model.updatedAt($0) }
            add(.cameras, updatedAt: stamps.max())
        }
        if enabled.contains("controls") { add(.controls, updatedAt: model.updatedAt("controls")) }
        if enabled.contains("fuel") { add(.fuel, updatedAt: model.updatedAt("fuel")) }
        if enabled.contains("bridges") { add(.bridges, updatedAt: model.updatedAt("bridges")) }
        if enabled.contains("trees") { add(.trees, updatedAt: model.updatedAt("trees")) }
        if enabled.contains("traffic") { add(.traffic, updatedAt: model.enabledSince("traffic")) }
        if enabled.contains("satellite") {
            add(.satelliteImagery, updatedAt: model.enabledSince("satellite"))
        }
        if model.showTransit { add(.transit, updatedAt: model.enabledSince("transit")) }

        for layer in hub.layers where hub.isOn(layer.id) {
            guard let id = LayerInfoID(rawValue: layer.id) else { continue }
            let state = hub.state(layer.id)
            let stamp = state.flatMap { $0.updatedAtMs > 0
                ? Date(timeIntervalSince1970: Double($0.updatedAtMs) / 1_000) : nil }
            add(id, updatedAt: stamp)
        }
        // Radar events are part of the energy layer; the legend names it only when its host is
        // on and the state carries a timestamp, so a keyless Radar is never shown as live.
        return out.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
}

/// The overlay itself. A compact card over the map, anchored top-leading so it never covers the
/// attribution at the bottom or the map controls on the right. One VoiceOver element per layer.
struct LayerLegendView: View {
    @ObservedObject var model: LayersModel
    @ObservedObject var hub: WorldLayersHub
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [LayerLegendEntry] = []

    private var parity: Int { LayerInfoParity.failures().isEmpty
        && LayerInfoParity.renderFailures().isEmpty ? 1 : 0 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }
            VStack(alignment: .leading, spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(entries) { entry in
                            row(entry)
                        }
                        Text("legend_layers=\(entries.count) legend_parity=\(parity)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("layer-legend-debug")
                    }
                    .padding(12)
                }
                .frame(maxHeight: 380)
            }
            .frame(maxWidth: 330)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1))
            .shadow(radius: 12)
            .padding(.leading, 16)
            .padding(.top, 96)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("layer-legend")
        .preferredColorScheme(forcedDark ? .dark : nil)
        .onAppear { reload() }
    }

    private var header: some View {
        HStack {
            Text(VelaL10n.text("layer_legend_title"))
                .font(.headline)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("layer-legend-close")
            .accessibilityLabel(Text(VelaL10n.text("layer_legend_close")))
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private func row(_ entry: LayerLegendEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: entry.symbol)
                .font(.footnote)
                .foregroundStyle(entry.color)
                .frame(width: 20, height: 20)
                .background(entry.color.opacity(0.16), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title)
                    .font(.caption.weight(.semibold))
                Text(entry.unit.isEmpty
                     ? entry.source
                     : "\(entry.unit) · \(entry.source)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(entry.age)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(entry.spoken))
        .accessibilityIdentifier("layer-legend-row-\(entry.id)")
    }

    private func reload() {
        entries = LayerLegendEntries.make(model: model, hub: hub)
    }

    /// Debug-only test hook: `-VelaForceDark YES` renders the legend in dark mode for the second
    /// screenshot without changing the whole app theme.
    private var forcedDark: Bool {
        ProcessInfo.processInfo.arguments.contains("-VelaForceDark")
    }
}

/// Presents the legend over the map from the layers sheet. The sheet dismisses first, so the
/// capture shows the legend against the map, and the card stays clear of attribution and controls.
enum LayerLegendPresenter {
    static func present(model: LayersModel) {
        guard let top = topController() else { return }
        let host = UIHostingController(
            rootView: LayerLegendView(model: model, hub: .shared))
        host.modalPresentationStyle = .overFullScreen
        host.view.backgroundColor = .clear
        top.present(host, animated: false)
    }

    private static func topController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: { $0.isKeyWindow })
            ?? scenes.flatMap(\.windows).first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
