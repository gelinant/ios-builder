// Metal pipeline shared by the two routes: a MapLibre custom style layer (inside the map render
// pass) and a sibling MTKView drawn above the map. The shaders are the same in both cases.
import MapLibre
import Metal
import MetalKit
import UIKit

struct TerrainUniforms {
    var matrix: simd_float4x4
    var worldSize: Float
    var metersPerUnit: Float
    var pad: SIMD2<Float>
    var light: SIMD4<Float>
}

final class TerrainRenderer {
    let device: MTLDevice
    private(set) var vertexBuffer: MTLBuffer?
    private(set) var indexBuffer: MTLBuffer?
    private(set) var indexCount = 0
    private(set) var mesh: TerrainMesh?
    private(set) var uploadMilliseconds = 0.0

    private let contextLock = NSLock()
    private var storedContext: MLNStyleLayerDrawingContext?
    var lastContext: MLNStyleLayerDrawingContext? {
        get {
            contextLock.lock()
            defer { contextLock.unlock() }
            return storedContext
        }
        set {
            contextLock.lock()
            defer { contextLock.unlock() }
            storedContext = newValue
        }
    }

    private var pipeline: MTLRenderPipelineState?
    private var depthState: MTLDepthStencilState?
    private var pipelineColorFormat: MTLPixelFormat = .invalid
    private var pipelineDepthFormat: MTLPixelFormat = .invalid

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexIn {
        float4 positionAndHeight; // x, y in normalized Web Mercator, w in metres
        float4 normal;            // east, south, up
    };

    struct Uniforms {
        float4x4 matrix;
        float worldSize;
        float metersPerUnit;
        float2 pad;
        float4 light;
    };

    struct Raster {
        float4 position [[position]];
        float3 normal;
        float height;
    };

    vertex Raster terrainVertex(uint vid [[vertex_id]],
                                const device VertexIn *vertices [[buffer(0)]],
                                constant Uniforms &u [[buffer(1)]]) {
        VertexIn v = vertices[vid];
        // World Z is in metres: MapLibre's worldToCamera already scales it by pixelsPerMeter.
        float3 world = float3(v.positionAndHeight.x * u.worldSize,
                              v.positionAndHeight.y * u.worldSize,
                              v.positionAndHeight.w);
        Raster out;
        out.position = u.matrix * float4(world, 1.0);
        out.normal = v.normal.xyz;
        out.height = v.positionAndHeight.w;
        return out;
    }

    fragment float4 terrainFragment(Raster in [[stage_in]],
                                    constant Uniforms &u [[buffer(1)]]) {
        float h = in.height;
        float rock = smoothstep(900.0, 2100.0, h);
        float snow = smoothstep(2300.0, 3050.0, h);
        float3 low = float3(0.16, 0.29, 0.15);
        float3 mid = float3(0.42, 0.37, 0.29);
        float3 high = float3(0.94, 0.95, 0.97);
        float3 color = mix(low, mid, rock);
        color = mix(color, high, snow);
        float3 n = normalize(in.normal);
        float3 l = normalize(u.light.xyz);
        float lambert = saturate(dot(n, l));
        float shade = 0.32 + 0.68 * lambert;
        shade *= 0.9 + 0.1 * saturate(h / 3000.0);
        return float4(color * shade, 1.0);
    }
    """

    init(device: MTLDevice) {
        self.device = device
    }

    func setMesh(_ mesh: TerrainMesh) {
        let started = CACurrentMediaTime()
        let vertexLength = mesh.vertices.count * MemoryLayout<TerrainVertex>.stride
        let indexLength = mesh.indices.count * MemoryLayout<UInt32>.stride
        vertexBuffer = mesh.vertices.withUnsafeBufferPointer {
            guard let base = $0.baseAddress else { return nil }
            return device.makeBuffer(bytes: base, length: vertexLength, options: .storageModeShared)
        }
        indexBuffer = mesh.indices.withUnsafeBufferPointer {
            guard let base = $0.baseAddress else { return nil }
            return device.makeBuffer(bytes: base, length: indexLength, options: .storageModeShared)
        }
        indexCount = mesh.indices.count
        self.mesh = mesh
        uploadMilliseconds = (CACurrentMediaTime() - started) * 1000
        log("upload \(mesh.gridVerticesPerSide) grid: vb \(vertexLength) ib \(indexLength) in \(String(format: "%.1f", uploadMilliseconds)) ms")
    }

    /// Builds the pipeline against the formats of the pass it will actually draw into. MapLibre's
    /// main pass uses depth32Float_stencil8 and a BGRA8 colour target; reading them avoids a
    /// pipeline that validates but never draws.
    func preparePipeline(renderPass: MTLRenderPassDescriptor) {
        let colorFormat = renderPass.colorAttachments[0].texture?.pixelFormat ?? .bgra8Unorm
        let depthFormat = renderPass.depthAttachment.texture?.pixelFormat ?? .invalid
        if pipeline != nil, pipelineColorFormat == colorFormat, pipelineDepthFormat == depthFormat {
            return
        }
        do {
            let library = try device.makeLibrary(source: Self.shaderSource, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.label = "terrain"
            descriptor.vertexFunction = library.makeFunction(name: "terrainVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "terrainFragment")
            descriptor.colorAttachments[0].pixelFormat = colorFormat
            if depthFormat != .invalid {
                descriptor.depthAttachmentPixelFormat = depthFormat
                if depthFormat == .depth32Float_stencil8 {
                    descriptor.stencilAttachmentPixelFormat = depthFormat
                }
            }
            pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
            if depthFormat != .invalid {
                let depthDescriptor = MTLDepthStencilDescriptor()
                depthDescriptor.depthCompareFunction = .lessEqual
                depthDescriptor.isDepthWriteEnabled = true
                depthState = device.makeDepthStencilState(descriptor: depthDescriptor)
            } else {
                depthState = nil
            }
            pipelineColorFormat = colorFormat
            pipelineDepthFormat = depthFormat
            log("pipeline ready, colour \(colorFormat.rawValue), depth \(depthFormat.rawValue)")
        } catch {
            log("pipeline failed: \(error)")
            pipeline = nil
        }
    }

    func draw(encoder: MTLRenderCommandEncoder, context: MLNStyleLayerDrawingContext) {
        guard let pipeline, let vertexBuffer, let indexBuffer, indexCount > 0 else { return }
        let uniforms = makeUniforms(context: context)
        encoder.setRenderPipelineState(pipeline)
        if let depthState { encoder.setDepthStencilState(depthState) }
        encoder.setCullMode(.none)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        var value = uniforms
        encoder.setVertexBytes(&value, length: MemoryLayout<TerrainUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&value, length: MemoryLayout<TerrainUniforms>.stride, index: 1)
        encoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: indexCount,
            indexType: .uint32,
            indexBuffer: indexBuffer,
            indexBufferOffset: 0
        )
    }

    func makeUniforms(context: MLNStyleLayerDrawingContext) -> TerrainUniforms {
        let zoom = context.zoomLevel
        let worldSize = 512.0 * pow(2.0, zoom)
        let latitude = context.centerCoordinate.latitude * Double.pi / 180
        let metersPerUnit = 40_075_016.686 * max(cos(latitude), 0.01) / worldSize
        return TerrainUniforms(
            matrix: convertMatrix(context.projectionMatrix),
            worldSize: Float(worldSize),
            metersPerUnit: Float(metersPerUnit),
            pad: SIMD2<Float>(0, 0),
            light: SIMD4<Float>(-0.55, -0.45, 0.70, 0)
        )
    }

    func convertMatrix(_ mat: MLNMatrix4) -> simd_float4x4 {
        simd_float4x4(columns: (
            SIMD4<Float>(Float(mat.m00), Float(mat.m01), Float(mat.m02), Float(mat.m03)),
            SIMD4<Float>(Float(mat.m10), Float(mat.m11), Float(mat.m12), Float(mat.m13)),
            SIMD4<Float>(Float(mat.m20), Float(mat.m21), Float(mat.m22), Float(mat.m23)),
            SIMD4<Float>(Float(mat.m30), Float(mat.m31), Float(mat.m32), Float(mat.m33))
        ))
    }
}
