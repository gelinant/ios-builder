import Foundation
import MapLibre
import VelaCore

/// Socket for the Wikivoyage layer (W-1). WLD-1 installs the host only. W-1 owns this file: it
/// implements `refresh` over Wikidata and Wikivoyage, draws the geolocated articles in `apply`,
/// sets `installed` to true and changes nothing in `WorldLayers.swift` or
/// `WorldLayerSection.swift`.
final class WikiLayer: WorldLayer {
    static let installed = false
    let id = "wiki"
    let title = "Wikivoyage articles"
    let source = "Wikivoyage, CC BY-SA 4.0; Wikidata, CC0 1.0"
    var isInstalled: Bool { Self.installed }
    var rows: [WorldLayerRow] { [] }

    func refresh(viewport: MapViewport) async -> WorldLayerRefresh? { nil }
    func apply(style: MLNStyle, offline: Bool) {}
}
