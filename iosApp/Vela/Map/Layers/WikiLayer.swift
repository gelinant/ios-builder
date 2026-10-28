import Foundation
import MapLibre
import SafariServices
import UIKit
import VelaCore

/// The Wikivoyage layer (W-1). It asks the shared `WikiStore` for the curated destinations that
/// fall inside the viewport, draws a teal dot with the article title, and opens the article in an
/// in-app Safari sheet when its row is tapped. It draws nothing offline and nothing before the
/// first payload: with no rows the style gains no source and no layer.
///
/// The host (`WorldLayers.swift`) and its section are WLD-1's; this file only fills the socket.
final class WikiLayer: WorldLayer {
    let id = WikiLayerId
    let title = "Wikivoyage articles"
    let source = "Wikivoyage, CC BY-SA 4.0; Wikidata, CC0 1.0"
    var isInstalled: Bool { true }

    private static let sourceId = "vela-wiki-src"
    private static let circleId = "vela-wiki-circles"
    private static let labelId = "vela-wiki-labels"

    private let lock = NSLock()
    private var storedRows: [WorldLayerRow] = []
    private var articleURLs: [String: URL] = [:]
    private var focusObserver: NSObjectProtocol?

    init() {
        // The host recenters the map from the same notification. This layer also reads the tap to
        // open the article, because the row shape carries no URL and the host files stay WLD-1's.
        focusObserver = NotificationCenter.default.addObserver(
            forName: WorldLayers.focusNotification, object: nil, queue: .main
        ) { [weak self] note in
            self?.openArticle(for: note)
        }
    }

    deinit {
        if let focusObserver {
            NotificationCenter.default.removeObserver(focusObserver)
        }
    }

    var rows: [WorldLayerRow] {
        lock.lock()
        defer { lock.unlock() }
        return storedRows
    }

    func refresh(viewport: MapViewport) async -> WorldLayerRefresh? {
        guard let core = IosGraph.shared.core else { return nil }
        let store = WikiResources.shared.forCore(core: core)
        let articles: [WikiArticle]
        do {
            articles = try await store.articlesNear(
                south: viewport.south, west: viewport.west,
                north: viewport.north, east: viewport.east,
                language: nil)
        } catch {
            // Keep whatever the last accepted refresh delivered; the host ages it.
            return nil
        }
        var next: [WorldLayerRow] = []
        var urls: [String: URL] = [:]
        for article in articles {
            guard let lat = article.latitude?.doubleValue,
                  let lng = article.longitude?.doubleValue,
                  lat.isFinite, lng.isFinite,
                  let url = URL(string: article.url),
                  url.scheme == "https" else { continue }
            let rowId = "wiki:\(article.language):\(article.title)"
            next.append(WorldLayerRow(
                id: rowId,
                title: article.title,
                detail: "Wikivoyage, \(article.language.uppercased())",
                lat: lat,
                lng: lng))
            urls[rowId] = url
        }
        guard !next.isEmpty else { return nil }
        lock.lock()
        storedRows = next
        articleURLs = urls
        lock.unlock()
        return WorldLayerRefresh(
            updatedAtMs: Int64(Date().timeIntervalSince1970 * 1_000), rows: next)
    }

    func apply(style: MLNStyle, offline: Bool) {
        // A remote source is never drawn from a downloaded region.
        guard !offline else { return }
        let current = rows
        guard !current.isEmpty else { return }

        let features: [MLNPointFeature] = current.compactMap { row in
            guard let lat = row.lat, let lng = row.lng else { return nil }
            let feature = MLNPointFeature()
            feature.coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            feature.attributes = ["title": row.title]
            return feature
        }
        let shape = MLNShapeCollectionFeature(shapes: features)

        if let existing = style.source(withIdentifier: Self.sourceId) as? MLNShapeSource {
            existing.shape = shape
            return
        }

        let source = MLNShapeSource(identifier: Self.sourceId, shape: shape, options: nil)
        style.addSource(source)

        let circle = MLNCircleStyleLayer(identifier: Self.circleId, source: source)
        circle.circleRadius = NSExpression(forConstantValue: 5)
        circle.circleColor = NSExpression(forConstantValue: UIColor(red: 0.13, green: 0.42, blue: 0.55, alpha: 1))
        circle.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
        circle.circleStrokeWidth = NSExpression(forConstantValue: 1.5)
        style.addLayer(circle)

        let label = MLNSymbolStyleLayer(identifier: Self.labelId, source: source)
        label.text = NSExpression(forKeyPath: "title")
        label.textFontNames = NSExpression(
            forConstantValue: offline ? ["Noto Sans Regular"] : ["Roboto Medium"])
        label.textFontSize = NSExpression(forConstantValue: 11)
        label.textColor = NSExpression(forConstantValue: UIColor(red: 0.07, green: 0.25, blue: 0.33, alpha: 1))
        label.textHaloColor = NSExpression(forConstantValue: UIColor.white)
        label.textHaloWidth = NSExpression(forConstantValue: 1.5)
        label.textAnchor = NSExpression(forConstantValue: "top")
        label.textOffset = NSExpression(forConstantValue: NSValue(cgVector: CGVector(dx: 0, dy: 0.8)))
        label.textAllowsOverlap = NSExpression(forConstantValue: false)
        style.addLayer(label)
    }

    /// A row tap already recenters through the host; this opens the article in the app's Safari
    /// sheet, matched by the row's own coordinate so another layer's tap opens nothing.
    private func openArticle(for note: Notification) {
        guard let info = note.userInfo,
              let lat = info[WorldLayers.latitudeKey] as? Double,
              let lng = info[WorldLayers.longitudeKey] as? Double else { return }
        lock.lock()
        let match = storedRows.first {
            guard let rowLat = $0.lat, let rowLng = $0.lng else { return false }
            return abs(rowLat - lat) < 0.0008 && abs(rowLng - lng) < 0.0008
        }
        let url = match.flatMap { articleURLs[$0.id] }
        lock.unlock()
        guard let url else { return }
        present(url)
    }

    private func present(_ url: URL) {
        DispatchQueue.main.async {
            guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
                let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return }
            var top = root
            while let presented = top.presentedViewController {
                top = presented
            }
            guard !(top is SFSafariViewController) else { return }
            let safari = SFSafariViewController(url: url)
            top.present(safari, animated: true)
        }
    }
}
