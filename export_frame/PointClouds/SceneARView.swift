import SwiftUI
import ARKit
import SceneKit

/// A SwiftUI wrapper providing an `ARSCNView` that updates a `ScenePointCloudNode`
/// from ARKit's `rawFeaturePoints` each frame. This is a drop-in alternative to
/// the existing Metal `MTKView` approach for visualizing point clouds with SceneKit.
struct SceneARView: UIViewRepresentable {
    @ObservedObject var manager: ARDataDelegate

    func makeCoordinator() -> Coordinator {
        Coordinator(manager: manager)
    }

    func makeUIView(context: Context) -> ARSCNView {
        let arView = ARSCNView(frame: .zero)
        arView.automaticallyUpdatesLighting = false
        arView.autoenablesDefaultLighting = false

        // Attach the ARSession if manager provides one; otherwise use a new session
        if let session = manager.arSession {
            arView.session = session
        } else {
            arView.session = ARSession()
        }

        arView.delegate = context.coordinator
        arView.session.delegate = context.coordinator
        arView.scene = SCNScene()

        // Add the point-cloud node into the scene
        arView.scene.rootNode.addChildNode(context.coordinator.pointNode)

        return arView
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        // Propagate settings from manager if you have any (e.g., thresholds)
        // Example: set scene background to clear
        uiView.backgroundColor = .clear
    }

    class Coordinator: NSObject, ARSCNViewDelegate, ARSessionDelegate {
        var manager: ARDataDelegate
        let pointNode = ScenePointCloudNode()

        init(manager: ARDataDelegate) {
            self.manager = manager
            super.init()
        }

        // ARSessionDelegate - called each frame
        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            // Prefer the renderer's accumulated point cloud when available so SceneKit mirrors Metal output.
            if let renderer = manager.renderer {
                let (positions, colors) = renderer.snapshotPointCloud()
                if positions.isEmpty {
                    DispatchQueue.main.async { [weak self] in
                        self?.pointNode.geometry = nil
                    }
                } else {
                    DispatchQueue.main.async { [weak self] in
                        self?.pointNode.update(points: positions, colors: colors)
                    }
                }
                return
            }

            // Fallback: use ARKit's built-in rawFeaturePoints
            if let raw = frame.rawFeaturePoints, raw.points.count > 0 {
                let count = Int(raw.points.count)
                let buffer = UnsafeBufferPointer(start: raw.points, count: count)
                let pointArray: [SIMD3<Float>] = buffer.map { SIMD3<Float>($0.x, $0.y, $0.z) }

                DispatchQueue.main.async { [weak self] in
                    self?.pointNode.update(points: pointArray, colors: nil)
                }
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.pointNode.geometry = nil
                }
            }
        }
    }
}
