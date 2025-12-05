/*
 See LICENSE folder for this sample’s licensing information.
 
 Abstract:
 The host app renderer.
 */

import Metal
import MetalKit
import ARKit
import Foundation
import UIKit
import CoreGraphics

// MARK: - Helper Structs
struct SimpleVertex {
    var position: SIMD3<Float>
    var color: SIMD4<Float>
}

fileprivate func getCameraDirectory() throws -> URL {
    let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let directoryName = "Camera"
    let directoryUrl = documentDirectory.appendingPathComponent(directoryName)
    if !FileManager.default.fileExists(atPath: directoryUrl.path) {
        try FileManager.default.createDirectory(at: directoryUrl, withIntermediateDirectories: true, attributes: nil)
    }
    return directoryUrl
}

final class Renderer {
    
    // MARK: - Configuration & State
    public var isRecording = true
    public var currentFolder = ""
    public var pickFrames = 5
    public var currentFrameIndex = 0
    public weak var delegate: TaskDelegate?
    
    // Settings
    private let maxPoints = 1_000_000
    private let numGridPoints = 500
    private let particleSize: Float = 10
    private let orientation = UIInterfaceOrientation.portrait
    private let maxInFlightBuffers = 3
    private let maxPyramids = 500
    
    // Thresholds
    private let cameraRotationThreshold = cos(2 * .degreesToRadian)
    private let cameraTranslationThreshold: Float = pow(0.02, 2)
    
    // User Interaction (Rotation/Zoom)
    public var scaleFactor: Float = 1.0 {
        didSet { scaleFactor = max(0.1, min(10.0, scaleFactor)) }
    }
    private var rotationX: Float = 0
    private var rotationY: Float = 0
    private var userRotationMatrix: matrix_float4x4 = matrix_identity_float4x4
    
    // Shader Interfaces
    var confidenceThreshold = 1 {
        didSet { pointCloudUniforms.confidenceThreshold = Int32(confidenceThreshold) }
    }
    var rgbRadius: Float = 0 {
        didSet { rgbUniforms.radius = rgbRadius }
    }
    
    // MARK: - Metal Objects
    private let device: MTLDevice
    private let library: MTLLibrary
    private let commandQueue: MTLCommandQueue
    private let renderDestination: RenderDestinationProvider
    private let inFlightSemaphore: DispatchSemaphore
    
    // Pipelines
    private let relaxedStencilState: MTLDepthStencilState
    private let depthStencilState: MTLDepthStencilState
    private lazy var unprojectPipelineState = makePipeline(vertex: "unprojectVertex", fragment: nil) // Compute/Vertex only
    private lazy var rgbPipelineState = makePipeline(vertex: "rgbVertex", fragment: "rgbFragment")
    private lazy var particlePipelineState = makePipeline(vertex: "particleVertex", fragment: "particleFragment", blending: true)
    private lazy var pyramidPipelineState = makePipeline(vertex: "geometryVertex", fragment: "geometryFragment", blending: true)
    
    // Texture Cache
    private lazy var textureCache = makeTextureCache()
    private var capturedImageTextureY: CVMetalTexture?
    private var capturedImageTextureCbCr: CVMetalTexture?
    private var depthTexture: CVMetalTexture?
    private var confidenceTexture: CVMetalTexture?
    
    // MARK: - Buffers
    private var currentBufferIndex = 0
    private lazy var gridPointsBuffer = MetalBuffer<Float2>(device: device, array: makeGridPoints(), index: kGridPoints.rawValue, options: [])
    private var rgbUniformsBuffers = [MetalBuffer<RGBUniforms>]()
    private var pointCloudUniformsBuffers = [MetalBuffer<PointCloudUniforms>]()
    private var particlesBuffer: MetalBuffer<ParticleUniforms>
    
    // Pyramid Buffers
    private var pyramidVertexBuffer: MTLBuffer!
    private var pyramidVertexCount: Int = 0
    private var cameraHistoryTransforms: [matrix_float4x4] = []
    
    // MARK: - AR Data
    private let session: ARSession
    private var viewportSize = CGSize()
    private var currentPointIndex = 0
    private var currentPointCount = 0
    
    private var sampleFrame: ARFrame { session.currentFrame! }
    private lazy var cameraResolution = Float2(Float(sampleFrame.camera.imageResolution.width), Float(sampleFrame.camera.imageResolution.height))
    private lazy var viewToCamera = sampleFrame.displayTransform(for: orientation, viewportSize: viewportSize).inverted()
    private lazy var lastCameraTransform = sampleFrame.camera.transform
    private lazy var rotateToARCamera = Self.makeRotateToARCameraMatrix(orientation: orientation)
    
    private let overlapCalculator: OverlapCalculator = FovOverlapCalculator()
    
    // MARK: - Uniforms Local Cache
    private lazy var rgbUniforms: RGBUniforms = {
        var uniforms = RGBUniforms()
        uniforms.radius = rgbRadius
        uniforms.viewToCamera.copy(from: viewToCamera)
        uniforms.viewRatio = Float(viewportSize.width / viewportSize.height)
        return uniforms
    }()
    
    private lazy var pointCloudUniforms: PointCloudUniforms = {
        var uniforms = PointCloudUniforms()
        uniforms.maxPoints = Int32(maxPoints)
        uniforms.confidenceThreshold = Int32(confidenceThreshold)
        uniforms.particleSize = particleSize
        uniforms.cameraResolution = cameraResolution
        return uniforms
    }()

    // MARK: - Initialization
    init(session: ARSession, metalDevice device: MTLDevice, renderDestination: MTKView) {
        self.session = session
        self.device = device
        self.renderDestination = renderDestination
        
        guard let lib = device.makeDefaultLibrary(),
              let queue = device.makeCommandQueue() else {
            fatalError("Failed to create Metal library or queue")
        }
        self.library = lib
        self.commandQueue = queue
        
        // Initialize buffers
        for _ in 0 ..< maxInFlightBuffers {
            rgbUniformsBuffers.append(.init(device: device, count: 1, index: 0))
            pointCloudUniformsBuffers.append(.init(device: device, count: 1, index: kPointCloudUniforms.rawValue))
        }
        particlesBuffer = .init(device: device, count: maxPoints, index: kParticleUniforms.rawValue)
        
        // Stencil/Depth States
        let relaxedDescriptor = MTLDepthStencilDescriptor()
        self.relaxedStencilState = device.makeDepthStencilState(descriptor: relaxedDescriptor)!
        
        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .lessEqual
        depthDescriptor.isDepthWriteEnabled = true
        self.depthStencilState = device.makeDepthStencilState(descriptor: depthDescriptor)!
        
        self.inFlightSemaphore = DispatchSemaphore(value: maxInFlightBuffers)
        
        // Initialize Pyramid Geometry
        (self.pyramidVertexBuffer, self.pyramidVertexCount) = Self.makePyramidBuffer(device: device)
    }
    
    // MARK: - Public Methods
    func drawRectResized(size: CGSize) {
        viewportSize = size
        rgbUniforms.viewRatio = Float(viewportSize.width / viewportSize.height)
    }
    
    public func rotate(byX deltaX: Float, y deltaY: Float) {
        rotationX += deltaY
        rotationY += deltaX
        rotationX = max(-Float.pi / 2, min(Float.pi / 2, rotationX))
        
        let rotationMatrixX = matrix_float4x4(simd_quaternion(rotationX, SIMD3<Float>(1, 0, 0)))
        let rotationMatrixY = matrix_float4x4(simd_quaternion(rotationY, SIMD3<Float>(0, 1, 0)))
        userRotationMatrix = rotationMatrixX * rotationMatrixY
    }
    
    public func zoom(by scaleDelta: Float) {
        scaleFactor *= scaleDelta
    }
    
    // MARK: - Main Loop
    func draw() {
        guard let currentFrame = session.currentFrame,
              let renderDescriptor = renderDestination.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderDescriptor) else {
            return
        }
        
        // Synchronization
        _ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)
        commandBuffer.addCompletedHandler { [weak self] _ in
            self?.inFlightSemaphore.signal()
        }
        
        // 1. Update Data (Matrices, Textures)
        update(frame: currentFrame)
        updateCapturedImageTextures(frame: currentFrame)
        
        currentBufferIndex = (currentBufferIndex + 1) % maxInFlightBuffers
        pointCloudUniformsBuffers[currentBufferIndex][0] = pointCloudUniforms
        
        // 2. Accumulate Logic (Point Cloud & Camera Trail)
        handleAccumulation(frame: currentFrame, commandBuffer: commandBuffer, renderEncoder: renderEncoder)
        
        // 3. Render Passes
        // A. Background
        drawBackgroundRGB(renderEncoder: renderEncoder)
        
        // B. Point Cloud
        drawPointCloud(renderEncoder: renderEncoder)
        
        // C. Camera Trail (Pyramids)
        drawCameraTrails(renderEncoder: renderEncoder)
        
        // Finish
        renderEncoder.endEncoding()
        commandBuffer.present(renderDestination.currentDrawable!)
        commandBuffer.commit()
    }
    
    // MARK: - Logic & Updates
    
    private func update(frame: ARFrame) {
        let camera = frame.camera
        let viewMatrix = camera.viewMatrix(for: orientation)
        let projectionMatrix = camera.projectionMatrix(for: orientation, viewportSize: viewportSize, zNear: 0.001, zFar: 0)
        
        let scaleMatrix = matrix_float4x4(diagonal: simd_float4(scaleFactor, scaleFactor, scaleFactor, 1))
        
        // Apply User Rotation & Scale to ViewProjection
        let rotatedViewProjectionMatrix = (projectionMatrix * viewMatrix) * userRotationMatrix * scaleMatrix
        
        pointCloudUniforms.viewProjectionMatrix = rotatedViewProjectionMatrix
        pointCloudUniforms.localToWorld = viewMatrix.inverse * rotateToARCamera
        pointCloudUniforms.cameraIntrinsicsInversed = camera.intrinsics.inverse
    }
    
    private func handleAccumulation(frame: ARFrame, commandBuffer: MTLCommandBuffer, renderEncoder: MTLRenderCommandEncoder) {
        var shouldAccumulatePoints = false
        
        // Calculate Overlap
        if let lastFrameCache = ImageProcessor.shared.lastFrameCache, let lastFrame = lastFrameCache.frame {
            let distance = overlapCalculator.calculateDynamicDistance(frame.sceneDepth?.depthMap)
            let pointsCount = frame.rawFeaturePoints?.points.count ?? 0
            
            let overlapRatio: CGFloat
            if pointsCount <= 250 {
                overlapRatio = overlapCalculator.calculateFromFov(lastFrame, frame, distance)
            } else {
                overlapRatio = overlapCalculator.calculateFromFeaturePoints(lastFrame, frame, distance)
            }
            
            if overlapRatio <= 0.9 { shouldAccumulatePoints = true }
        } else {
            shouldAccumulatePoints = true // First frame
        }
        
        // Execute Accumulation if needed
        if shouldAccumulatePoints, shouldAccumulate(frame: frame), updateDepthTextures(frame: frame) {
            
            // 1. Accumulate Points
            accumulatePoints(frame: frame, commandBuffer: commandBuffer, renderEncoder: renderEncoder)
            
            // 2. Add to Camera History (Trail)
            if cameraHistoryTransforms.count >= maxPyramids {
                cameraHistoryTransforms.removeFirst()
            }
            cameraHistoryTransforms.append(frame.camera.transform)
            
            // 3. Update Cache
            let fps = session.configuration?.videoFormat.framesPerSecond ?? 0
            ImageProcessor.shared.lastFrameCache = FrameCache(0, frame, fps)
        }
    }
    
    private func shouldAccumulate(frame: ARFrame) -> Bool {
        guard isRecording else { return false }
        
        let cameraTransform = frame.camera.transform
        return currentPointCount == 0
            || dot(cameraTransform.columns.2, lastCameraTransform.columns.2) <= cameraRotationThreshold
            || distance_squared(cameraTransform.columns.3, lastCameraTransform.columns.3) >= cameraTranslationThreshold
    }
    
    private func accumulatePoints(frame: ARFrame, commandBuffer: MTLCommandBuffer, renderEncoder: MTLRenderCommandEncoder) {
        pointCloudUniforms.pointCloudCurrentIndex = Int32(currentPointIndex)
        
        var retainingTextures = [capturedImageTextureY, capturedImageTextureCbCr, depthTexture, confidenceTexture]
        commandBuffer.addCompletedHandler { _ in retainingTextures.removeAll() }
        
        renderEncoder.setDepthStencilState(relaxedStencilState)
        renderEncoder.setRenderPipelineState(unprojectPipelineState!)
        renderEncoder.setVertexBuffer(pointCloudUniformsBuffers[currentBufferIndex])
        renderEncoder.setVertexBuffer(particlesBuffer)
        renderEncoder.setVertexBuffer(gridPointsBuffer)
        
        // Set Textures
        if let y = capturedImageTextureY, let cbcr = capturedImageTextureCbCr, let depth = depthTexture, let conf = confidenceTexture {
            renderEncoder.setVertexTexture(CVMetalTextureGetTexture(y), index: Int(kTextureY.rawValue))
            renderEncoder.setVertexTexture(CVMetalTextureGetTexture(cbcr), index: Int(kTextureCbCr.rawValue))
            renderEncoder.setVertexTexture(CVMetalTextureGetTexture(depth), index: Int(kTextureDepth.rawValue))
            renderEncoder.setVertexTexture(CVMetalTextureGetTexture(conf), index: Int(kTextureConfidence.rawValue))
        }
        
        renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: gridPointsBuffer.count)
        
        currentPointIndex = (currentPointIndex + gridPointsBuffer.count) % maxPoints
        currentPointCount = min(currentPointCount + gridPointsBuffer.count, maxPoints)
        lastCameraTransform = frame.camera.transform
    }

    // MARK: - Drawing Functions
    
    private func drawBackgroundRGB(renderEncoder: MTLRenderCommandEncoder) {
        guard rgbUniforms.radius > 0, let pipe = rgbPipelineState else { return }
        
        rgbUniformsBuffers[currentBufferIndex][0] = rgbUniforms
        
        renderEncoder.setDepthStencilState(relaxedStencilState)
        renderEncoder.setRenderPipelineState(pipe)
        renderEncoder.setVertexBuffer(rgbUniformsBuffers[currentBufferIndex])
        renderEncoder.setFragmentBuffer(rgbUniformsBuffers[currentBufferIndex])
        
        if let y = capturedImageTextureY, let cbcr = capturedImageTextureCbCr {
            renderEncoder.setFragmentTexture(CVMetalTextureGetTexture(y), index: Int(kTextureY.rawValue))
            renderEncoder.setFragmentTexture(CVMetalTextureGetTexture(cbcr), index: Int(kTextureCbCr.rawValue))
            renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
    }
    
    private func drawPointCloud(renderEncoder: MTLRenderCommandEncoder) {
        guard let pipe = particlePipelineState else { return }
        
        renderEncoder.setDepthStencilState(depthStencilState)
        renderEncoder.setRenderPipelineState(pipe)
        renderEncoder.setVertexBuffer(pointCloudUniformsBuffers[currentBufferIndex])
        renderEncoder.setVertexBuffer(particlesBuffer)
        renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: currentPointCount)
    }
    
    private func drawCameraTrails(renderEncoder: MTLRenderCommandEncoder) {
        guard let pipe = pyramidPipelineState, let buffer = pyramidVertexBuffer, !cameraHistoryTransforms.isEmpty else { return }
        
        let viewProjMatrix = pointCloudUniforms.viewProjectionMatrix
        var mvpMatrices: [matrix_float4x4] = []
        mvpMatrices.reserveCapacity(cameraHistoryTransforms.count + 1)
        
        // Historical transforms
        for oldTransform in cameraHistoryTransforms {
            mvpMatrices.append(viewProjMatrix * oldTransform)
        }
        
        // Current camera transform
        if let currentCamTransform = session.currentFrame?.camera.transform {
            mvpMatrices.append(viewProjMatrix * currentCamTransform)
        }
        
        renderEncoder.pushDebugGroup("Draw Pyramids Trail")
        renderEncoder.setRenderPipelineState(pipe)
        renderEncoder.setDepthStencilState(depthStencilState)
        renderEncoder.setVertexBuffer(buffer, offset: 0, index: 0)
        
        // Create Instance Buffer
        let mvpBufferSize = mvpMatrices.count * MemoryLayout<matrix_float4x4>.stride
        if let instanceBuffer = device.makeBuffer(bytes: mvpMatrices, length: mvpBufferSize, options: []) {
            renderEncoder.setVertexBuffer(instanceBuffer, offset: 0, index: 1)
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: pyramidVertexCount, instanceCount: mvpMatrices.count)
        }
        renderEncoder.popDebugGroup()
    }
    
    // MARK: - Texture & Helpers
    
    private func updateCapturedImageTextures(frame: ARFrame) {
        let pixelBuffer = frame.capturedImage
        guard CVPixelBufferGetPlaneCount(pixelBuffer) >= 2 else { return }
        capturedImageTextureY = makeTexture(fromPixelBuffer: pixelBuffer, pixelFormat: .r8Unorm, planeIndex: 0)
        capturedImageTextureCbCr = makeTexture(fromPixelBuffer: pixelBuffer, pixelFormat: .rg8Unorm, planeIndex: 1)
    }
    
    private func updateDepthTextures(frame: ARFrame) -> Bool {
        guard let depthMap = frame.sceneDepth?.depthMap,
              let confidenceMap = frame.sceneDepth?.confidenceMap else { return false }
        depthTexture = makeTexture(fromPixelBuffer: depthMap, pixelFormat: .r32Float, planeIndex: 0)
        confidenceTexture = makeTexture(fromPixelBuffer: confidenceMap, pixelFormat: .r8Uint, planeIndex: 0)
        return true
    }
    
    func snapshotPointCloud() -> ([SIMD3<Float>], [SIMD3<Float>]) {
        var positions: [SIMD3<Float>] = []
        var colors: [SIMD3<Float>] = []
        positions.reserveCapacity(currentPointCount)
        colors.reserveCapacity(currentPointCount)
        for i in 0..<currentPointCount {
            let p = particlesBuffer[i]
            positions.append(p.position)
            colors.append(p.color)
        }
        return (positions, colors)
    }
    
    func savePointCloud() {
        delegate?.didStartTask()
        Task.init(priority: .utility) {
            do {
                var fileToWrite = ""
                let headers = ["ply", "format ascii 1.0", "element vertex \(currentPointCount)", "property float x", "property float y", "property float z", "property uchar red", "property uchar green", "property uchar blue", "element face 0", "property list uchar int vertex_indices", "end_header"]
                headers.forEach { fileToWrite += $0 + "\r\n" }
                
                for i in 0..<currentPointCount {
                    let point = particlesBuffer[i]
                    let c = point.color * 255.0
                    fileToWrite += "\(point.position.x) \(point.position.y) \(point.position.z) \(Int(c.x)) \(Int(c.y)) \(Int(c.z))\r\n"
                }
                
                try await saveFile(content: fileToWrite, filename: "\(getTimeStr()).ply", folder: currentFolder)
                delegate?.didFinishTask()
            } catch {
                print(error.localizedDescription)
            }
        }
    }
    
    // MARK: - Pipeline & Geometry Construction
    
    /// Generic function to create pipelines, reducing boilerplate
    private func makePipeline(vertex: String, fragment: String?, blending: Bool = false) -> MTLRenderPipelineState? {
        guard let vertexFunc = library.makeFunction(name: vertex) else { return nil }
        
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunc
        if let frag = fragment {
            descriptor.fragmentFunction = library.makeFunction(name: frag)
        } else {
            descriptor.isRasterizationEnabled = false // For compute/unproject pass
        }
        
        descriptor.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        descriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
        
        if blending {
            let attachment = descriptor.colorAttachments[0]
            attachment?.isBlendingEnabled = true
            attachment?.sourceRGBBlendFactor = .sourceAlpha
            attachment?.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment?.sourceAlphaBlendFactor = .sourceAlpha
            attachment?.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        }
        
        // Special case for Geometry (Pyramid) to add Vertex Descriptor
        if vertex == "geometryVertex" {
            let vertexDescriptor = MTLVertexDescriptor()
            vertexDescriptor.attributes[0].format = .float3 // Pos
            vertexDescriptor.attributes[0].offset = 0
            vertexDescriptor.attributes[0].bufferIndex = 0
            vertexDescriptor.attributes[1].format = .float4 // Color
            vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
            vertexDescriptor.attributes[1].bufferIndex = 0
            vertexDescriptor.layouts[0].stride = MemoryLayout<SimpleVertex>.stride
            descriptor.vertexDescriptor = vertexDescriptor
        }
        
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }
    
    // Static helper for Geometry
    private static func makePyramidBuffer(device: MTLDevice) -> (MTLBuffer?, Int) {
        let color = SIMD4<Float>(0, 0, 1, 0.4)
        let w: Float = 0.05, h: Float = 0.05, d: Float = 0.15
        let apex = SIMD3<Float>(0, 0, 0)
        let v0 = SIMD3<Float>(-w, -h, -d), v1 = SIMD3<Float>(w, -h, -d)
        let v2 = SIMD3<Float>(w, h, -d), v3 = SIMD3<Float>(-w, h, -d)
        
        let vertices: [SimpleVertex] = [
            SimpleVertex(position: apex, color: color), SimpleVertex(position: v0, color: color), SimpleVertex(position: v1, color: color),
            SimpleVertex(position: apex, color: color), SimpleVertex(position: v1, color: color), SimpleVertex(position: v2, color: color),
            SimpleVertex(position: apex, color: color), SimpleVertex(position: v2, color: color), SimpleVertex(position: v3, color: color),
            SimpleVertex(position: apex, color: color), SimpleVertex(position: v3, color: color), SimpleVertex(position: v0, color: color),
            SimpleVertex(position: v0, color: color), SimpleVertex(position: v2, color: color), SimpleVertex(position: v1, color: color),
            SimpleVertex(position: v0, color: color), SimpleVertex(position: v3, color: color), SimpleVertex(position: v2, color: color)
        ]
        
        let buffer = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<SimpleVertex>.stride, options: [])
        return (buffer, vertices.count)
    }

    // MARK: - Utility Functions
    
    private func makeGridPoints() -> [Float2] {
        let gridArea = cameraResolution.x * cameraResolution.y
        let spacing = sqrt(gridArea / Float(numGridPoints))
        let deltaX = Int(round(cameraResolution.x / spacing))
        let deltaY = Int(round(cameraResolution.y / spacing))
        
        var points = [Float2]()
        for gridY in 0 ..< deltaY {
            let alternatingOffsetX = Float(gridY % 2) * spacing / 2
            for gridX in 0 ..< deltaX {
                let cameraPoint = Float2(alternatingOffsetX + (Float(gridX) + 0.5) * spacing, (Float(gridY) + 0.5) * spacing)
                points.append(cameraPoint)
            }
        }
        return points
    }
    
    private func makeTextureCache() -> CVMetalTextureCache {
        var cache: CVMetalTextureCache!
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        return cache
    }
    
    private func makeTexture(fromPixelBuffer pixelBuffer: CVPixelBuffer, pixelFormat: MTLPixelFormat, planeIndex: Int) -> CVMetalTexture? {
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, planeIndex)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, planeIndex)
        var texture: CVMetalTexture? = nil
        let status = CVMetalTextureCacheCreateTextureFromImage(nil, textureCache, pixelBuffer, nil, pixelFormat, width, height, planeIndex, &texture)
        return status == kCVReturnSuccess ? texture : nil
    }
    
    static func makeRotateToARCameraMatrix(orientation: UIInterfaceOrientation) -> matrix_float4x4 {
        let flipYZ = matrix_float4x4([1,0,0,0], [0,-1,0,0], [0,0,-1,0], [0,0,0,1])
        let rotationAngle: Float = (orientation == .landscapeLeft ? 180 : (orientation == .portrait ? 90 : (orientation == .portraitUpsideDown ? -90 : 0))) * .degreesToRadian
        return flipYZ * matrix_float4x4(simd_quaternion(rotationAngle, Float3(0, 0, 1)))
    }
}
