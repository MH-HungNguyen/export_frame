import SwiftUI
import MetalKit

struct MetalARView: UIViewRepresentable {
    
    @ObservedObject var manager: ARDataDelegate
    let metalDevice = MTLCreateSystemDefaultDevice()! // Assumes device exists

    func makeCoordinator() -> Coordinator {
        // Pass the manager to the Coordinator
        Coordinator(manager: manager)
    }

    func makeUIView(context: Context) -> MTKView {
        print("Frank makeUIView MetalARView")
        let view = MTKView()
        
        view.device = metalDevice
        view.backgroundColor = UIColor.clear
        view.depthStencilPixelFormat = .depth32Float
        view.contentScaleFactor = 1
        
        // Assign the Coordinator as the MTKViewDelegate
        view.delegate = context.coordinator
        
        // Initialize the renderer now that we have the device and MTKView
        if let arSession = manager.arSession {
            manager.renderer = Renderer.init(session: arSession, metalDevice: metalDevice, renderDestination: view)
        }
        manager.renderer?.delegate = manager as TaskDelegate // Assign the manager as the TaskDelegate
        
        // Initial size update
        manager.renderer?.drawRectResized(size: view.bounds.size)
        
        // Thêm cử chỉ vào view Metal
        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(context.coordinator.handlePan(gesture:)))
        let pinchGesture = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(context.coordinator.handlePinch(gesture:)))
        
        view.addGestureRecognizer(panGesture)
        view.addGestureRecognizer(pinchGesture)
        
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        // Propagate state changes from the manager to the renderer
        manager.renderer?.confidenceThreshold = manager.confidenceThreshold
        manager.renderer?.rgbRadius = manager.rgbRadius
        manager.renderer?.pickFrames = manager.pickFrames
        
        // In a complex AR app, you might also update the ARConfiguration here.
    }
    
    // The Coordinator holds the MTKViewDelegate logic
    class Coordinator: NSObject, MTKViewDelegate {
        var manager: ARDataDelegate
        
        private var currentRotationX: Float = 0
        private var currentRotationY: Float = 0
        private var currentScale: Float = 1.0
        
        let panSensitivity: Float = 0.005

        init(manager: ARDataDelegate) {
            self.manager = manager
        }

        // MTKViewDelegate - drawableSizeWillChange
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            manager.renderer?.drawRectResized(size: size)
        }
        
        // MTKViewDelegate - draw
        func draw(in view: MTKView) {
            manager.renderer?.draw()
        }
        
        @objc func handlePan(gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: gesture.view)
//            let sensitivity: Float = 0.01 // Độ nhạy xoay
//            
//            // Cập nhật góc quay dựa trên cử chỉ vuốt
//            currentRotationY -= Float(translation.x) * sensitivity
//            currentRotationX -= Float(translation.y) * sensitivity
//            
//            updateDisplayMatrix()
            
            // Tính toán lượng xoay theo radians
            let deltaX = Float(translation.x) * panSensitivity
            let deltaY = Float(translation.y) * panSensitivity
            
            // Gọi hàm xoay trong Renderer
            manager.renderer?.rotate(byX: deltaX, y: deltaY)
            
            // Reset translation sau khi xử lý
            gesture.setTranslation(.zero, in: gesture.view)
        }
        
        @objc func handlePinch(gesture: UIPinchGestureRecognizer) {
            // Xử lý zoom
            currentScale *= Float(gesture.scale)
            currentScale = max(0.1, min(10.0, currentScale)) // Giới hạn zoom
            
            //updateDisplayMatrix()
            manager.renderer?.zoom(by: currentScale)
            
            // Reset scale sau khi xử lý
            gesture.scale = 1.0
        }
        
        private func updateDisplayMatrix() {
            print("Frank updateDisplayMatrix currentScale: \(currentScale), currentRotationX: \(currentRotationX), currentRotationY: \(currentRotationY)")
            // 1. Ma trận Xoay: Tạo ma trận xoay từ các góc quay X và Y
            let rotationX = simd_float4x4(rotation: SIMD3<Float>(currentRotationX, 0, 0))
            let rotationY = simd_float4x4(rotation: SIMD3<Float>(0, currentRotationY, 0))
            
            // 2. Ma trận Scale: Thay đổi tỷ lệ (zoom)
            let scaleMatrix = simd_float4x4(scale: SIMD3<Float>(currentScale, currentScale, currentScale))
            
            // Kết hợp ma trận: Scale * RotationY * RotationX
            //manager.renderer?.displayRotationMatrix = scaleMatrix * rotationY * rotationX
        }
    }
}

// MARK: - RenderDestinationProvider

protocol RenderDestinationProvider {
    var currentRenderPassDescriptor: MTLRenderPassDescriptor? { get }
    var currentDrawable: CAMetalDrawable? { get }
    var colorPixelFormat: MTLPixelFormat { get set }
    var depthStencilPixelFormat: MTLPixelFormat { get set }
    var sampleCount: Int { get set }
}

extension MTKView: RenderDestinationProvider {
    
}

// Hàm tiện ích để tạo ma trận xoay (cần thiết cho SIMD)
extension simd_float4x4 {
    init(rotation angle: SIMD3<Float>) {
        let rotationX = simd_float4x4(
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, cos(angle.x), sin(angle.x), 0),
            SIMD4<Float>(0, -sin(angle.x), cos(angle.x), 0),
            SIMD4<Float>(0, 0, 0, 1)
        )
        
        let rotationY = simd_float4x4(
            SIMD4<Float>(cos(angle.y), 0, -sin(angle.y), 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(sin(angle.y), 0, cos(angle.y), 0),
            SIMD4<Float>(0, 0, 0, 1)
        )
        
        let rotationZ = simd_float4x4(
            SIMD4<Float>(cos(angle.z), sin(angle.z), 0, 0),
            SIMD4<Float>(-sin(angle.z), cos(angle.z), 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(0, 0, 0, 1)
        )
        
        self = rotationX * rotationY * rotationZ
    }
    
    init(scale s: SIMD3<Float>) {
        self = simd_float4x4(diagonal: SIMD4<Float>(s.x, s.y, s.z, 1.0))
    }
}
