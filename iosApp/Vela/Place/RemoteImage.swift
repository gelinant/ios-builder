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

/// An image from a Google host, a gray tile until it lands.
struct RemoteImage: View {
    let url: String
    let headers: [String: String]

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Rectangle().fill(Color(uiColor: .secondarySystemBackground))
            if let image {
                // Original colors: a reviewer's rounded PNG drawn as a template was a black disc
                // (its alpha filled with the label color, I-3).
                Image(uiImage: image.withRenderingMode(.alwaysOriginal))
                    .renderingMode(.original)
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
