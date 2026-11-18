// DEM download, terrarium decode and heightfield mesh build.
//
// Source: AWS Open Data "elevation-tiles-prod", the Mapzen terrain tiles. Tiles are the terrarium
// encoding: height in meters = (R * 256 + G + B / 256) - 32768. The spike pins four z11 tiles over
// Mont Blanc and Chamonix so a run always covers the same ground.
import Foundation
import UIKit

struct TerrainVertex {
    var positionAndHeight: SIMD4<Float>
    var normal: SIMD4<Float>
}

struct TerrainMesh {
    let vertices: [TerrainVertex]
    let indices: [UInt32]
    let triangleCount: Int
    let gridVerticesPerSide: Int
    let arrayBytes: Int
    let buildMilliseconds: Double
}

final class DEMBlock {
    static let zoom = 11
    static let originX = 1062
    static let originY = 729
    static let tilesPerSide = 2
    static let rasterPixelsPerSide = 512
    static let tileName = "elevation-tiles-prod/terrarium"
    static let baseURL = "https://s3.amazonaws.com/elevation-tiles-prod/terrarium"

    let heights: [Float]
    let decodeMilliseconds: Double
    let downloadMilliseconds: Double
    let downloadedBytes: Int

    init(heights: [Float], decodeMilliseconds: Double, downloadMilliseconds: Double, downloadedBytes: Int) {
        self.heights = heights
        self.decodeMilliseconds = decodeMilliseconds
        self.downloadMilliseconds = downloadMilliseconds
        self.downloadedBytes = downloadedBytes
    }

    static func fetchAndDecode() throws -> DEMBlock {
        let started = CACurrentMediaTime()
        var combined = [Float](repeating: 0, count: rasterPixelsPerSide * rasterPixelsPerSide)
        var downloaded = 0
        let decodeStart = CACurrentMediaTime()
        for ty in 0..<tilesPerSide {
            for tx in 0..<tilesPerSide {
                let x = originX + tx
                let y = originY + ty
                let urlString = "\(baseURL)/\(zoom)/\(x)/\(y).png"
                guard let url = URL(string: urlString) else { throw DEMError.badURL(urlString) }
                let data = try Data(contentsOf: url)
                downloaded += data.count
                guard let tile = decodeTerrarium(data) else { throw DEMError.badTile(urlString) }
                for row in 0..<256 {
                    let source = row * 256
                    let destination = (ty * 256 + row) * rasterPixelsPerSide + tx * 256
                    for column in 0..<256 {
                        combined[destination + column] = tile[source + column]
                    }
                }
                log("dem tile \(zoom)/\(x)/\(y) \(data.count) bytes")
            }
        }
        let now = CACurrentMediaTime()
        return DEMBlock(
            heights: combined,
            decodeMilliseconds: (now - decodeStart) * 1000,
            downloadMilliseconds: (now - started) * 1000,
            downloadedBytes: downloaded
        )
    }

    private static func decodeTerrarium(_ data: Data) -> [Float]? {
        guard let image = UIImage(data: data)?.cgImage else { return nil }
        let width = image.width
        let height = image.height
        guard width == 256, height == 256 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ok: Bool = pixels.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            // Flip so row 0 is the north edge of the tile, like the PNG.
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard ok else { return nil }
        var values = [Float](repeating: 0, count: width * height)
        for index in 0..<(width * height) {
            let r = Double(pixels[index * 4])
            let g = Double(pixels[index * 4 + 1])
            let b = Double(pixels[index * 4 + 2])
            values[index] = Float(r * 256 + g + b / 256 - 32768)
        }
        return values
    }

    /// Bilinear height at a normalized Web Mercator position (0..1 across the whole world).
    func heightAtNormalized(x: Double, y: Double) -> Float {
        // 256 raster pixels per z11 tile, unlike MapLibre's 512 render units per tile.
        let worldPixels = 256.0 * Double(1 << Self.zoom)
        let px = x * worldPixels - Double(Self.originX * 256) - 0.5
        let py = y * worldPixels - Double(Self.originY * 256) - 0.5
        let maxIndex = Self.rasterPixelsPerSide - 1
        let clampedX = min(max(px, 0), Double(maxIndex))
        let clampedY = min(max(py, 0), Double(maxIndex))
        let x0 = Int(clampedX)
        let y0 = Int(clampedY)
        let x1 = min(x0 + 1, maxIndex)
        let y1 = min(y0 + 1, maxIndex)
        let fx = Float(clampedX - Double(x0))
        let fy = Float(clampedY - Double(y0))
        let h00 = heights[y0 * Self.rasterPixelsPerSide + x0]
        let h10 = heights[y0 * Self.rasterPixelsPerSide + x1]
        let h01 = heights[y1 * Self.rasterPixelsPerSide + x0]
        let h11 = heights[y1 * Self.rasterPixelsPerSide + x1]
        return (h00 * (1 - fx) + h10 * fx) * (1 - fy) + (h01 * (1 - fx) + h11 * fx) * fy
    }

    func heightAt(latitude: Double, longitude: Double) -> Float {
        let n = Double(1 << Self.zoom)
        let x = (longitude + 180) / 360 * n / n
        let latRad = latitude * Double.pi / 180
        let y = (1 - log(tan(latRad) + 1 / cos(latRad)) / Double.pi) / 2
        return heightAtNormalized(x: x, y: y)
    }
}

enum DEMError: Error {
    case badURL(String)
    case badTile(String)
}

enum TerrainMeshBuilder {
    /// Builds an indexed grid over the two-by-two DEM block. `cellsPerTile` is the number of quads
    /// per side of one z11 tile: 128, 256 or 512.
    static func build(block: DEMBlock, cellsPerTile: Int) -> TerrainMesh {
        let started = CACurrentMediaTime()
        let verticesPerSide = cellsPerTile * DEMBlock.tilesPerSide + 1
        let cellCount = verticesPerSide - 1
        let count = verticesPerSide * verticesPerSide

        // Height is sampled once, then normals read the four neighbours from this buffer.
        var heightGrid = [Float](repeating: 0, count: count)
        let spanX = Double(DEMBlock.tilesPerSide) / Double(1 << DEMBlock.zoom)
        let spanY = spanX
        let originX = Double(DEMBlock.originX) / Double(1 << DEMBlock.zoom)
        let originY = Double(DEMBlock.originY) / Double(1 << DEMBlock.zoom)
        for row in 0..<verticesPerSide {
            let v = Double(row) / Double(cellCount)
            let y = originY + v * spanY
            for column in 0..<verticesPerSide {
                let u = Double(column) / Double(cellCount)
                let x = originX + u * spanX
                heightGrid[row * verticesPerSide + column] = block.heightAtNormalized(x: x, y: y)
            }
        }

        // One unit of the mesh is one Web Mercator world unit; the shader scales by 512 * 2^zoom.
        // The scene is 45.92 N, so a fixed metric cell size is enough for the lighting normals.
        let latitude = 45.92 * Double.pi / 180
        let spanMeters = spanX * 40_075_016.686 * cos(latitude)
        let cellMeters = spanMeters / Double(cellCount)

        var vertices = [TerrainVertex](
            repeating: TerrainVertex(positionAndHeight: SIMD4<Float>(0, 0, 0, 0), normal: SIMD4<Float>(0, 0, 1, 0)),
            count: count
        )
        for row in 0..<verticesPerSide {
            let v = Double(row) / Double(cellCount)
            let y = originY + v * spanY
            for column in 0..<verticesPerSide {
                let index = row * verticesPerSide + column
                let u = Double(column) / Double(cellCount)
                let x = originX + u * spanX
                let height = heightGrid[index]
                let left = heightGrid[row * verticesPerSide + max(column - 1, 0)]
                let right = heightGrid[row * verticesPerSide + min(column + 1, cellCount)]
                let up = heightGrid[max(row - 1, 0) * verticesPerSide + column]
                let down = heightGrid[min(row + 1, cellCount) * verticesPerSide + column]
                let dx = (right - left) / Float(2 * cellMeters)
                let dsouth = (down - up) / Float(2 * cellMeters)
                let length = (dx * dx + dsouth * dsouth + 1).squareRoot()
                let normal = SIMD3<Float>(-dx / length, -dsouth / length, 1 / length)
                vertices[index] = TerrainVertex(
                    positionAndHeight: SIMD4<Float>(Float(x), Float(y), 0, height),
                    normal: SIMD4<Float>(normal.x, normal.y, normal.z, 0)
                )
            }
        }

        let triangleCount = cellCount * cellCount * 2
        var indices = [UInt32](repeating: 0, count: triangleCount * 3)
        var cursor = 0
        for row in 0..<cellCount {
            for column in 0..<cellCount {
                let topLeft = UInt32(row * verticesPerSide + column)
                let topRight = UInt32(row * verticesPerSide + column + 1)
                let bottomLeft = UInt32((row + 1) * verticesPerSide + column)
                let bottomRight = UInt32((row + 1) * verticesPerSide + column + 1)
                indices[cursor] = topLeft
                indices[cursor + 1] = bottomLeft
                indices[cursor + 2] = topRight
                indices[cursor + 3] = topRight
                indices[cursor + 4] = bottomLeft
                indices[cursor + 5] = bottomRight
                cursor += 6
            }
        }

        let elapsed = (CACurrentMediaTime() - started) * 1000
        let bytes = vertices.count * MemoryLayout<TerrainVertex>.stride + indices.count * MemoryLayout<UInt32>.stride
        log("mesh \(cellsPerTile): \(triangleCount) tris, \(bytes) bytes, \(String(format: "%.1f", elapsed)) ms")
        return TerrainMesh(
            vertices: vertices,
            indices: indices,
            triangleCount: triangleCount,
            gridVerticesPerSide: verticesPerSide,
            arrayBytes: bytes,
            buildMilliseconds: elapsed
        )
    }
}
