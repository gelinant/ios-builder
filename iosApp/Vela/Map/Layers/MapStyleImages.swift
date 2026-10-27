import MapLibre
import UIKit

/// The exit-number badges the generated style references. They are drawn at load rather than
/// shipped in the sprite, the way Android's `RoadShields` paints its own, so the number reads as
/// the green sign it is. A style without these images still draws the number as text.
enum MapStyleImages {
    private static let widths: [Int: CGFloat] = [1: 18, 2: 23, 3: 29, 4: 35]

    static func install(in style: MLNStyle) {
        for (length, width) in widths {
            style.setImage(badge(width: width), forName: "vela-exit_\(length)")
        }
    }

    private static func badge(width: CGFloat) -> UIImage {
        let size = CGSize(width: width, height: 16)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 4)
            context.cgContext.setFillColor(UIColor(rgb: 0x1E7B45).cgColor)
            context.cgContext.addPath(path.cgPath)
            context.cgContext.fillPath()
            context.cgContext.setStrokeColor(UIColor.white.cgColor)
            context.cgContext.setLineWidth(1.1)
            context.cgContext.addPath(path.cgPath)
            context.cgContext.strokePath()
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
