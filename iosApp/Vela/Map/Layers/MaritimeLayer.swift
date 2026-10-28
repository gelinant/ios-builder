import Foundation
import MapLibre
import VelaCore

/// Socket for the maritime layer (A-2). WLD-1 installs the host only. A-2 owns this file: it
/// implements `refresh` over Digitraffic and AISHub, adds the UKMTO list, draws in `apply`, sets
/// `installed` to true and changes nothing in `WorldLayers.swift` or `WorldLayerSection.swift`.
final class MaritimeLayer: WorldLayer {
    static let installed = false
    let id = "maritime"
    let title = "Ships"
    let source = "Digitraffic AIS, CC BY 4.0; AISHub with a member key"
    var isInstalled: Bool { Self.installed }
    var rows: [WorldLayerRow] { [] }

    func refresh(viewport: MapViewport) async -> WorldLayerRefresh? { nil }
    func apply(style: MLNStyle, offline: Bool) {}
}
