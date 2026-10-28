import Foundation
import MapLibre
import VelaCore

/// Socket for the satellite layer (G-3). WLD-1 installs the host only. G-3 owns this file: it
/// implements `refresh` over CelesTrak, propagates the cached TLEs, draws in `apply`, sets
/// `installed` to true and changes nothing in `WorldLayers.swift` or `WorldLayerSection.swift`.
final class SatelliteLayer: WorldLayer {
    static let installed = false
    let id = "satellite"
    let title = "Satellites"
    let source = "CelesTrak TLE, Dr T.S. Kelso"
    var isInstalled: Bool { Self.installed }
    var rows: [WorldLayerRow] { [] }

    func refresh(viewport: MapViewport) async -> WorldLayerRefresh? { nil }
    func apply(style: MLNStyle, offline: Bool) {}
}
