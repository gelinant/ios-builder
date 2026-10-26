import SceneKit
import UIKit
import VelaCore

/// The panorama renderer: a textured sphere seen from inside, plus higher-resolution tile quads
/// over the part of the sphere that is in view. SceneKit draws the featureless sphere as one
/// geometry, so the 360 degree context is immediate; detail tiles replace it where the user looks.
///
/// Texture frame and camera follow Android's `PanoramaView`: the texture's u and v increase with
/// the image, yaw 0 looks at u = 0.75, and `StreetViewTiles` owns the compass conversion. That
/// keeps the two viewers' headings, drag direction and zoom range identical.
final class StreetViewSceneRenderer: ObservableObject {
    let view: SCNView

    private let scene = SCNScene()
    private let cameraNode = SCNNode()
    private let baseNode = SCNNode()
    private let detailNode = SCNNode()
    private let camera = SCNCamera()

    private var panoId: String?
    private var panoHeading = 0.0
    private var baseImage: UIImage?
    private var detailLevel: (zoom: Int32, columns: Int32, rows: Int32)?
    private var detailKeys: Set<StreetViewTileKey> = []
    private var detailImages: [StreetViewTileKey: UIImage] = [:]

    private static let baseRadius: CGFloat = 1.0
    private static let detailRadius: CGFloat = 0.9985

    init() {
        view = SCNView(frame: .zero)
        view.scene = scene
        view.backgroundColor = .black
        view.antialiasingMode = .multisampling2X
        view.preferredFramesPerSecond = 60
        view.isPlaying = true
        view.autoenablesDefaultLighting = false
        view.isJitteringEnabled = false
        view.isAccessibilityElement = true
        view.accessibilityLabel = "Street View panorama"
        view.accessibilityIdentifier = "street-view-pano"

        camera.fieldOfView = 75
        camera.projectionDirection = .horizontal
        camera.zNear = 0.05
        camera.zFar = 20
        camera.wantsHDR = false
        cameraNode.camera = camera
        cameraNode.position = SCNVector3Zero
        scene.rootNode.addChildNode(cameraNode)
        scene.rootNode.addChildNode(baseNode)
        scene.rootNode.addChildNode(detailNode)
        baseNode.renderingOrder = 0
        detailNode.renderingOrder = 1
        view.pointOfView = cameraNode

        updateCamera(yawDeg: 0, pitchDeg: 0, fovDeg: 75)
    }

    func setPano(_ pano: StreetViewPano) {
        guard panoId != pano.panoId else { return }
        panoId = pano.panoId
        panoHeading = pano.headingDeg
        baseNode.geometry = nil
        baseImage = nil
        detailNode.childNodes.forEach { $0.removeFromParentNode() }
        detailKeys = []
        detailImages = [:]
        detailLevel = nil
    }

    func setBase(_ image: UIImage?) {
        guard let image, image !== baseImage else { return }
        baseImage = image
        let geometry = Self.sphereGeometry(radius: Self.baseRadius)
        geometry.firstMaterial = Self.material(image, wrapS: .repeat)
        baseNode.geometry = geometry
    }

    func setDetail(_ images: [StreetViewTileKey: UIImage], level: StreetViewLevel?) {
        guard let level else { return }
        detailLevel = (level.zoom, level.columns, level.rows)
        detailImages = images
        let keys = Set(images.keys)
        guard keys != detailKeys else { return }
        detailKeys = keys

        detailNode.childNodes.forEach { $0.removeFromParentNode() }
        let columns = max(1, Int(level.columns))
        let rows = max(1, Int(level.rows))
        for (key, image) in images {
            let geometry = Self.tileGeometry(
                radius: Self.detailRadius,
                x: Int(key.x), y: Int(key.y), columns: columns, rows: rows)
            geometry.firstMaterial = Self.material(image, wrapS: .clamp)
            let node = SCNNode(geometry: geometry)
            detailNode.addChildNode(node)
        }
    }

    func updateCamera(yawDeg: Double, pitchDeg: Double, fovDeg: Double) {
        let yaw = yawDeg * .pi / 180
        let pitch = pitchDeg * .pi / 180
        let dx = Float(cos(pitch) * sin(yaw))
        let dy = Float(sin(pitch))
        let dz = Float(-cos(pitch) * cos(yaw))
        let direction = SCNVector3(x: dx, y: dy, z: dz)
        cameraNode.look(at: direction, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        camera.fieldOfView = CGFloat(fovDeg)
        view.setNeedsDisplay()
    }

    func clear() {
        panoId = nil
        baseNode.geometry = nil
        baseImage = nil
        detailNode.childNodes.forEach { $0.removeFromParentNode() }
        detailKeys = []
        detailImages = [:]
        detailLevel = nil
    }

    // MARK: Geometry

    /// An equirectangular sphere seen from inside. Texture u follows image u (a flipped U would
    /// mirror signage), v is flipped because SceneKit's texture origin is the image's bottom left.
    private static func sphereGeometry(radius: CGFloat) -> SCNGeometry {
        let slices = 64
        let stacks = 32
        let r = Float(radius)
        var vertices: [SCNVector3] = []
        var uvs: [Float] = []
        var indices: [Int32] = []
        for i in 0...stacks {
            let v = Double(i) / Double(stacks)
            let phi = Double.pi * v
            for j in 0...slices {
                let u = Double(j) / Double(slices)
                let theta = 2 * Double.pi * u
                let px = r * Float(sin(phi) * cos(theta))
                let py = r * Float(cos(phi))
                let pz = r * Float(sin(phi) * sin(theta))
                vertices.append(SCNVector3(x: px, y: py, z: pz))
                uvs.append(Float(u))
                uvs.append(Float(1 - v))
            }
        }
        let row = slices + 1
        for i in 0..<stacks {
            for j in 0..<slices {
                let a = Int32(i * row + j)
                let b = Int32((i + 1) * row + j)
                let c = Int32(i * row + j + 1)
                let d = Int32((i + 1) * row + j + 1)
                indices.append(contentsOf: [a, b, c, c, b, d])
            }
        }
        return geometry(vertices: vertices, uvs: uvs, indices: indices)
    }

    /// One tile's patch: a flat quad whose corners sit on the sphere at the tile's equirect
    /// rectangle. Four corners are enough at this subdivision; the sagitta is under a pixel.
    private static func tileGeometry(
        radius: CGFloat, x: Int, y: Int, columns: Int, rows: Int
    ) -> SCNGeometry {
        let u0 = Double(x) / Double(columns)
        let u1 = Double(x + 1) / Double(columns)
        let v0 = Double(y) / Double(rows)
        let v1 = Double(y + 1) / Double(rows)
        let r = Float(radius)
        func point(_ u: Double, _ v: Double) -> SCNVector3 {
            let phi = Double.pi * v
            let theta = 2 * Double.pi * u
            let px = r * Float(sin(phi) * cos(theta))
            let py = r * Float(cos(phi))
            let pz = r * Float(sin(phi) * sin(theta))
            return SCNVector3(x: px, y: py, z: pz)
        }
        let vertices = [point(u0, v0), point(u1, v0), point(u0, v1), point(u1, v1)]
        let uvs: [Float] = [0, 1, 1, 1, 0, 0, 1, 0]
        let indices: [Int32] = [0, 2, 1, 1, 2, 3]
        return geometry(vertices: vertices, uvs: uvs, indices: indices)
    }

    private static func geometry(vertices: [SCNVector3], uvs: [Float],
                                 indices: [Int32]) -> SCNGeometry {
        let positionSource = SCNGeometrySource(vertices: vertices)
        let uvData = uvs.withUnsafeBufferPointer { Data(buffer: $0) }
        let uvSource = SCNGeometrySource(
            data: uvData, semantic: .texcoord, vectorCount: uvs.count / 2,
            usesFloatComponents: true, componentsPerVector: 2,
            bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0,
            dataStride: MemoryLayout<Float>.size * 2)
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        return SCNGeometry(sources: [positionSource, uvSource], elements: [element])
    }

    private static func material(_ image: UIImage, wrapS: SCNWrapMode) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = image
        material.diffuse.wrapS = wrapS
        material.diffuse.wrapT = .clamp
        material.diffuse.magnificationFilter = .linear
        material.diffuse.minificationFilter = .linear
        material.diffuse.mipFilter = .linear
        material.lightingModel = .constant
        material.isDoubleSided = true
        material.writesToDepthBuffer = true
        return material
    }
}
