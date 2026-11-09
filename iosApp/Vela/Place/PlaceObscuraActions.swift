import SafariServices
import SwiftUI
import UIKit
import VelaCore

/// The two Atlas Obscura rows in the place sheet. They are link only: the address comes from the
/// shared `ObscuraLinks`, the site opens in the app's Safari sheet, and Vela reads nothing back,
/// stores nothing and never fetches an Atlas Obscura image. See docs/ios/PLACE.md and the
/// `atlas-obscura` notice in Settings/Notices.json.
struct PlaceObscuraSection: View {
    let card: PlaceCard

    /// The nearby search needs a real point. The shared builder refuses a non-finite coordinate,
    /// so the row disappears instead of opening an untrustworthy address.
    private var atlasURL: URL? {
        guard let raw = ObscuraLinks.shared.nearbyUrl(lat: card.latitude, lng: card.longitude)
        else { return nil }
        return URL(string: raw)
    }

    /// Gastro Obscura has no position filter, so its URL carries no point. The row still requires
    /// the place to have coordinates, and only appears for a food or drink category.
    private var gastroURL: URL? {
        guard atlasURL != nil,
              let raw = ObscuraLinks.shared.gastroUrl(category: card.category)
        else { return nil }
        return URL(string: raw)
    }

    var body: some View {
        if atlasURL != nil || gastroURL != nil {
            VStack(alignment: .leading, spacing: 8) {
                Text(VelaL10n.text("place_obscura_title"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                if let url = atlasURL {
                    row(
                        title: VelaL10n.text("place_obscura_atlas"),
                        note: VelaL10n.text("place_obscura_atlas_note"),
                        identifier: "place-obscura-atlas",
                        url: url)
                }
                if let url = gastroURL {
                    row(
                        title: VelaL10n.text("place_obscura_gastro"),
                        note: VelaL10n.text("place_obscura_gastro_note"),
                        identifier: "place-obscura-gastro",
                        url: url)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("place-obscura-section")
        }
    }

    private func row(title: String, note: String, identifier: String, url: URL) -> some View {
        Button {
            open(url)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "safari")
                    .font(.footnote)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .multilineTextAlignment(.leading)
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right.square")
                    .font(.caption)
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityValue(debugURL(url))
    }

    /// The DEBUG mirror a UI scenario reads off the row, because the Safari sheet is a remote
    /// process whose address XCUITest cannot query. Release builds expose an empty value.
    private func debugURL(_ url: URL) -> String {
        #if DEBUG
        url.absoluteString
        #else
        ""
        #endif
    }

    private func open(_ url: URL) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
            let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        guard !(top is SFSafariViewController) else { return }
        top.present(SFSafariViewController(url: url), animated: true)
    }
}
