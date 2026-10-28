import Foundation
import MapLibre
import VelaCore

/// Socket for the aviation layer (A-1). WLD-1 installs the host only. A-1 owns this file: it
/// implements `refresh` over adsb.lol, draws in `apply`, sets `installed` to true and changes
/// nothing in `WorldLayers.swift` or `WorldLayerSection.swift`.
final class AviationLayer: WorldLayer {
    static let installed = false
    let id = "aviation"
    let title = "Aircraft"
    let source = "adsb.lol, ODbL 1.0"
    var isInstalled: Bool { Self.installed }
    var rows: [WorldLayerRow] { [] }

    func refresh(viewport: MapViewport) async -> WorldLayerRefresh? { nil }
    func apply(style: MLNStyle, offline: Bool) {}
}
