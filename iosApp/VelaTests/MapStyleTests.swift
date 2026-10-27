import XCTest
@testable import Vela

final class MapStyleTests: XCTestCase {
    private func options(_ look: MapLook = .vela, appearance: MapAppearance = .light,
                         names: MapNamesMode = .englishLatin,
                         house: HouseNumberLevel = .normal) -> MapStyleOptions {
        MapStyleOptions(look: look, appearance: appearance, names: names,
                        houseNumbers: house, language: "en")
    }

    private func layers(_ root: [String: Any]) -> [String: [String: Any]] {
        Dictionary(uniqueKeysWithValues: (root["layers"] as? [[String: Any]] ?? [])
            .compactMap { layer in
                (layer["id"] as? String).map { ($0, layer) }
            })
    }

    func testEveryLookHasALocalGeneratedStyle() throws {
        for look in MapLook.allCases {
            for appearance in [MapAppearance.light, .dark] where look == .vela || appearance == .light {
                let root = try MapStyleBuilder.root(options: options(look, appearance: appearance))
                XCTAssertEqual((root["layers"] as? [Any])?.count, 112,
                               "\(look) \(appearance) layer count")
                XCTAssertNotNil((root["metadata"] as? [String: Any])?["vela:look"])
            }
        }
    }

    func testStyleDocumentIsLocalAndOnlyTheTileSourceIsRemote() throws {
        let root = try MapStyleBuilder.root(options: options(.vela))
        let sources = try XCTUnwrap(root["sources"] as? [String: Any])
        XCTAssertNil(sources["ne2_shaded"])
        let vector = try XCTUnwrap(sources["openmaptiles"] as? [String: Any])
        XCTAssertNil(vector["url"], "a style source url is a remote style fetch")
        XCTAssertTrue((vector["tiles"] as? [String])?.first?.hasPrefix("https://") == true)
        let encoded = try JSONSerialization.data(withJSONObject: root)
        let text = String(decoding: encoded, as: UTF8.self)
        XCTAssertFalse(text.contains("tiles.openfreemap.org/styles/"),
                       "the style document must not name a remote style endpoint")
    }

    func testHouseNumbersAndExitNumbersUseTheVectorFields() throws {
        for look in MapLook.allCases {
            let root = try MapStyleBuilder.root(options: options(look))
            let byId = layers(root)
            let house = try XCTUnwrap(byId["vela-housenumber"])
            XCTAssertEqual(house["source-layer"] as? String, "housenumber")
            XCTAssertEqual(house["minzoom"] as? Double, 17.8)
            let houseLayout = try XCTUnwrap(house["layout"] as? [String: Any])
            XCTAssertEqual(houseLayout["text-field"] as? [String], ["get", "housenumber"])
            XCTAssertEqual(houseLayout["text-ignore-placement"] as? Bool, true)

            let exit = try XCTUnwrap(byId["vela-exit-shield"])
            XCTAssertEqual(exit["source-layer"] as? String, "transportation_name")
            XCTAssertEqual(exit["minzoom"] as? Double, 12.5)
            let filters = try XCTUnwrap(exit["filter"] as? [Any])
            XCTAssertTrue(filters.contains { value in
                (value as? [Any])?.first as? String == "=="
            })
        }
    }

    func testHouseNumberSettingMovesTheZoomGate() throws {
        let near = try MapStyleBuilder.root(options: options(house: .near))
        let far = try MapStyleBuilder.root(options: options(house: .far))
        XCTAssertEqual(layers(near)["vela-housenumber"]?["minzoom"] as? Double, 18.3)
        XCTAssertEqual(layers(far)["vela-housenumber"]?["minzoom"] as? Double, 17.3)
        let paint = try XCTUnwrap(layers(far)["vela-housenumber"]?["paint"] as? [String: Any])
        let opacity = try XCTUnwrap(paint["text-opacity"] as? [Any])
        XCTAssertEqual(opacity[3] as? Double, 17.3)
    }

    func testNameModesRewriteRoadAndPlaceLabels() throws {
        let local = layers(try MapStyleBuilder.root(options: options(names: .local)))
        let minor = try XCTUnwrap(local["highway-name-minor"]?["layout"] as? [String: Any])
        XCTAssertEqual(minor["text-field"] as? [String], ["get", "name"])
        let poi = try XCTUnwrap(local["poi_r1"]?["layout"] as? [String: Any])
        XCTAssertEqual(poi["text-field"] as? [String], ["get", "name"])

        let english = layers(try MapStyleBuilder.root(options: options(names: .englishLatin)))
        let major = try XCTUnwrap(english["highway-name-major"]?["layout"] as? [String: Any])
        let field = try XCTUnwrap(major["text-field"] as? [Any])
        XCTAssertEqual(field.first as? String, "coalesce")
        XCTAssertTrue(field.contains { ($0 as? [String]) == ["get", "name:latin"] })

        let both = layers(try MapStyleBuilder.root(options: options(names: .localEnglish)))
        let line = try XCTUnwrap(both["highway-name-minor"]?["layout"] as? [String: Any])
        let lineField = try XCTUnwrap(line["text-field"] as? [Any])
        XCTAssertEqual(lineField.first as? String, "case")
        let lineConcat = try XCTUnwrap(lineField[2] as? [Any])
        XCTAssertEqual(lineConcat[2] as? String, "  ")
        let point = try XCTUnwrap(both["poi_r1"]?["layout"] as? [String: Any])
        let pointField = try XCTUnwrap(point["text-field"] as? [Any])
        let pointConcat = try XCTUnwrap(pointField[2] as? [Any])
        XCTAssertEqual(pointConcat[2] as? String, "\n")
    }

    func testOfflineStyleHasNoRemoteURLForEveryLook() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vela-style-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let archive = root.appendingPathComponent("region.pmtiles")
        try Data(repeating: 0, count: 64).write(to: archive)
        for look in MapLook.allCases {
            for names in [MapNamesMode.englishLatin, .local] {
                let style = try OfflineStyleFactory.makeStyle(
                    archivePath: archive.path,
                    glyphsPath: root.appendingPathComponent("glyphs").path,
                    spritesPath: root.appendingPathComponent("sprites").path,
                    options: options(look, names: names, house: .far))
                XCTAssertEqual(OfflineStyleFactory.remoteURLCount(in: style), 0,
                               "\(look) \(names) kept a remote URL")
                let object = try JSONSerialization.jsonObject(
                    with: Data(contentsOf: style)) as! [String: Any]
                let byId = layers(object)
                XCTAssertNotNil(byId["vela-housenumber"], "\(look) lost house numbers offline")
                XCTAssertNotNil(byId["vela-exit-shield"], "\(look) lost exit numbers offline")
            }
        }
    }
}
