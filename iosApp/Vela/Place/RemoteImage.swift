import SwiftUI
import UIKit

/// Loads Google images (place photos, reviewer avatars) with the image identity's headers, as the
/// Maps page would ask for them, and keeps them in memory. No cookies: Google's image hosts need
/// none.
final class ImageLoader {
    static let shared = ImageLoader()

    private let cache = NSCache<NSString, UIImage>()
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 20
        config.httpMaximumConnectionsPerHost = 4
        session = URLSession(configuration: config)
        cache.countLimit = 200
    }

    func image(_ url: String, headers: [String: String]) async -> UIImage? {
        if let hit = cache.object(forKey: url as NSString) { return hit }
        guard let u = URL(string: url), u.scheme == "https" else { return nil }
        var req = URLRequest(url: u)
        for (name, value) in headers {
            req.setValue(value, forHTTPHeaderField: name)
        }
        guard let reply = try? await session.data(for: req),
              (reply.1 as? HTTPURLResponse)?.statusCode == 200,
              let image = UIImage(data: reply.0) else { return nil }
        cache.setObject(image, forKey: url as NSString)
        return image
    }
}

/// Small sRGB pixel measurements for the avatar regression and its unit test. The image is scaled
/// down before sampling, which bounds the temporary buffer for a full-resolution gallery photo.
enum ImagePixels {
    struct Stats: Equatable {
        let visible: Int
        let nonBlack: Int
        let colorful: Int
    }

    static func stats(_ image: UIImage) -> Stats {
        guard let source = image.cgImage, source.width > 0, source.height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return Stats(visible: 0, nonBlack: 0, colorful: 0) }
        let scale = min(1, 64 / max(CGFloat(source.width), CGFloat(source.height)))
        let width = max(1, Int(CGFloat(source.width) * scale))
        let height = max(1, Int(CGFloat(source.height) * scale))
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let drew = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress,
                  let context = CGContext(
                    data: base, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drew else { return Stats(visible: 0, nonBlack: 0, colorful: 0) }
        var visible = 0
        var nonBlack = 0
        var colorful = 0
        for offset in stride(from: 0, to: rgba.count, by: 4) where rgba[offset + 3] > 16 {
            visible += 1
            let r = Int(rgba[offset])
            let g = Int(rgba[offset + 1])
            let b = Int(rgba[offset + 2])
            let low = min(r, g, b)
            let high = max(r, g, b)
            if high > 24 { nonBlack += 1 }
            if high > 24 && high - low > 12 { colorful += 1 }
        }
        return Stats(visible: visible, nonBlack: nonBlack, colorful: colorful)
    }

    static func hasNonBlackPixel(_ image: UIImage) -> Bool { stats(image).nonBlack > 0 }
}

/// An image from a Google host, a gray tile until it lands.
struct RemoteImage: View {
    let url: String
    let headers: [String: String]
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Rectangle().fill(Color(uiColor: .secondarySystemBackground))
            if let image {
                Image(uiImage: image.withRenderingMode(.alwaysOriginal))
                    .renderingMode(.original)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            }
        }
        .clipped()
        .task(id: url) {
            image = nil
            image = await ImageLoader.shared.image(url, headers: headers)
        }
    }
}

/// Avatars stay in UIKit. SwiftUI's template/rendering path produced black circles for valid
/// color PNGs; UIImageView gets the original sRGB image with no tint or rendering-mode rewrite.
struct RemoteAvatarImage: View {
    let url: String
    let headers: [String: String]
    let onImage: (UIImage) -> Void

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Circle().fill(Color(uiColor: .secondarySystemBackground))
            AvatarUIImageView(image: image)
                .frame(width: 32, height: 32)
        }
        .frame(width: 32, height: 32)
        .clipShape(Circle())
        .task(id: url) {
            image = nil
            guard let loaded = await ImageLoader.shared.image(url, headers: headers) else { return }
            image = loaded
            onImage(loaded)
        }
    }
}

private struct AvatarUIImageView: UIViewRepresentable {
    let image: UIImage?

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.setContentHuggingPriority(.required, for: .horizontal)
        view.setContentHuggingPriority(.required, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        view.image = image?.withRenderingMode(.alwaysOriginal)
        view.layer.cornerRadius = 16
    }
}
