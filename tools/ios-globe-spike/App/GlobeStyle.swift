// Local style document for the spike. The projection is a style property in this pre-release:
// "projection": {"type": "globe"} on the document; without it the map stays Mercator.
import Foundation

enum GlobeStyle {
    static let tiles = "https://tiles.openfreemap.org/planet"

    static func document(projection: String) -> [String: Any] {
        var doc: [String: Any] = [
            "version": 8,
            "name": "globe-spike",
            "sources": [
                "planet": ["type": "vector", "url": tiles],
            ],
            "layers": [
                [
                    "id": "background",
                    "type": "background",
                    "paint": ["background-color": "#101820"],
                ],
                [
                    "id": "landcover",
                    "type": "fill",
                    "source": "planet",
                    "source-layer": "landcover",
                    "paint": ["fill-color": "#182a20"],
                ],
                [
                    "id": "water",
                    "type": "fill",
                    "source": "planet",
                    "source-layer": "water",
                    "paint": ["fill-color": "#0d3354"],
                ],
                [
                    "id": "boundary",
                    "type": "line",
                    "source": "planet",
                    "source-layer": "boundary",
                    "filter": ["==", ["get", "admin_level"], 2],
                    "paint": [
                        "line-color": "#5b6b7f",
                        "line-width": 0.6,
                        "line-opacity": 0.85,
                    ],
                ],
            ],
        ]
        if projection == "globe" {
            doc["projection"] = ["type": "globe"]
        }
        return doc
    }

    static func write(projection: String) -> URL {
        let url = SpikeFiles.documents.appendingPathComponent("style-\(projection).json")
        let data = try! JSONSerialization.data(
            withJSONObject: document(projection: projection),
            options: [.prettyPrinted, .sortedKeys]
        )
        try! data.write(to: url)
        return url
    }
}

enum SpikeFiles {
    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static func write(_ name: String, _ text: String = "") {
        let url = documents.appendingPathComponent(name)
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    static func writeJSON(_ name: String, _ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys]
        ) else { return }
        try? data.write(to: documents.appendingPathComponent(name))
    }
}
