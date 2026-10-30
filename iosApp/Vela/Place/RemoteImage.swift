import Foundation
import Network
import SwiftUI
import UIKit

/// Loads Google images (place photos, reviewer avatars) with the image identity's headers, as the
/// Maps page would ask for them, and keeps them in memory. No cookies: Google's image hosts need
/// none.
///
/// The loader honors the Settings > Data and content policy: no photo traffic in low-data mode or
/// when photos are off, optionally only on Wi-Fi, a per-request size for the photo quality, and a
/// byte budget for the memory cache. The Settings screen reads [currentBytes] for its size row and
/// calls [purge] for "Clear photo cache".
final class ImageLoader {
    static let shared = ImageLoader()

    private let cache = NSCache<NSString, UIImage>()
    private let session: URLSession
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "app.vela.ios.photo-network")
    private let lock = NSLock()
    private var bytes = 0

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 20
        config.httpMaximumConnectionsPerHost = 4
        #if DEBUG
        PlaceFixtureLaunch.configure(session: config)
        #endif
        session = URLSession(configuration: config)
        monitor.start(queue: monitorQueue)
        applySettings()
    }

    /// Bytes the cache currently holds, as reported by the Settings storage row.
    var currentBytes: Int64 {
        lock.lock(); defer { lock.unlock() }
        return Int64(bytes)
    }

    /// Applies the cache budget and quality from the shared settings. A smaller budget evicts the
    /// whole cache rather than keeping more than the user chose.
    func applySettings() {
        let limit = ContentSettingsKeys.photoCacheMbValue * 1024 * 1024
        cache.totalCostLimit = limit
        if currentBytes > Int64(limit) { purge() }
    }

    func purge() {
        cache.removeAllObjects()
        lock.lock(); bytes = 0; lock.unlock()
    }

    func image(_ url: String, headers: [String: String]) async -> UIImage? {
        if let hit = cache.object(forKey: url as NSString) { return hit }
        guard photosMayLeaveThePhone else { return nil }
        guard let u = URL(string: sized(url)), u.scheme == "https" else { return nil }
        var req = URLRequest(url: u)
        for (name, value) in headers {
            req.setValue(value, forHTTPHeaderField: name)
        }
        guard let reply = try? await session.data(for: req),
              (reply.1 as? HTTPURLResponse)?.statusCode == 200,
              let image = UIImage(data: reply.0) else { return nil }
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 1
        cache.setObject(image, forKey: url as NSString, cost: cost)
        lock.lock(); bytes += cost; lock.unlock()
        return image
    }

    /// Low-data mode and "Load photos" off skip new downloads; Wi-Fi only checks the current path.
    private var photosMayLeaveThePhone: Bool {
        if ContentSettingsKeys.lowDataModeValue || !ContentSettingsKeys.loadPhotosValue { return false }
        if ContentSettingsKeys.photosWifiOnlyValue {
            let path = monitor.currentPath
            if path.status == .satisfied && path.isExpensive { return false }
        }
        return true
    }

    /// The URL asks for the photo quality: high 1200x900, standard the parser's 600x450, low
    /// 320x240. A URL without Google's size suffix is left alone.
    private func sized(_ url: String) -> String {
        switch ContentSettingsKeys.photoQualityValue {
        case "high":
            return url
                .replacingOccurrences(of: "=w\\d+-h\\d+", with: "=w1200-h900", options: .regularExpression)
                .replacingOccurrences(of: "=s\\d+", with: "=s1200", options: .regularExpression)
        case "low":
            return url
                .replacingOccurrences(of: "=w\\d+-h\\d+", with: "=w320-h240", options: .regularExpression)
                .replacingOccurrences(of: "=s\\d+", with: "=s320", options: .regularExpression)
        default:
            return url
        }
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
