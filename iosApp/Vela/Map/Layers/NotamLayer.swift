import Foundation
import MapLibre
import VelaCore

/// Socket for the NOTAM layer (A-4). WLD-1 installs the host only. A-4 owns this file: it
/// implements `refresh` once FAA NMS access is granted, draws text and optional zones in `apply`,
/// sets `installed` to true and changes nothing in `WorldLayers.swift` or
/// `WorldLayerSection.swift`. This layer needs a key, so the sheet offers its Keychain field.
final class NotamLayer: WorldLayer {
    static let installed = false
    let id = "notam"
    let title = VelaL10n.text("world_layer_notam")
    let source = "FAA NOTAM, information only, not for operational use"
    var isInstalled: Bool { Self.installed }
    var rows: [WorldLayerRow] { [] }

    func refresh(viewport: MapViewport) async -> WorldLayerRefresh? { nil }
    func apply(style: MLNStyle, offline: Bool) {}
}
