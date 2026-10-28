import XCTest
@testable import Vela

/// The offline camera pack: its parser, its date rule and its coverage. The bundled pack is the
/// DeFlock/OpenStreetMap file the Android app ships, converted by `scripts/ios/gen-camera-pack.py`.
final class CameraPackTests: XCTestCase {
    override func setUp() {
        super.setUp()
        CameraPacks.resetCacheForTest()
    }

    func testBundledPackParsesWithItsDateAndWorldCoverage() throws {
        let pack = try XCTUnwrap(CameraPacks.bundled, "camera-pack.json is missing from the bundle")
        XCTAssertEqual(pack.id, "camera-pack")
        XCTAssertEqual(pack.name, "camera-pack-2026-07-21")
        XCTAssertEqual(pack.date, "2026-07-21")
        XCTAssertEqual(pack.kind, "alpr", "the repository ships plate cameras only")
        XCTAssertEqual(pack.cameras.count, 127_264)
        XCTAssertTrue(pack.cameras.allSatisfy { $0.kind == "alpr" })
        XCTAssertEqual(pack.south, -90)
        XCTAssertEqual(pack.west, -180)
        XCTAssertTrue(pack.contains(lat: 37.7749, lng: -122.4194), "San Francisco")
        XCTAssertTrue(pack.contains(lat: 38.5449, lng: -121.7405), "Davis")
        XCTAssertFalse(pack.stale(nowMs: pack.generatedAtMs + 30 * 86_400_000),
                       "a pack one month old is still drawn")
    }

    func testParserKeepsPairsAndTaggedObjectsAndDropsInvalidPoints() throws {
        let data = Data("""
        {"id":"tmp","name":"tmp-2026-01-02","kind":"alpr","generatedAtMs":1767312000000,
         "date":"2026-01-02","s":37.0,"w":-122.0,"n":38.0,"e":-121.0,
         "cameras":[[37.5,-121.5],{"lat":37.6,"lng":-121.4,"kind":"speed"},
                    [37.7],{"lat":95.0,"lng":-121.0,"kind":"alpr"}]}
        """.utf8)
        let pack = try CameraPack(data: data, fallbackKind: "alpr")
        XCTAssertEqual(pack.cameras, [
            CameraPoint(lat: 37.5, lng: -121.5, kind: "alpr"),
            CameraPoint(lat: 37.6, lng: -121.4, kind: "speed"),
        ])
        XCTAssertEqual(pack.name, "tmp-2026-01-02")
        XCTAssertEqual(pack.date, "2026-01-02")
    }

    func testStalePackIsReportedAndDrawsNothing() throws {
        let day: Int64 = 86_400_000
        let now: Int64 = 1_800_000_000_000
        let old = pack(date: "2025-01-01", generatedAtMs: now - 400 * day)
        let fresh = pack(date: "2026-07-21", generatedAtMs: now - 20 * day)
        XCTAssertTrue(old.stale(nowMs: now), "400 days is stale")
        XCTAssertFalse(fresh.stale(nowMs: now), "20 days is fresh")
        let undated = CameraPack(
            id: "undated", name: "undated", kind: "alpr", date: "unknown", generatedAtMs: 0,
            south: 37.0, west: -122.0, north: 38.0, east: -121.0, cameras: [])
        XCTAssertTrue(undated.stale(nowMs: now), "an unknown date is stale, never fresh")

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vela-camera-stale-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent(CameraPacks.regionFolder, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try write(old, to: folder.appendingPathComponent("old.json"))
        try write(fresh, to: folder.appendingPathComponent("fresh.json"))

        let selection = CameraPacks.selection(
            south: 37.0, west: -122.0, north: 38.0, east: -121.0,
            rootPath: root.path, nowMs: now)
        XCTAssertEqual(selection.stale.map(\.date), ["2025-01-01"])
        XCTAssertTrue(selection.fresh.contains { $0.date == "2026-07-21" })
        XCTAssertEqual(selection.speed.count, 1, "only the fresh pack contributes")
        XCTAssertTrue(selection.alpr.contains(CameraPoint(lat: 37.6, lng: -121.4, kind: "alpr")),
                      "the fresh pack joins the bundled one")
        XCTAssertFalse(selection.alpr.contains(CameraPoint(lat: 37.5, lng: -121.5, kind: "alpr")),
                       "the stale pack adds nothing")
    }

    func testCoverageFiltersTheViewportAndCapsThePoints() throws {
        let pack = try CameraPack(
            id: "tmp", name: "tmp", kind: "both", date: "2026-01-02",
            generatedAtMs: 1_767_312_000_000,
            south: 37.0, west: -122.0, north: 38.0, east: -121.0,
            cameras: [
                CameraPoint(lat: 37.5, lng: -121.5, kind: "speed"),
                CameraPoint(lat: 37.6, lng: -121.4, kind: "speed"),
                CameraPoint(lat: 38.5, lng: -121.5, kind: "speed"),
            ])
        XCTAssertTrue(pack.intersects(south: 37.4, west: -121.6, north: 37.7, east: -121.3))
        XCTAssertFalse(pack.intersects(south: 39.0, west: -121.6, north: 39.7, east: -121.3))
        let points = pack.points(kind: "speed", south: 37.0, west: -122.0, north: 38.0, east: -121.0,
                                 centerLat: 37.55, centerLng: -121.45)
        XCTAssertEqual(points.count, 2, "38.5 is outside the view")
        let capped = pack.points(kind: "speed", south: 37.0, west: -122.0, north: 38.0, east: -121.0,
                                 centerLat: 37.55, centerLng: -121.45, limit: 1)
        XCTAssertEqual(capped, [CameraPoint(lat: 37.5, lng: -121.5, kind: "speed")],
                       "the nearest point survives the cap")
    }

    func testCameraSourceNeverFallsBackBetweenLiveAndPack() {
        XCTAssertEqual(CameraSource.normalize(nil), .auto)
        XCTAssertEqual(CameraSource.normalize("nonsense"), .auto)
        XCTAssertEqual(CameraSource.normalize("pack"), .pack)
        XCTAssertTrue(CameraSource.live.drawsLive(offline: false))
        XCTAssertTrue(CameraSource.live.drawsLive(offline: true))
        XCTAssertFalse(CameraSource.live.drawsPack(offline: true))
        XCTAssertTrue(CameraSource.pack.drawsPack(offline: false))
        XCTAssertFalse(CameraSource.pack.drawsLive(offline: false))
        XCTAssertTrue(CameraSource.auto.drawsLive(offline: false))
        XCTAssertFalse(CameraSource.auto.drawsPack(offline: false))
        XCTAssertTrue(CameraSource.auto.drawsPack(offline: true))
        XCTAssertFalse(CameraSource.auto.drawsLive(offline: true))
    }

    func testOfflineStyleStaysRemoteFreeWithThePackOn() throws {
        let layers = AppGraph.session.layers
        layers.setCameraSource(source: "pack")
        layers.setSwitch(key: "speed", on: true)
        layers.setSwitch(key: "alpr", on: true)
        defer {
            layers.setCameraSource(source: "auto")
            layers.setSwitch(key: "speed", on: false)
            layers.setSwitch(key: "alpr", on: false)
        }
        XCTAssertEqual(layers.state.value.cameraSource, "pack")
        XCTAssertTrue(layers.state.value.speedCameras)
        XCTAssertTrue(layers.state.value.alprCameras)

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vela-camera-offline-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let archive = root.appendingPathComponent("monaco.pmtiles")
        try Data(repeating: 0, count: 128).write(to: archive)
        let style = try OfflineStyleFactory.makeStyle(
            archivePath: archive.path,
            glyphsPath: root.appendingPathComponent("glyphs").path,
            spritesPath: root.appendingPathComponent("sprites").path)
        XCTAssertEqual(OfflineStyleFactory.remoteURLCount(in: style), 0)
        let json = try String(contentsOf: style, encoding: .utf8)
        XCTAssertFalse(json.contains("camera-pack"), "the pack is an in-memory shape source")
        XCTAssertFalse(json.contains("overpass"), "the offline style never queries Overpass")
    }

    func testDebugLineNamesThePackAndTheSource() {
        let pack = "camera-pack-2026-07-21"
        XCTAssertEqual(CameraPackDebug.describe(
            mode: .pack, offline: false, packName: pack, packDate: "2026-07-21",
            packCovers: true, packStale: false, count: 504),
            "cam=pack:camera-pack-2026-07-21:504")
        XCTAssertEqual(CameraPackDebug.describe(
            mode: .auto, offline: false, packName: pack, packDate: "2026-07-21",
            packCovers: true, packStale: false, count: 504), "cam=live")
        XCTAssertEqual(CameraPackDebug.describe(
            mode: .auto, offline: true, packName: pack, packDate: "2026-07-21",
            packCovers: true, packStale: false, count: 504),
            "cam=pack:camera-pack-2026-07-21:504")
        XCTAssertEqual(CameraPackDebug.describe(
            mode: .pack, offline: false, packName: "", packDate: "2025-01-01",
            packCovers: false, packStale: true, count: 0), "cam=stale:2025-01-01")
    }

    // MARK: - Helpers

    private func pack(date: String, generatedAtMs: Int64) -> CameraPack {
        CameraPack(
            id: "tmp", name: "tmp-\(date)", kind: "both", date: date,
            generatedAtMs: generatedAtMs,
            south: 37.0, west: -122.0, north: 38.0, east: -121.0,
            cameras: [
                CameraPoint(lat: 37.5, lng: -121.5, kind: "speed"),
                CameraPoint(lat: 37.6, lng: -121.4, kind: "alpr"),
            ])
    }

    private func write(_ pack: CameraPack, to url: URL) throws {
        let object: [String: Any] = [
            "id": pack.id, "name": pack.name, "kind": pack.kind,
            "generatedAtMs": pack.generatedAtMs, "date": pack.date,
            "s": pack.south, "w": pack.west, "n": pack.north, "e": pack.east,
            "cameras": pack.cameras.map { ["lat": $0.lat, "lng": $0.lng, "kind": $0.kind] },
        ]
        try JSONSerialization.data(withJSONObject: object).write(to: url)
    }
}
