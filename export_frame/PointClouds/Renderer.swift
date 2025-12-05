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
    // Whether recording is on
    public var isRecording = true;
    // Current folder for saving data
    public var currentFolder = ""
    // Pick every n frames (~1/sampling frequency)
    public var pickFrames = 5 // default to save 1/5 of the new frames = 5
    public var currentFrameIndex = 0;
    // Task delegate for informing ViewController of tasks
    public weak var delegate: TaskDelegate?
    
    // Maximum number of points we store in the point cloud
    private let maxPoints = 1_000_000//500_000
    // Number of sample points on the grid
    private let numGridPoints = 500
    // Particle's size in pixels
    private let particleSize: Float = 10
    // We only use landscape orientation in this app
    private let orientation = UIInterfaceOrientation.portrait
    // Camera's threshold values for detecting when the camera moves so that we can accumulate the points
    private let cameraRotationThreshold = cos(2 * .degreesToRadian)
    private let cameraTranslationThreshold: Float = pow(0.02, 2)   // (meter-squared)
    // The max number of command buffers in flight
    private let maxInFlightBuffers = 3
    
    private lazy var rotateToARCamera = Self.makeRotateToARCameraMatrix(orientation: orientation)
    private let session: ARSession
    
    // THAY ĐỔI: Thêm các thuộc tính cho xoay camera ảo (xoay quanh điểm gốc)
    // Các góc xoay hiện tại (radians)
    private var rotationX: Float = 0
    private var rotationY: Float = 0
    // Ma trận xoay của người dùng
    private var userRotationMatrix: matrix_float4x4 = matrix_identity_float4x4
    
    // Metal objects and textures
    private let device: MTLDevice
    private let library: MTLLibrary
    private let renderDestination: RenderDestinationProvider
    private let relaxedStencilState: MTLDepthStencilState
    private let depthStencilState: MTLDepthStencilState
    private let commandQueue: MTLCommandQueue
    private lazy var unprojectPipelineState = makeUnprojectionPipelineState()!
    private lazy var rgbPipelineState = makeRGBPipelineState()!
    private lazy var particlePipelineState = makeParticlePipelineState()!
    // texture cache for captured image
    private lazy var textureCache = makeTextureCache()
    private var capturedImageTextureY: CVMetalTexture?
    private var capturedImageTextureCbCr: CVMetalTexture?
    private var depthTexture: CVMetalTexture?
    private var confidenceTexture: CVMetalTexture?
    
    // Multi-buffer rendering pipeline
    private let inFlightSemaphore: DispatchSemaphore
    private var currentBufferIndex = 0
    
    // The current viewport size
    private var viewportSize = CGSize()
    // The grid of sample points
    private lazy var gridPointsBuffer = MetalBuffer<Float2>(device: device,
                                                            array: makeGridPoints(),
                                                            index: kGridPoints.rawValue, options: [])
    
    // RGB buffer
    private lazy var rgbUniforms: RGBUniforms = {
        var uniforms = RGBUniforms()
        uniforms.radius = rgbRadius
        uniforms.viewToCamera.copy(from: viewToCamera)
        uniforms.viewRatio = Float(viewportSize.width / viewportSize.height)
        return uniforms
    }()
    private var rgbUniformsBuffers = [MetalBuffer<RGBUniforms>]()
    // Point Cloud buffer
    // This is not the point cloud data, but some parameters
    private lazy var pointCloudUniforms: PointCloudUniforms = {
        var uniforms = PointCloudUniforms()
        uniforms.maxPoints = Int32(maxPoints)
        uniforms.confidenceThreshold = Int32(confidenceThreshold)
        uniforms.particleSize = particleSize
        uniforms.cameraResolution = cameraResolution
        return uniforms
    }()
    private var pointCloudUniformsBuffers = [MetalBuffer<PointCloudUniforms>]()
    // Particles buffer
    // Saves the point cloud data, filled by unprojectVertex func in Shaders.metal
    private var particlesBuffer: MetalBuffer<ParticleUniforms>
    private var currentPointIndex = 0
    private var currentPointCount = 0
    
    // Camera data
    private var sampleFrame: ARFrame { session.currentFrame! }
    private lazy var cameraResolution = Float2(Float(sampleFrame.camera.imageResolution.width), Float(sampleFrame.camera.imageResolution.height))
    private lazy var viewToCamera = sampleFrame.displayTransform(for: orientation, viewportSize: viewportSize).inverted()
    private lazy var lastCameraTransform = sampleFrame.camera.transform
    
    private let overlapCalculator: OverlapCalculator = FovOverlapCalculator()
    
    public var scaleFactor: Float = 1.0 {
        didSet {
            // Giới hạn giá trị để tránh các vấn đề hiển thị
            scaleFactor = max(0.1, min(10.0, scaleFactor))
        }
    }
    
    // interfaces
    var confidenceThreshold = 1 {
        didSet {
            // apply the change for the shader
            pointCloudUniforms.confidenceThreshold = Int32(confidenceThreshold)
        }
    }
    
    var rgbRadius: Float = 0 {
        didSet {
            // apply the change for the shader
            rgbUniforms.radius = rgbRadius
        }
    }
    
    // THÊM: Metal objects và Buffer cho Hình Chóp Camera
    private lazy var cameraFrustumPipelineState = try! makeCameraFrustumPipelineState()
    private lazy var cameraFrustumVertices: [SimpleVertex] = Self.createCameraFrustumVertices()
    private lazy var cameraFrustumVertexBuffer: MetalBuffer<SimpleVertex> = .init(
        device: device,
        array: cameraFrustumVertices,
        index: 5, // Giả sử một index mới
        options: []
    )
    private var simpleUniformsBuffers = [MetalBuffer<SimpleUniforms>]() // Buffer cho ma trận
    
    // MARK: - Public Rotation Function
        
    /**
     Cập nhật góc xoay camera ảo dựa trên thao tác của người dùng.
     - Parameter deltaX: Lượng thay đổi góc xoay trục Y (xoay ngang) theo radians.
     - Parameter deltaY: Lượng thay đổi góc xoay trục X (xoay dọc) theo radians.
     */
    public func rotate(byX deltaX: Float, y deltaY: Float) {
        // Cập nhật góc xoay
        rotationX += deltaY // deltaY ảnh hưởng đến xoay quanh trục X (lên/xuống)
        rotationY += deltaX // deltaX ảnh hưởng đến xoay quanh trục Y (trái/phải)
        
        // Giới hạn xoay dọc (trục X) để tránh lộn ngược
        rotationX = max(-Float.pi / 2, min(Float.pi / 2, rotationX))
        
        // Tạo ma trận xoay mới
        let rotationMatrixX = matrix_float4x4(simd_quaternion(rotationX, SIMD3<Float>(1, 0, 0)))
        let rotationMatrixY = matrix_float4x4(simd_quaternion(rotationY, SIMD3<Float>(0, 1, 0)))
        
        // Áp dụng xoay Y trước, sau đó xoay X (yaw-pitch)
        userRotationMatrix = rotationMatrixX * rotationMatrixY
    }
    
    public func zoom(by scaleDelta: Float) {
        scaleFactor *= scaleDelta
    }
    
    init(session: ARSession, metalDevice device: MTLDevice, renderDestination: MTKView) {
        self.session = session
        self.device = device
        self.renderDestination = renderDestination
        
        library = device.makeDefaultLibrary()!
        commandQueue = device.makeCommandQueue()!
        
        // initialize our buffers
        for _ in 0 ..< maxInFlightBuffers {
            rgbUniformsBuffers.append(.init(device: device, count: 1, index: 0))
            pointCloudUniformsBuffers.append(.init(device: device, count: 1, index: kPointCloudUniforms.rawValue))
            // THÊM: Buffer cho SimpleUniforms (camera frustum)
            simpleUniformsBuffers.append(.init(device: device, count: 1, index: 4))
        }
        particlesBuffer = .init(device: device, count: maxPoints, index: kParticleUniforms.rawValue)
        
        // rbg does not need to read/write depth
        let relaxedStateDescriptor = MTLDepthStencilDescriptor()
        relaxedStencilState = device.makeDepthStencilState(descriptor: relaxedStateDescriptor)!
        
        // setup depth test for point cloud
        let depthStateDescriptor = MTLDepthStencilDescriptor()
        depthStateDescriptor.depthCompareFunction = .lessEqual
        depthStateDescriptor.isDepthWriteEnabled = true
        depthStencilState = device.makeDepthStencilState(descriptor: depthStateDescriptor)!
        
        inFlightSemaphore = DispatchSemaphore(value: maxInFlightBuffers)
    }
    
    func drawRectResized(size: CGSize) {
        viewportSize = size
    }
    
    private func updateCapturedImageTextures(frame: ARFrame) {
        // Create two textures (Y and CbCr) from the provided frame's captured image
        let pixelBuffer = frame.capturedImage
        guard CVPixelBufferGetPlaneCount(pixelBuffer) >= 2 else {
            return
        }
        
        capturedImageTextureY = makeTexture(fromPixelBuffer: pixelBuffer, pixelFormat: .r8Unorm, planeIndex: 0)
        capturedImageTextureCbCr = makeTexture(fromPixelBuffer: pixelBuffer, pixelFormat: .rg8Unorm, planeIndex: 1)
    }
    
    private func updateDepthTextures(frame: ARFrame) -> Bool {
        guard let depthMap = frame.sceneDepth?.depthMap,
              let confidenceMap = frame.sceneDepth?.confidenceMap else {
            return false
        }
        
        depthTexture = makeTexture(fromPixelBuffer: depthMap, pixelFormat: .r32Float, planeIndex: 0)
        confidenceTexture = makeTexture(fromPixelBuffer: confidenceMap, pixelFormat: .r8Uint, planeIndex: 0)
        
        return true
    }
    
    private func update(frame: ARFrame) {
        // frame dependent info
        let camera = frame.camera
        let cameraIntrinsicsInversed = camera.intrinsics.inverse
        let viewMatrix = camera.viewMatrix(for: orientation)
        let viewMatrixInversed = viewMatrix.inverse
        let projectionMatrix = camera.projectionMatrix(for: orientation, viewportSize: viewportSize, zNear: 0.001, zFar: 0)
        
        // Khi scaleFactor > 1.0, đối tượng sẽ xuất hiện lớn hơn (zoom in)
        let scaleMatrix = matrix_float4x4(
            simd_float4(scaleFactor, 0, 0, 0),
            simd_float4(0, scaleFactor, 0, 0),
            simd_float4(0, 0, scaleFactor, 0),
            simd_float4(0, 0, 0, 1)
        )
        
        // THAY ĐỔI LỚN NHẤT: ÁP DỤNG MA TRẬN XOAY CỦA NGƯỜI DÙNG
        // viewMatrix mô tả vị trí và hướng camera AR hiện tại (World -> Camera)
        // userRotationMatrix xoay đám mây điểm (hoặc xoay camera ảo theo cách ngược lại)
        // Chúng ta muốn xoay *toàn bộ cảnh* (bao gồm cả View Projection Matrix).
        
        // Ma trận View Projection đã được sửa đổi
        let rotatedViewProjectionMatrix = (projectionMatrix * viewMatrix) * userRotationMatrix * scaleMatrix
        pointCloudUniforms.viewProjectionMatrix = rotatedViewProjectionMatrix
        
        //pointCloudUniforms.viewProjectionMatrix = projectionMatrix * viewMatrix
        pointCloudUniforms.localToWorld = viewMatrixInversed * rotateToARCamera
        pointCloudUniforms.cameraIntrinsicsInversed = cameraIntrinsicsInversed
    }
    
    func draw() {
        guard let frame = session.currentFrame else {
            return
        }
        let fps: Int = session.configuration?.videoFormat.framesPerSecond ?? 0
        
        guard let lastFrameCache = ImageProcessor.shared.lastFrameCache, let lastFrame = lastFrameCache.frame else {
            ImageProcessor.shared.lastFrameCache = FrameCache(0, frame, fps)
            return
        }
        
        let distance = overlapCalculator.calculateDynamicDistance(frame.sceneDepth?.depthMap)
        let pointsCount = frame.rawFeaturePoints?.points.count ?? 0

        let overlapRatio: CGFloat
        if pointsCount <= 250 {
            overlapRatio = overlapCalculator.calculateFromFov(lastFrame, frame, distance)
        } else {
            overlapRatio = overlapCalculator.calculateFromFeaturePoints(lastFrame, frame, distance)
        }
        //print("Frank overlapRatio: \(overlapRatio)")
        if overlapRatio > 0.9 {
            return
        }
        
        guard let currentFrame = session.currentFrame,
              let renderDescriptor = renderDestination.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderDescriptor) else {
            return
        }
        
        _ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)
        commandBuffer.addCompletedHandler { [weak self] commandBuffer in
            if let self = self {
                self.inFlightSemaphore.signal()
            }
        }
        
        // update frame data
        update(frame: currentFrame)
        updateCapturedImageTextures(frame: currentFrame)
        
        // handle buffer rotating
        currentBufferIndex = (currentBufferIndex + 1) % maxInFlightBuffers
        pointCloudUniformsBuffers[currentBufferIndex][0] = pointCloudUniforms
        
        if shouldAccumulate(frame: currentFrame), updateDepthTextures(frame: currentFrame) {
            //print("Frank shouldAccumulate called: \(currentFrame.rawFeaturePoints?.points.count)")
            accumulatePoints(frame: currentFrame, commandBuffer: commandBuffer, renderEncoder: renderEncoder)
            
//            if (checkSamplingRate()) {
//                // save selected data to disk if not dropped
//                autoreleasepool {
//                    // selected data are deep copied into custom struct to release currentFrame
//                    // if not, the pools of memory reserved for ARFrame will be full and later frames will be dropped
//                    let data = ARFrameDataPack(
//                        timestamp: currentFrame.timestamp,
//                        cameraTransform: currentFrame.camera.transform,
//                        cameraEulerAngles: currentFrame.camera.eulerAngles,
//                        depthMap: duplicatePixelBuffer(input: currentFrame.sceneDepth!.depthMap),
//                        smoothedDepthMap: duplicatePixelBuffer(input: currentFrame.smoothedSceneDepth!.depthMap),
//                        confidenceMap: duplicatePixelBuffer(input: currentFrame.sceneDepth!.confidenceMap!),
//                        capturedImage: duplicatePixelBuffer(input: currentFrame.capturedImage),
//                        localToWorld: pointCloudUniforms.localToWorld,
//                        cameraIntrinsicsInversed: pointCloudUniforms.cameraIntrinsicsInversed
//                    )
//                    saveData(frame: data)
//                }
//            }
        }
        
        // check and render rgb camera image
        if rgbUniforms.radius > 0 {
            var retainingTextures = [capturedImageTextureY, capturedImageTextureCbCr]
            commandBuffer.addCompletedHandler { buffer in
                retainingTextures.removeAll()
            }
            rgbUniformsBuffers[currentBufferIndex][0] = rgbUniforms
            
            renderEncoder.setDepthStencilState(relaxedStencilState)
            renderEncoder.setRenderPipelineState(rgbPipelineState)
            renderEncoder.setVertexBuffer(rgbUniformsBuffers[currentBufferIndex])
            renderEncoder.setFragmentBuffer(rgbUniformsBuffers[currentBufferIndex])
            renderEncoder.setFragmentTexture(CVMetalTextureGetTexture(capturedImageTextureY!), index: Int(kTextureY.rawValue))
            renderEncoder.setFragmentTexture(CVMetalTextureGetTexture(capturedImageTextureCbCr!), index: Int(kTextureCbCr.rawValue))
            renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
        
        // render particles
        renderEncoder.setDepthStencilState(depthStencilState)
        renderEncoder.setRenderPipelineState(particlePipelineState)
        renderEncoder.setVertexBuffer(pointCloudUniformsBuffers[currentBufferIndex])
        renderEncoder.setVertexBuffer(particlesBuffer)
        renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: currentPointCount)
        
        // --- THÊM: VẼ HÌNH CHÓP CAMERA FRUSTUM ---
                
        // 1. Tính toán Model-View-Projection Matrix cho hình chóp
        
        // Lấy ma trận View-Projection * Rotation * Scale từ hàm update (chỉ Projection * View * UserRotation * Scale)
        let viewProjectionMatrix = pointCloudUniforms.viewProjectionMatrix
        
        // Lấy Model Matrix (World Matrix) của camera AR
        let cameraWorldTransform = currentFrame.camera.transform
        
        // ModelViewProjection = ViewProjectionMatrix * ModelMatrix
        let cameraFrustumModelViewProjectionMatrix = viewProjectionMatrix * cameraWorldTransform
        
        var simpleUniforms = SimpleUniforms(modelViewProjectionMatrix: cameraFrustumModelViewProjectionMatrix)
        simpleUniformsBuffers[currentBufferIndex][0] = simpleUniforms
        
        // 2. Thiết lập Render State và Vẽ
        
        // Tắt Depth Write nhưng vẫn dùng Depth Test để hình chóp trong suốt không che mất các điểm gần hơn.
        let frustumDepthStateDescriptor = MTLDepthStencilDescriptor()
        frustumDepthStateDescriptor.depthCompareFunction = .lessEqual
        frustumDepthStateDescriptor.isDepthWriteEnabled = false // KHÔNG ghi depth
        let frustumDepthStencilState = device.makeDepthStencilState(descriptor: frustumDepthStateDescriptor)!
        
        renderEncoder.setDepthStencilState(frustumDepthStencilState)
        if let cameraFrustumPipelineState = self.cameraFrustumPipelineState {
            renderEncoder.setRenderPipelineState(cameraFrustumPipelineState)
        }
        
        // Cài đặt Vertex Buffer (Uniforms và Vertices)
        //renderEncoder.setVertexBuffer(simpleUniformsBuffers[currentBufferIndex], offset: 0, index: 4)
        renderEncoder.setVertexBuffer(simpleUniformsBuffers[currentBufferIndex].buffer, offset: 0, index: 4)
        //renderEncoder.setVertexBuffer(cameraFrustumVertexBuffer, offset: 0, index: 5)
        renderEncoder.setVertexBuffer(cameraFrustumVertexBuffer.buffer, offset: 0, index: 5)
        
        // Vẽ 4 mặt (mỗi mặt 3 vertices)
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: cameraFrustumVertices.count)
        
        // ----------------------------------------------
        
        renderEncoder.endEncoding()
        
        commandBuffer.present(renderDestination.currentDrawable!)
        commandBuffer.commit()
        //print(("Frank draw point cloud called: \(currentPointCount)"))
    }

    // MARK: - Point cloud snapshot API
    /// Return a snapshot of the current accumulated point cloud as arrays of positions and colors.
    /// This provides a bridge for higher-level code (e.g., SceneKit) to visualize the same points.
    /// Note: This is a synchronous shallow-copy snapshot of the CPU-accessible buffer.
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
    
    // custom struct for pulling necessary data from arframes
    struct ARFrameDataPack {
        var timestamp: Double
        var cameraTransform: simd_float4x4
        var cameraEulerAngles: simd_float3
        var depthMap: CVPixelBuffer
        var smoothedDepthMap: CVPixelBuffer
        var confidenceMap: CVPixelBuffer
        var capturedImage: CVPixelBuffer
        var localToWorld: simd_float4x4
        var cameraIntrinsicsInversed: simd_float3x3
    }
    
    /// Save data to disk in json and jpeg formats.
    private func saveData(frame: ARFrameDataPack) {
        struct DataPack: Codable {
            var timestamp: Double
            var cameraTransform: simd_float4x4 // The position and orientation of the camera in world coordinate space.
            var cameraEulerAngles: simd_float3 // The orientation of the camera, expressed as roll, pitch, and yaw values.
            var depthMap: [[Float32]]
            var smoothedDepthMap: [[Float32]]
            var confidenceMap: [[UInt8]]
            var localToWorld: simd_float4x4
            var cameraIntrinsicsInversed: simd_float3x3
        }
        
        delegate?.didStartTask()
        Task.init(priority: .utility) {
            do {
                let dataPack = await DataPack(
                    timestamp: frame.timestamp,
                    cameraTransform: frame.cameraTransform,
                    cameraEulerAngles: frame.cameraEulerAngles,
                    depthMap: cvPixelBuffer2Map(rawDepth: frame.depthMap),
                    smoothedDepthMap: cvPixelBuffer2Map(rawDepth: frame.smoothedDepthMap),
                    confidenceMap: cvPixelBuffer2Map(rawDepth: frame.confidenceMap),
                    localToWorld: frame.localToWorld,
                    cameraIntrinsicsInversed: frame.cameraIntrinsicsInversed
                )
                
                let jsonEncoder = JSONEncoder()
                jsonEncoder.outputFormatting = .prettyPrinted
                
                let encoded = try jsonEncoder.encode(dataPack)
                let encodedStr = String(data: encoded, encoding: .utf8)!
                try await saveFile(content: encodedStr, filename: "\(frame.timestamp)_\(pickFrames).json", folder: currentFolder + "/data")
                try await savePic(pic: cvPixelBuffer2UIImage(pixelBuffer: frame.capturedImage), filename: "\(frame.timestamp)_\(pickFrames).jpeg", folder: currentFolder + "/data")
                delegate?.didFinishTask()
            } catch {
                print(error.localizedDescription)
            }
        }
    }
    
    /// Save all particles to a point cloud file in ply format.
    func savePointCloud() {
        delegate?.didStartTask()
        Task.init(priority: .utility) {
            do {
                var fileToWrite = ""
                let headers = ["ply", "format ascii 1.0", "element vertex \(currentPointCount)", "property float x", "property float y", "property float z", "property uchar red", "property uchar green", "property uchar blue", "element face 0", "property list uchar int vertex_indices", "end_header"]
                for header in headers {
                    fileToWrite += header
                    fileToWrite += "\r\n"
                }
                
                for i in 0..<currentPointCount {
                    let point = particlesBuffer[i]
                    let colors = point.color
                    
                    let red = colors.x * 255.0
                    let green = colors.y * 255.0
                    let blue = colors.z * 255.0
                    
                    let pvValue = "\(point.position.x) \(point.position.y) \(point.position.z) \(Int(red)) \(Int(green)) \(Int(blue))"
                    fileToWrite += pvValue
                    fileToWrite += "\r\n"
                }
                
                try await saveFile(content: fileToWrite, filename: "\(getTimeStr()).ply", folder: currentFolder)
                
                delegate?.didFinishTask()
            } catch {
                print(error.localizedDescription)
            }
        }
    }
    
    private func shouldAccumulate(frame: ARFrame) -> Bool {
        if (!isRecording) {
            //print("Frank shouldAccumulate false")
            return false
        }
        let cameraTransform = frame.camera.transform
        let isAccumulate = currentPointCount == 0
        || dot(cameraTransform.columns.2, lastCameraTransform.columns.2) <= cameraRotationThreshold
        || distance_squared(cameraTransform.columns.3, lastCameraTransform.columns.3) >= cameraTranslationThreshold
        return isAccumulate
    }
    
    /// Check if the current frame should be saved or dropped based on sampling rate configuration
    private func checkSamplingRate() -> Bool {
        currentFrameIndex += 1
        return currentFrameIndex % pickFrames == 0
    }
    
    private func accumulatePoints(frame: ARFrame, commandBuffer: MTLCommandBuffer, renderEncoder: MTLRenderCommandEncoder) {
        pointCloudUniforms.pointCloudCurrentIndex = Int32(currentPointIndex)
        
        var retainingTextures = [capturedImageTextureY, capturedImageTextureCbCr, depthTexture, confidenceTexture]
        commandBuffer.addCompletedHandler { buffer in
            retainingTextures.removeAll()
        }
        
        renderEncoder.setDepthStencilState(relaxedStencilState)
        renderEncoder.setRenderPipelineState(unprojectPipelineState)
        renderEncoder.setVertexBuffer(pointCloudUniformsBuffers[currentBufferIndex])
        renderEncoder.setVertexBuffer(particlesBuffer)
        renderEncoder.setVertexBuffer(gridPointsBuffer)
        renderEncoder.setVertexTexture(CVMetalTextureGetTexture(capturedImageTextureY!), index: Int(kTextureY.rawValue))
        renderEncoder.setVertexTexture(CVMetalTextureGetTexture(capturedImageTextureCbCr!), index: Int(kTextureCbCr.rawValue))
        renderEncoder.setVertexTexture(CVMetalTextureGetTexture(depthTexture!), index: Int(kTextureDepth.rawValue))
        renderEncoder.setVertexTexture(CVMetalTextureGetTexture(confidenceTexture!), index: Int(kTextureConfidence.rawValue))
        renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: gridPointsBuffer.count)
        
        currentPointIndex = (currentPointIndex + gridPointsBuffer.count) % maxPoints
        currentPointCount = min(currentPointCount + gridPointsBuffer.count, maxPoints)
        lastCameraTransform = frame.camera.transform
    }
}

// MARK: - Metal Helpers

private extension Renderer {
    func makeUnprojectionPipelineState() -> MTLRenderPipelineState? {
        guard let vertexFunction = library.makeFunction(name: "unprojectVertex") else {
            return nil
        }
        
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.isRasterizationEnabled = false
        descriptor.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        descriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
        
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }
    
    func makeRGBPipelineState() -> MTLRenderPipelineState? {
        guard let vertexFunction = library.makeFunction(name: "rgbVertex"),
              let fragmentFunction = library.makeFunction(name: "rgbFragment") else {
            return nil
        }
        
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        descriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
        
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }
    
    func makeParticlePipelineState() -> MTLRenderPipelineState? {
        guard let vertexFunction = library.makeFunction(name: "particleVertex"),
              let fragmentFunction = library.makeFunction(name: "particleFragment") else {
            return nil
        }
        
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        descriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }
    
    /// Makes sample points on camera image, also precompute the anchor point for animation
    func makeGridPoints() -> [Float2] {
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
    
    func makeTextureCache() -> CVMetalTextureCache {
        // Create captured image texture cache
        var cache: CVMetalTextureCache!
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        
        return cache
    }
    
    func makeTexture(fromPixelBuffer pixelBuffer: CVPixelBuffer, pixelFormat: MTLPixelFormat, planeIndex: Int) -> CVMetalTexture? {
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, planeIndex)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, planeIndex)
        
        var texture: CVMetalTexture? = nil
        let status = CVMetalTextureCacheCreateTextureFromImage(nil, textureCache, pixelBuffer, nil, pixelFormat, width, height, planeIndex, &texture)
        
        if status != kCVReturnSuccess {
            texture = nil
        }
        
        return texture
    }
    
    static func cameraToDisplayRotation(orientation: UIInterfaceOrientation) -> Int {
        switch orientation {
        case .landscapeLeft:
            return 180
        case .portrait:
            return 90
        case .portraitUpsideDown:
            return -90
        default:
            return 0
        }
    }
    
    static func makeRotateToARCameraMatrix(orientation: UIInterfaceOrientation) -> matrix_float4x4 {
        // flip to ARKit Camera's coordinate
        let flipYZ = matrix_float4x4(
            [1, 0, 0, 0],
            [0, -1, 0, 0],
            [0, 0, -1, 0],
            [0, 0, 0, 1] )
        
        let rotationAngle = Float(cameraToDisplayRotation(orientation: orientation)) * .degreesToRadian
        return flipYZ * matrix_float4x4(simd_quaternion(rotationAngle, Float3(0, 0, 1)))
    }
    
    // THÊM: Pipeline State cho Camera Frustum (có Blending)
    func makeCameraFrustumPipelineState() -> MTLRenderPipelineState? {
        // Giả sử có "simpleVertex" và "simpleFragment" trong Shaders.metal
        guard let vertexFunction = library.makeFunction(name: "simpleVertex"),
              let fragmentFunction = library.makeFunction(name: "simpleFragment") else {
            return nil
        }
        
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        descriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
        
        // Kích hoạt Blending cho độ trong suốt (alpha = 0.4)
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }
    
    // THÊM: Định nghĩa hình chóp tứ giác (camera frustum)
    static func createCameraFrustumVertices() -> [SimpleVertex] {
        let frustumColor = SIMD4<Float>(0.0, 0.0, 1.0, 0.4) // Màu Xanh, Alpha 0.4
        let size: Float = 0.1 // Kích thước cơ sở hình chóp (tính bằng mét)
        let height: Float = 0.2 // Chiều cao hình chóp (đỉnh đến mặt đáy)
        
        let A = SIMD3<Float>(-size, -size, -height) // Góc trái dưới (mặt đáy)
        let B = SIMD3<Float>( size, -size, -height) // Góc phải dưới
        let C = SIMD3<Float>( size,  size, -height) // Góc phải trên
        let D = SIMD3<Float>(-size,  size, -height) // Góc trái trên
        let O = SIMD3<Float>( 0, 0, 0)             // Đỉnh chóp (Camera)

        // Định nghĩa các tam giác cho 4 mặt bên
        let vertices: [SimpleVertex] = [
            // Mặt 1: Tam giác OAB
            SimpleVertex(position: O, color: frustumColor),
            SimpleVertex(position: A, color: frustumColor),
            SimpleVertex(position: B, color: frustumColor),
            
            // Mặt 2: Tam giác OBC
            SimpleVertex(position: O, color: frustumColor),
            SimpleVertex(position: B, color: frustumColor),
            SimpleVertex(position: C, color: frustumColor),
            
            // Mặt 3: Tam giác OCD
            SimpleVertex(position: O, color: frustumColor),
            SimpleVertex(position: C, color: frustumColor),
            SimpleVertex(position: D, color: frustumColor),
            
            // Mặt 4: Tam giác ODA
            SimpleVertex(position: O, color: frustumColor),
            SimpleVertex(position: D, color: frustumColor),
            SimpleVertex(position: A, color: frustumColor),
            
            // (Không vẽ mặt đáy để giữ hiệu ứng "khung")
        ]
        
        return vertices
    }
}

struct SimpleVertex {
    var position: SIMD3<Float>
    var color: SIMD4<Float>
}

struct SimpleUniforms {
    var modelViewProjectionMatrix: matrix_float4x4
}
