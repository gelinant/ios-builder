import MapLibre
import UIKit

/// One place from the bundled Vela pack. [group] is the sheet category (`food`, `fuel`, `transit`,
/// `parking` or `other`), so the same five switches filter the pack and the vector tiles.
struct VelaPoi: Equatable {
    let name: String
    let group: String
    let lat: Double
    let lng: Double
}

/// The Vela POI pack shipped in the app bundle. It is derived from the OpenMapTiles vector-tile
/// fixture already committed at `core/src/test/resources/tiles/davis-14-2651-6288.pbf` (Davis,
/// California) by `scripts/ios/gen-poi-pack.py`; its named 337 OSM places are the only real place
/// data the repository contains. Android draws its Overture archive instead, which is downloaded
/// per region and has no bundled equivalent here. The pack is read once and never requested.
enum VelaPoiPack {
    static let resourceName = "poi-davis"
    static let sourcePath = "core/src/test/resources/tiles/davis-14-2651-6288.pbf"
    static let groups = ["food", "fuel", "transit", "parking", "other"]

    static let all: [VelaPoi] = load()

    static var count: Int { all.count }

    /// Keeps the places of the categories the sheet still allows. An empty [allowed] with a filter
    /// on draws nothing; callers pass nil when every category is on.
    static func filtered(allowed: [String]?) -> [VelaPoi] {
        guard let allowed else { return all }
        let keep = Set(allowed)
        return all.filter { keep.contains($0.group) }
    }

    private struct Payload: Decodable {
        let source: String
        let count: Int
        let places: [Place]

        struct Place: Decodable {
            let name: String
            let group: String
            let lat: Double
            let lng: Double
        }
    }

    private final class BundleToken {}

    private static func load() -> [VelaPoi] {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return []
        }
        return payload.places
            .filter { groups.contains($0.group) }
            .map { VelaPoi(name: $0.name, group: $0.group, lat: $0.lat, lng: $0.lng) }
    }

    private static var bundle: Bundle {
        let main = Bundle.main
        if main.url(forResource: resourceName, withExtension: "json") != nil { return main }
        return Bundle(for: BundleToken.self)
    }
}

/// The category markers the Vela pack draws. Android paints a colored circle with a white Material
/// icon at runtime (`PoiIcons`); iOS does the same with an SF Symbol, so an icon size change is a
/// style image scale and nothing is added to the sprite or fetched.
enum VelaPoiImages {
    private static let markers: [(group: String, color: UInt32, symbol: String)] = [
        ("food", 0xE8710A, "fork.knife"),
        ("fuel", 0x1967D2, "fuelpump.fill"),
        ("transit", 0x1A73E8, "bus.fill"),
        ("parking", 0x1A73E8, "parkingsign"),
        ("other", 0x5F6368, "mappin"),
    ]

    static func imageName(for group: String) -> String { "vela-poi-\(group)" }

    static func install(in style: MLNStyle) {
        for marker in markers {
            style.setImage(draw(marker.color, marker.symbol), forName: imageName(for: marker.group))
        }
    }

    private static func draw(_ rgb: UInt32, _ symbol: String) -> UIImage {
        let side: CGFloat = 28
        let size = CGSize(width: side, height: side)
        return UIGraphicsImageRenderer(size: size).image { context in
            let circle = CGRect(origin: .zero, size: size).insetBy(dx: 1.5, dy: 1.5)
            let path = UIBezierPath(ovalIn: circle)
            context.cgContext.setFillColor(UIColor(rgb: rgb).cgColor)
            context.cgContext.addPath(path.cgPath)
            context.cgContext.fillPath()
            context.cgContext.setStrokeColor(UIColor.white.cgColor)
            context.cgContext.setLineWidth(1.4)
            context.cgContext.addPath(path.cgPath)
            context.cgContext.strokePath()

            let configuration = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            if let glyph = UIImage(systemName: symbol, withConfiguration: configuration)?
                .withTintColor(.white, renderingMode: .alwaysOriginal) {
                let tinted = UIGraphicsImageRenderer(size: size).image { _ in
                    glyph.draw(at: CGPoint(x: (side - glyph.size.width) / 2,
                                           y: (side - glyph.size.height) / 2))
                }
                tinted.draw(at: .zero)
            } else {
                context.cgContext.setFillColor(UIColor.white.cgColor)
                context.cgContext.fillEllipse(in: circle.insetBy(dx: 7, dy: 7))
            }
        }
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255,
                  alpha: 1)
    }
}
