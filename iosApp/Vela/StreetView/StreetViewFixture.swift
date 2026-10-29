#if DEBUG
import UIKit
import VelaCore

/// The synthetic equirectangular image behind the CI renderer scenario. It is drawn at runtime,
/// never shipped as an asset: sky above the horizon, ground below, and N/E/S/W markers whose
/// positions follow Google's texture frame (capture heading at the image center). A screenshot
/// therefore shows whether the renderer's yaw, wrap and vertical projection are right, even when
/// Google answers no imagery to the runner.
enum StreetViewFixtureImages {
    static let fullWidth = 2048
    static let fullHeight = 1024

    private static var cachedFull: UIImage?

    static var full: UIImage {
        if let cachedFull { return cachedFull }
        let size = CGSize(width: fullWidth, height: fullHeight)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let cg = context.cgContext
            let horizon = size.height / 2

            let sky = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
                UIColor(red: 0.04, green: 0.16, blue: 0.30, alpha: 1).cgColor,
                UIColor(red: 0.62, green: 0.78, blue: 0.92, alpha: 1).cgColor,
            ] as CFArray, locations: nil)!
            cg.drawLinearGradient(sky, start: CGPoint(x: 0, y: 0),
                                  end: CGPoint(x: 0, y: horizon), options: [])

            let ground = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
                UIColor(red: 0.38, green: 0.42, blue: 0.36, alpha: 1).cgColor,
                UIColor(red: 0.14, green: 0.17, blue: 0.14, alpha: 1).cgColor,
            ] as CFArray, locations: nil)!
            cg.drawLinearGradient(ground, start: CGPoint(x: 0, y: horizon),
                                  end: CGPoint(x: 0, y: size.height), options: [])

            cg.setStrokeColor(UIColor.white.withAlphaComponent(0.55).cgColor)
            cg.setLineWidth(4)
            cg.move(to: CGPoint(x: 0, y: horizon))
            cg.addLine(to: CGPoint(x: size.width, y: horizon))
            cg.strokePath()

            // A marker every 30 degrees, taller on the cardinal points.
            let letters = ["N", "E", "S", "W"]
            for step in 0..<12 {
                let u = Double(step) / 12.0
                let x = CGFloat(u) * size.width
                let cardinal = step % 3 == 0
                cg.setStrokeColor(UIColor(red: 0.95, green: 0.85, blue: 0.2, alpha: 0.9).cgColor)
                cg.setLineWidth(cardinal ? 6 : 2)
                cg.move(to: CGPoint(x: x, y: horizon - (cardinal ? 54 : 24)))
                cg.addLine(to: CGPoint(x: x, y: horizon + (cardinal ? 54 : 24)))
                cg.strokePath()
                guard cardinal else { continue }
                let letter = letters[(step / 3) % letters.count]
                let text = letter as NSString
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 120, weight: .heavy),
                    .foregroundColor: UIColor.white,
                ]
                let textSize = text.size(withAttributes: attrs)
                let rect = CGRect(
                    x: x - textSize.width / 2,
                    y: horizon - 170 - textSize.height / 2,
                    width: textSize.width, height: textSize.height)
                text.draw(in: rect, withAttributes: attrs)
            }

            // Asymmetric landmark: a red band at u = 0.625 (south-east of north), so a mirrored
            // texture is visible in the screenshots, not only with the cardinal letters.
            cg.setFillColor(UIColor(red: 0.85, green: 0.18, blue: 0.18, alpha: 1).cgColor)
            cg.fill(CGRect(x: size.width * 0.60, y: horizon - 300,
                           width: size.width * 0.05, height: 90))
        }
        cachedFull = image
        return image
    }

    /// One tile of the fixture pyramid: zoom 0 is 512x256, one more zoom doubles both sides.
    static func tile(zoom: Int32, x: Int32, y: Int32) -> UIImage? {
        let width = 512 << Int(zoom)
        guard width > 0, fullWidth % width == 0 else { return nil }
        let scale = fullWidth / width
        let tile = 512
        let rect = CGRect(
            x: CGFloat(Int(x) * tile * scale), y: CGFloat(Int(y) * tile * scale),
            width: CGFloat(tile * scale), height: CGFloat(tile * scale))
        guard let source = full.cgImage, let cropped = source.cropping(to: rect) else { return nil }
        let image = UIImage(cgImage: cropped)
        guard scale > 1 else { return image }
        let size = CGSize(width: tile, height: tile)
        return UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
#endif
