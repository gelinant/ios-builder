import OSLog
import SwiftUI
import UIKit

/// Loads Google images (place photos, reviewer avatars) with the image identity's headers, as the
/// Maps page would ask for them, and keeps them in memory. No cookies: Google's image hosts need
/// none.
final class ImageLoader {
    static let shared = ImageLoader()

    private let cache = NSCache<NSString, UIImage>()
    private let log = Logger(subsystem: "app.vela.ios", category: "Image")
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
        let reply = try? await session.data(for: req)
        let http = reply?.1 as? HTTPURLResponse
        let avatar = url.contains("/a/") || url.contains("/a-/")
        if avatar {
            // Reviewer avatars drew as black discs on the simulator (I-3): what came back.
            let decoded = reply.flatMap { UIImage(data: $0.0) }
            log.info("avatar \(http?.statusCode ?? 0, privacy: .public) \(http?.value(forHTTPHeaderField: "Content-Type") ?? "-", privacy: .public) \(reply?.0.count ?? 0, privacy: .public) bytes \(Int(decoded?.size.width ?? 0), privacy: .public)x\(Int(decoded?.size.height ?? 0), privacy: .public) bpc=\(decoded?.cgImage?.bitsPerComponent ?? 0, privacy: .public) alpha=\(decoded?.cgImage?.alphaInfo.rawValue ?? 99, privacy: .public) cs=\((decoded?.cgImage?.colorSpace?.name as String?) ?? "-", privacy: .public) \(String(url.suffix(40)), privacy: .public)")
        }
        guard let reply, http?.statusCode == 200, let decoded = UIImage(data: reply.0) else { return nil }
        let image = avatar ? Self.redrawn(decoded) : decoded
        cache.setObject(image, forKey: url as NSString)
        return image
    }

    /// [image] drawn again into a plain 8-bit sRGB bitmap with alpha. The avatars' rounded PNGs
    /// decoded fine (120 by 120) yet drew as black discs on the simulator (I-3).
    private static func redrawn(_ image: UIImage) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.preferredRange = .standard
        format.opaque = false
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}

/// An image from a Google host, a gray tile until it lands.
struct RemoteImage: View {
    let url: String
    let headers: [String: String]

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Rectangle().fill(Color(uiColor: .secondarySystemBackground))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .clipped()
        .task(id: url) {
            image = await ImageLoader.shared.image(url, headers: headers)
        }
    }
}
