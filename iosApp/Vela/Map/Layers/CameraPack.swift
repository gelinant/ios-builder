import Foundation

/// One camera a pack can draw. [kind] is `alpr` or `speed`, never anything else: the two map
/// layers keep their own switch and their own colour. [bearing] is the OSM facing in degrees
/// clockwise from north, or nil when the pack line carries no direction. The map draws no wedge
/// for a nil bearing: a guessed cone is worse than a bare dot.
struct CameraPoint: Equatable {
    let lat: Double
    let lng: Double
    let kind: String
    let bearing: Double?

    init(lat: Double, lng: Double, kind: String, bearing: Double? = nil) {
        self.lat = lat
        self.lng = lng
        self.kind = kind
        self.bearing = bearing
    }
}

/// A camera pack: the bundled plate-camera file, or one written next to a downloaded region.
///
/// A pack carries the date of its data. `maxAgeDays` is a hard rule: once a pack is older, it
/// contributes no point at all. A camera map is an invitation to trust a location, and a year-old
/// one is not worth drawing. The sheet says "stale" rather than showing a plausible but old dot.
struct CameraPack: Equatable {
    /// 365 days. The bundled pack is dated by `app/src/main/assets/flock_cameras_version.txt`;
    /// a region pack is dated when its Overpass answer was written.
    static let maxAgeDays = 365
    static let maxPointsPerKind = 600

    let id: String
    let name: String
    let kind: String
    let source: String
    let coverage: String
    let version: String
    let date: String
    let generatedAtMs: Int64
    let south: Double
    let west: Double
    let north: Double
    let east: Double
    let cameras: [CameraPoint]

    func intersects(south: Double, west: Double, north: Double, east: Double) -> Bool {
        !(north < self.south || self.north < south || east < self.west || self.east < west)
    }

    func contains(lat: Double, lng: Double) -> Bool {
        lat >= south && lat <= north && lng >= west && lng <= east
    }

    func stale(nowMs: Int64) -> Bool {
        // An unreadable date is treated as stale, never as "fresh enough".
        guard generatedAtMs > 0 else { return true }
        return nowMs - generatedAtMs > Int64(Self.maxAgeDays) * 86_400_000
    }

    /// Points of one kind inside the viewport, nearest to its centre first, capped like the live
    /// layer so a country-sized view cannot build a hundred thousand MapLibre features.
    func points(kind wanted: String, south: Double, west: Double, north: Double, east: Double,
                centerLat: Double, centerLng: Double, limit: Int = Self.maxPointsPerKind) -> [CameraPoint] {
        var kept: [(point: CameraPoint, distance: Double)] = []
        for camera in cameras where camera.kind == wanted {
            guard camera.lat >= south, camera.lat <= north,
                  camera.lng >= west, camera.lng <= east else { continue }
            kept.append((camera, CameraPack.distance(centerLat, centerLng, camera.lat, camera.lng)))
        }
        if kept.count > limit {
            kept.sort { $0.distance < $1.distance }
            kept.removeLast(kept.count - limit)
        }
        return kept.map(\.point)
    }

    private static func distance(_ aLat: Double, _ aLng: Double, _ bLat: Double, _ bLng: Double) -> Double {
        let scale = cos(aLat * .pi / 180)
        let dx = (bLng - aLng) * scale
        let dy = bLat - aLat
        return dx * dx + dy * dy
    }

    // MARK: - Parsing

    private struct RawPack: Decodable {
        let id: String?
        let name: String?
        let kind: String?
        let source: String?
        let coverage: String?
        let version: String?
        let date: String?
        let generatedAtMs: Int64?
        let s: Double
        let w: Double
        let n: Double
        let e: Double
        let cameras: [RawCameraValue]
    }

    /// One element of `cameras`. The bundled file stores `[lat, lng]` pairs, or `[lat, lng,
    /// degrees]` when the facing is known, to stay small; a region pack stores
    /// `{"lat":..,"lng":..,"kind":"speed","direction":..}` because one pack carries both kinds.
    /// A malformed element is dropped, never allowed to fail the whole pack.
    private struct RawCameraValue: Decodable {
        let camera: RawCamera?

        private struct Object: Decodable {
            let lat: Double
            let lng: Double
            let kind: String?
            let direction: Double?
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let values = try? container.decode([Double].self) {
                camera = values.count >= 2
                    ? RawCamera(lat: values[0], lng: values[1], kind: nil,
                                bearing: values.count >= 3 ? values[2] : nil)
                    : nil
                return
            }
            if let object = try? container.decode(Object.self) {
                camera = RawCamera(lat: object.lat, lng: object.lng, kind: object.kind,
                                   bearing: object.direction)
                return
            }
            camera = nil
        }
    }

    private struct RawCamera {
        let lat: Double
        let lng: Double
        let kind: String?
        let bearing: Double?
    }

    init(data: Data, fallbackKind: String) throws {
        let raw = try JSONDecoder().decode(RawPack.self, from: data)
        self.id = raw.id ?? "camera-pack"
        self.kind = raw.kind ?? fallbackKind
        self.source = raw.source ?? ""
        self.coverage = raw.coverage ?? ""
        self.version = raw.version ?? ""
        self.generatedAtMs = raw.generatedAtMs ?? 0
        self.date = raw.date ?? CameraPack.dateText(raw.generatedAtMs ?? 0)
        self.name = raw.name ?? "camera-pack-\(self.date)"
        self.south = raw.s
        self.west = raw.w
        self.north = raw.n
        self.east = raw.e
        let packKind = self.kind == "both" ? nil : self.kind
        self.cameras = raw.cameras.compactMap { value -> CameraPoint? in
            guard let camera = value.camera else { return nil }
            let kind = camera.kind ?? packKind
            guard let kind, kind == "alpr" || kind == "speed" else { return nil }
            guard (-90.0 ... 90.0).contains(camera.lat), (-180.0 ... 180.0).contains(camera.lng) else {
                return nil
            }
            return CameraPoint(lat: camera.lat, lng: camera.lng, kind: kind,
                               bearing: CameraCones.normalizeBearing(camera.bearing))
        }
    }

    init(id: String, name: String, kind: String, source: String = "", coverage: String = "",
         version: String = "", date: String, generatedAtMs: Int64,
         south: Double, west: Double, north: Double, east: Double, cameras: [CameraPoint]) {
        self.id = id
        self.name = name
        self.kind = kind
        self.source = source
        self.coverage = coverage
        self.version = version
        self.date = date
        self.generatedAtMs = generatedAtMs
        self.south = south
        self.west = west
        self.north = north
        self.east = east
        self.cameras = cameras
    }

    static func dateText(_ ms: Int64) -> String {
        guard ms > 0 else { return "unknown" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date(timeIntervalSince1970: Double(ms) / 1000))
    }
}

/// The packs available to the map: the one in the app bundle and the ones written into the
/// offline folder by a region download.
enum CameraPacks {
    static let bundledResource = "camera-pack"
    static let regionFolder = "camera-packs"

    /// Which pack a viewport can draw from, and which packs are present but stale.
    struct Selection: Equatable {
        var speed: [CameraPoint] = []
        var alpr: [CameraPoint] = []
        var fresh: [CameraPack] = []
        var stale: [CameraPack] = []

        var isEmpty: Bool { speed.isEmpty && alpr.isEmpty }
    }

    private final class BundleToken {}
    private static var bundledCache: CameraPack?
    private static var bundledLoaded = false
    private static var regionCache: [String: (mtime: Int64, pack: CameraPack?)] = [:]

    static func resetCacheForTest() {
        bundledCache = nil
        bundledLoaded = false
        regionCache = [:]
    }

    static var bundled: CameraPack? {
        if bundledLoaded { return bundledCache }
        bundledLoaded = true
        for bundle in [Bundle.main, Bundle(for: BundleToken.self)] {
            guard let url = bundle.url(forResource: bundledResource, withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let pack = try? CameraPack(data: data, fallbackKind: "alpr") else { continue }
            bundledCache = pack
            break
        }
        return bundledCache
    }

    /// Every region pack on disk, newest first. Unreadable files are skipped, not invented.
    static func regionPacks(rootPath: String) -> [CameraPack] {
        let directory = URL(fileURLWithPath: rootPath).appendingPathComponent(regionFolder)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
        var packs: [CameraPack] = []
        for url in entries where url.pathExtension == "json" {
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate?.timeIntervalSince1970) ?? 0
            let stamp = Int64(mtime * 1000)
            if let cached = regionCache[url.path], cached.mtime == stamp {
                if let pack = cached.pack { packs.append(pack) }
                continue
            }
            let pack = (try? Data(contentsOf: url))
                .flatMap { try? CameraPack(data: $0, fallbackKind: "both") }
            regionCache[url.path] = (stamp, pack)
            if let pack { packs.append(pack) }
        }
        return packs.sorted { $0.generatedAtMs > $1.generatedAtMs }
    }

    /// Packs that intersect the viewport, split into fresh and stale. Points are capped per kind,
    /// duplicates between the bundled and a region pack are dropped, and a stale pack adds nothing.
    static func selection(
        south: Double, west: Double, north: Double, east: Double,
        rootPath: String?, nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) -> Selection {
        let centerLat = (south + north) / 2
        let centerLng = (west + east) / 2
        var selection = Selection()
        var speedKeys = Set<Int64>()
        var alprKeys = Set<Int64>()
        var candidates = regionPacks(rootPath: rootPath ?? "")
        if let bundled { candidates.append(bundled) }
        for pack in candidates {
            guard pack.intersects(south: south, west: west, north: north, east: east) else { continue }
            if pack.stale(nowMs: nowMs) {
                selection.stale.append(pack)
                continue
            }
            selection.fresh.append(pack)
            for point in pack.points(kind: "speed", south: south, west: west, north: north, east: east,
                                     centerLat: centerLat, centerLng: centerLng) {
                guard speedKeys.insert(Self.key(point)).inserted else { continue }
                selection.speed.append(point)
            }
            for point in pack.points(kind: "alpr", south: south, west: west, north: north, east: east,
                                     centerLat: centerLat, centerLng: centerLng) {
                guard alprKeys.insert(Self.key(point)).inserted else { continue }
                selection.alpr.append(point)
            }
        }
        selection.fresh.sort { $0.generatedAtMs > $1.generatedAtMs }
        return selection
    }

    private static func key(_ point: CameraPoint) -> Int64 {
        let lat = Int64((point.lat * 100_000).rounded())
        let lng = Int64((point.lng * 100_000).rounded())
        return lat &* 100_000_003 &+ lng
    }
}

/// Which camera family the map may draw. `auto` follows the style: live query online, the pack
/// over a downloaded region. `live` and `pack` are explicit and never fall back to each other.
enum CameraSource: String, CaseIterable {
    case auto
    case live
    case pack

    static func normalize(_ value: String?) -> CameraSource {
        CameraSource(rawValue: value ?? "") ?? .auto
    }

    func drawsLive(offline: Bool) -> Bool {
        switch self {
        case .live: return true
        case .pack: return false
        case .auto: return !offline
        }
    }

    func drawsPack(offline: Bool) -> Bool {
        switch self {
        case .pack: return true
        case .live: return false
        case .auto: return offline
        }
    }

    var title: String {
        switch self {
        case .auto: return "Automatic"
        case .live: return "Live query"
        case .pack: return "Offline pack"
        }
    }
}

/// What `MapLayers` did with the cameras on the last apply, read by the sheet's debug line. The
/// UI scenario asserts this, so a switch that changes a preference without changing the source
/// cannot pass.
enum CameraPackDebug {
    /// For example `cam=pack:camera-pack-2026-07-21:504` or `cam=live`.
    static var line = "cam=live"
    /// Plate cameras currently drawn, split by whether the source carries a bearing. The UI
    /// scenario reports both counts; a missing tag must stay visible as an unoriented camera.
    /// For example `oriented=2 unoriented=1`.
    static var cones = "oriented=0 unoriented=0"

    static func describe(
        mode: CameraSource, offline: Bool, packName: String, packDate: String,
        packCovers: Bool, packStale: Bool, count: Int
    ) -> String {
        if mode.drawsLive(offline: offline) { return "cam=live" }
        guard mode.drawsPack(offline: offline) else { return "cam=none" }
        if packStale && !packCovers { return "cam=stale:\(packDate)" }
        guard packCovers else { return "cam=none" }
        return "cam=pack:\(packName):\(count)"
    }
}
