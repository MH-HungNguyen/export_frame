import Foundation
import SceneKit
import simd
import UIKit

/// A lightweight SCNNode that renders a point cloud using SceneKit geometry (.point).
/// - Call `update(points:colors:)` from the AR frame or your renderer to refresh points.
final class ScenePointCloudNode: SCNNode {

    override init() {
        super.init()
        // no-op; geometry is created on update
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    /// Update geometry with new points and optional colors.
    /// - Parameters:
    ///   - points: Array of SIMD3<Float> coordinates in world space (or node-local if you transform them).
    ///   - colors: Optional array of SIMD3<Float> RGB values in 0..1 matching `points.count`.
    func update(points: [SIMD3<Float>], colors: [SIMD3<Float>]? = nil) {
        guard !points.isEmpty else {
            self.geometry = nil
            return
        }

        // Build vertex data
        let vertexData: Data = points.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return Data() }
            return Data(bytes: base, count: buf.count * MemoryLayout<SIMD3<Float>>.stride)
        }

        let vertexSource = SCNGeometrySource(data: vertexData,
                                             semantic: .vertex,
                                             vectorCount: points.count,
                                             usesFloatComponents: true,
                                             componentsPerVector: 3,
                                             bytesPerComponent: MemoryLayout<Float>.size,
                                             dataOffset: 0,
                                             dataStride: MemoryLayout<SIMD3<Float>>.stride)

        var sources: [SCNGeometrySource] = [vertexSource]

        // Optional color source
        if let colors = colors, colors.count == points.count {
            let colorData: Data = colors.withUnsafeBufferPointer { buf in
                guard let base = buf.baseAddress else { return Data() }
                return Data(bytes: base, count: buf.count * MemoryLayout<SIMD3<Float>>.stride)
            }

            let colorSource = SCNGeometrySource(data: colorData,
                                                semantic: .color,
                                                vectorCount: colors.count,
                                                usesFloatComponents: true,
                                                componentsPerVector: 3,
                                                bytesPerComponent: MemoryLayout<Float>.size,
                                                dataOffset: 0,
                                                dataStride: MemoryLayout<SIMD3<Float>>.stride)
            sources.append(colorSource)
        }

        // Indices (0..n-1)
        let indices: [UInt32] = (0..<points.count).map { UInt32($0) }
        let indexData: Data = indices.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return Data() }
            return Data(bytes: base, count: buf.count * MemoryLayout<UInt32>.size)
        }

        let element = SCNGeometryElement(data: indexData,
                                         primitiveType: .point,
                                         primitiveCount: points.count,
                                         bytesPerIndex: MemoryLayout<UInt32>.size)

        let geometry = SCNGeometry(sources: sources, elements: [element])

        // Material: constant lighting so colors show without scene lights
        let mat = SCNMaterial()
        mat.lightingModel = .constant
        mat.isDoubleSided = true
        mat.diffuse.contents = UIColor.white
        mat.readsFromDepthBuffer = false
        // You can tweak point size by setting the SCNView's `pointOfView`/renderer settings or
        // by using a custom SCNProgram; for many use-cases the default is OK.

        geometry.materials = [mat]

        self.geometry = geometry
    }
}
