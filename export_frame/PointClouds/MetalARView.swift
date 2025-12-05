import SwiftUI
import MetalKit
import ARKit

// MARK: - RenderDestinationProvider Protocol
protocol RenderDestinationProvider {
    var currentRenderPassDescriptor: MTLRenderPassDescriptor? { get }
    var currentDrawable: CAMetalDrawable? { get }
    var colorPixelFormat: MTLPixelFormat { get set }
    var depthStencilPixelFormat: MTLPixelFormat { get set }
    var sampleCount: Int { get set }
}

// Extension to make MTKView conform to the protocol
extension MTKView: RenderDestinationProvider {}

// MARK: - SwiftUI View Wrapper
struct MetalARView: UIViewRepresentable {
    
    @ObservedObject var manager: ARDataDelegate
    
    // Ensure device exists, otherwise app likely cannot run AR anyway
    private let metalDevice = MTLCreateSystemDefaultDevice()
    
    func makeCoordinator() -> Coordinator {
        Coordinator(manager: manager)
    }

    func makeUIView(context: Context) -> MTKView {
        guard let device = metalDevice else {
            fatalError("Metal is not supported on this device")
        }
        
        let view = MTKView()
        view.device = device
        view.backgroundColor = .clear
        view.depthStencilPixelFormat = .depth32Float
        view.contentScaleFactor = 1
        view.delegate = context.coordinator
        
        // Setup Gesture Recognizers
        setupGestures(for: view, context: context)
        
        // Initialize Renderer
        if let arSession = manager.arSession {
            let renderer = Renderer(session: arSession, metalDevice: device, renderDestination: view)
            renderer.delegate = manager as TaskDelegate
            renderer.drawRectResized(size: view.bounds.size)
            manager.renderer = renderer
        }
        
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        // Sync UI state to Renderer
        guard let renderer = manager.renderer else { return }
        renderer.confidenceThreshold = manager.confidenceThreshold
        renderer.rgbRadius = manager.rgbRadius
        renderer.pickFrames = manager.pickFrames
    }
    
    private func setupGestures(for view: UIView, context: Context) {
        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(gesture:)))
        let pinchGesture = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(gesture:)))
        
        view.addGestureRecognizer(panGesture)
        view.addGestureRecognizer(pinchGesture)
    }

    // MARK: - Coordinator
    class Coordinator: NSObject, MTKViewDelegate {
        var manager: ARDataDelegate
        
        // Sensitivity configuration
        private let panSensitivity: Float = 0.005

        init(manager: ARDataDelegate) {
            self.manager = manager
        }

        // MARK: MTKViewDelegate
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            manager.renderer?.drawRectResized(size: size)
        }
        
        func draw(in view: MTKView) {
            manager.renderer?.draw()
        }
        
        // MARK: Gesture Handlers
        @objc func handlePan(gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view else { return }
            let translation = gesture.translation(in: view)
            
            // Calculate delta values
            let deltaX = Float(translation.x) * panSensitivity
            let deltaY = Float(translation.y) * panSensitivity
            
            // Update Renderer
            manager.renderer?.rotate(byX: deltaX, y: deltaY)
            
            // Reset translation to handle incremental changes
            gesture.setTranslation(.zero, in: view)
        }
        
        @objc func handlePinch(gesture: UIPinchGestureRecognizer) {
            // Update Renderer with the scale delta
            // Note: renderer.zoom should multiply its current scale by this delta
            manager.renderer?.zoom(by: Float(gesture.scale))
            
            // Reset scale to 1.0 to handle incremental changes
            gesture.scale = 1.0
        }
    }
}
