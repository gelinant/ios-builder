import Foundation
import UIKit
import VelaCore

/// One tile address, hashable for the renderer's node map. Kotlin's `StreetViewTileRef` is not a
/// Swift value type, so the viewer mirrors it here.
struct StreetViewTileKey: Hashable {
    let zoom: Int32
    let x: Int32
    let y: Int32

    init(zoom: Int32, x: Int32, y: Int32) {
        self.zoom = zoom
        self.x = x
        self.y = y
    }

    init(_ ref: StreetViewTileRef) {
        self.init(zoom: ref.zoom, x: ref.x, y: ref.y)
    }
}

/// Loads the panorama's tiles: a small stitched base sphere first, then the visible detail tiles.
/// The image cache is bounded; the disk cache lives in Kotlin (`StreetViewStore.tile`). Requests
/// outside the viewport are cancelled through `StreetViewStore.cancelTiles`, and only tiles around
/// the viewport are ever asked for.
final class StreetViewTilesModel: ObservableObject {
    @Published private(set) var base: UIImage?
    @Published private(set) var tiles: [StreetViewTileKey: UIImage] = [:]
    @Published private(set) var detailLevel: StreetViewLevel?
    @Published private(set) var baseLoaded = false

    private let store: StreetViewStore?
    private let fixture: Bool
    private let cache = NSCache<NSString, UIImage>()

    private var pano: StreetViewPano?
    private var baseLevel: StreetViewLevel?
    private var generation = 0
    private var baseTask: Task<Void, Never>?
    private var viewTask: Task<Void, Never>?
    private var fetches: [StreetViewTileKey: Task<Void, Never>] = [:]

    init(store: StreetViewStore?, fixture: Bool) {
        self.store = store
        self.fixture = fixture
        cache.countLimit = 64
    }

    var loadedTileCount: Int { tiles.count }

    func load(pano: StreetViewPano) {
        cancel()
        self.pano = pano
        generation += 1
        let gen = generation
        let baseLevel = StreetViewTiles.shared.baseLevel(pano: pano)
        let detailLevel = StreetViewTiles.shared.detailLevel(pano: pano)
        self.baseLevel = baseLevel
        self.detailLevel = detailLevel
        let baseRefs = Self.allRefs(level: baseLevel)
        baseTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var images: [StreetViewTileKey: UIImage] = [:]
            for ref in baseRefs {
                if Task.isCancelled || gen != self.generation { return }
                let key = StreetViewTileKey(ref)
                if let image = await self.image(key: key, pano: pano) { images[key] = image }
            }
            guard !Task.isCancelled, gen == self.generation else { return }
            self.base = Self.stitch(level: baseLevel, images: images)
            self.baseLoaded = !images.isEmpty
        }
    }

    /// Called whenever the view settles; selects the detail tiles inside the field of view (plus a
    /// one-tile margin), cancels the rest and fetches what is missing.
    func updateView(yawDeg: Double, pitchDeg: Double, fovXDeg: Double, aspect: Double) {
        guard let pano, let detailLevel, let baseLevel else { return }
        guard generation > 0 else { return }
        let gen = generation
        let refs = StreetViewTiles.shared.visibleTiles(
            level: detailLevel, yawDeg: yawDeg, fovXDeg: fovXDeg, pitchDeg: pitchDeg,
            aspect: aspect, margin: 1)
        let wanted = Set(refs.map { StreetViewTileKey($0) })
        let staleTiles = tiles.keys.filter { !wanted.contains($0) }
        staleTiles.forEach { tiles.removeValue(forKey: $0) }
        let staleFetches = fetches.filter { !wanted.contains($0.key) }
        for (key, task) in staleFetches {
            task.cancel()
            fetches.removeValue(forKey: key)
        }
        // Keep the base tiles in flight: they are not part of the viewport's detail set.
        let keep = refs + Self.allRefs(level: baseLevel)
        store?.cancelTiles(panoId: pano.panoId, keep: keep)

        viewTask?.cancel()
        viewTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled, let self, gen == self.generation else { return }
            self.fetch(refs: refs, wanted: wanted, pano: pano, gen: gen)
        }
    }

    func cancel() {
        generation += 1
        baseTask?.cancel()
        viewTask?.cancel()
        baseTask = nil
        viewTask = nil
        fetches.values.forEach { $0.cancel() }
        fetches.removeAll()
        pano = nil
        base = nil
        baseLoaded = false
        tiles.removeAll()
        store?.cancelAllTiles()
    }

    private func fetch(refs: [StreetViewTileRef], wanted: Set<StreetViewTileKey>,
                       pano: StreetViewPano, gen: Int) {
        for ref in refs {
            let key = StreetViewTileKey(ref)
            guard tiles[key] == nil, fetches[key] == nil else { continue }
            fetches[key] = Task { @MainActor [weak self] in
                guard let self else { return }
                let image = await self.image(key: key, pano: pano)
                self.fetches.removeValue(forKey: key)
                guard let image, gen == self.generation, wanted.contains(key) else { return }
                self.tiles[key] = image
            }
        }
    }

    private func image(key: StreetViewTileKey, pano: StreetViewPano) async -> UIImage? {
        let cacheKey = "\(pano.panoId)/\(key.zoom)/\(key.x)/\(key.y)" as NSString
        if let hit = cache.object(forKey: cacheKey) { return hit }
        let image: UIImage?
        if fixture {
            #if DEBUG
            image = StreetViewFixtureImages.tile(zoom: key.zoom, x: key.x, y: key.y)
            #else
            image = nil
            #endif
        } else if let store {
            do {
                guard let bytes = try await store.tile(
                    panoId: pano.panoId, zoom: key.zoom, x: key.x, y: key.y) else { return nil }
                image = UIImage(data: IosBytes.shared.toData(bytes: bytes))
            } catch {
                return nil
            }
        } else {
            image = nil
        }
        if let image { cache.setObject(image, forKey: cacheKey) }
        return image
    }

    private static func allRefs(level: StreetViewLevel) -> [StreetViewTileRef] {
        var refs: [StreetViewTileRef] = []
        for y in 0..<max(1, Int(level.rows)) {
            for x in 0..<max(1, Int(level.columns)) {
                refs.append(StreetViewTileRef(zoom: level.zoom, x: Int32(x), y: Int32(y)))
            }
        }
        return refs
    }

    /// Composes a level's tiles into one equirectangular image. Edge tiles are clipped to the
    /// pyramid's real size, never stretched (old captures pad past their last column).
    private static func stitch(level: StreetViewLevel,
                               images: [StreetViewTileKey: UIImage]) -> UIImage? {
        let width = Int(level.width)
        let height = Int(level.height)
        let tile = Int(level.tileSize)
        guard width > 0, height > 0, tile > 0, !images.isEmpty else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        return UIGraphicsImageRenderer(size: bounds.size).image { context in
            for (key, image) in images {
                let target = CGRect(
                    x: Int(key.x) * tile, y: Int(key.y) * tile,
                    width: tile, height: tile).intersection(bounds)
                guard !target.isEmpty else { continue }
                context.cgContext.saveGState()
                context.cgContext.clip(to: target)
                image.draw(in: CGRect(x: Int(key.x) * tile, y: Int(key.y) * tile,
                                      width: tile, height: tile))
                context.cgContext.restoreGState()
            }
        }
    }
}
