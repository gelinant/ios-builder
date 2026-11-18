import Foundation
import VelaCore

/// What the iOS share sheet receives for a place or a route: a subject for Mail, the text that
/// names the place or trip, and the link item when one exists. The text and links are built by
/// the shared `ShareLinks`, so Android and iOS share the same rules (L53, L115).
struct VelaSharePayload: Identifiable {
    let id = UUID()
    let subject: String
    let text: String
    let link: String?

    /// Text first, then the link, so a messaging app that only accepts one item still gets the
    /// part that names the place.
    var items: [Any] {
        if let link, let url = URL(string: link) { return [text, url] }
        return [text]
    }

    /// The DEBUG mirror a UI test reads off the share button, since the activity sheet itself is
    /// a remote process whose contents XCUITest cannot query.
    var debugText: String {
        [subject, text, link ?? ""].filter { !$0.isEmpty }.joined(separator: " | ")
    }
}

/// A place share: canonical Google link when Google is on, else the place's OpenStreetMap or
/// Photon link, else Android's keyless pin in the text. The name and address are always in it.
enum PlaceShare {
    static func payload(
        name: String,
        address: String?,
        latitude: Double,
        longitude: Double,
        featureId: String?,
        sourceId: String?,
        google: Bool = PrivacySettings.googleAllowed
    ) -> VelaSharePayload {
        let content = ShareLinks.shared.placeShare(
            name: name,
            address: address,
            latitude: latitude,
            longitude: longitude,
            featureId: featureId,
            sourceId: sourceId,
            google: google)
        return VelaSharePayload(subject: content.subject, text: content.text, link: content.link)
    }
}

/// A route share. The ETA is only passed when the selected route really has one, so a route
/// without a duration never shows an invented travel time.
enum RouteShare {
    static func payload(_ model: RouteModel, google: Bool = PrivacySettings.googleAllowed) -> VelaSharePayload {
        let here = model.fromMapCenter ? "the map's center" : "your location"
        let start = model.originName ?? here
        let origin = model.reversed ? model.destinationName : start
        let destination = model.reversed ? start : model.destinationName
        let seconds = model.mode == .transit ? model.activeTransit?.seconds : model.activeChoice?.seconds
        let eta = seconds.flatMap { $0 > 0 ? RouteFormat.duration($0) : nil }
        let content = ShareLinks.shared.routeShare(
            origin: origin,
            destination: destination,
            waypoints: model.waypoints.map(\.name),
            modeName: model.mode.rawValue,
            etaText: eta,
            google: google)
        return VelaSharePayload(subject: content.subject, text: content.text, link: content.link)
    }
}
