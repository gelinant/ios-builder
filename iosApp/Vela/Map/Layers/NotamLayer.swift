import Foundation
import MapLibre
import VelaCore

/// The FAA NOTAM layer (A-4) is not installed. The FAA NOTAM Management Service (NMS) needs
/// OAuth2 client credentials issued on request by e-mail, and its API paths and host are only
/// published with those credentials. This build therefore makes no request, draws no NOTAM text
/// and invents no zone. A later authorised integration replaces this file and sets `installed` to
/// true; it changes nothing in `WorldLayers.swift` or `WorldLayerSection.swift`.
///
/// The sheet still offers the generic Keychain field because the catalogue marks `notam` as
/// needing a key. One saved string is not enough for NMS: the service wants a client id and a
/// client secret, and the account is issued by the FAA, not by the user. The field is shown for
/// the shared contract, but this file does not read it and never presents it as access.
final class NotamLayer: WorldLayer {
    static let installed = false
    let id = "notam"
    let title = VelaL10n.text("world_layer_notam")
    let source = "FAA NOTAM data, U.S. Government work, not for operational use; FAA credentials required"
    var isInstalled: Bool { Self.installed }
    var rows: [WorldLayerRow] { [] }

    func refresh(viewport: MapViewport) async -> WorldLayerRefresh? { nil }
    func apply(style: MLNStyle, offline: Bool) {}
}
