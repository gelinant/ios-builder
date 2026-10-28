import Foundation
import MapLibre
import VelaCore

/// Socket for the energy layer (A-3). WLD-1 installs the host only. A-3 owns this file: it
/// implements `refresh` over NESO and the optional Electricity Maps and Cloudflare Radar sources,
/// draws in `apply`, sets `installed` to true and changes nothing in `WorldLayers.swift` or
/// `WorldLayerSection.swift`.
final class EnergyLayer: WorldLayer {
    static let installed = false
    let id = "energy"
    let title = "Energy and outages"
    let source = "NESO Carbon Intensity, CC BY 4.0; Electricity Maps key; Cloudflare Radar token"
    var isInstalled: Bool { Self.installed }
    var rows: [WorldLayerRow] { [] }

    func refresh(viewport: MapViewport) async -> WorldLayerRefresh? { nil }
    func apply(style: MLNStyle, offline: Bool) {}
}
