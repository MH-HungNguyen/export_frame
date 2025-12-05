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
    
    // MARK: cho Hình Chóp Camera
    // Mảng lưu lịch sử vị trí Camera (Lưu Model Matrix)
    private var cameraHistoryTransforms: [matrix_float4x4] = []
    // Giới hạn số lượng hình chóp để tránh crash bộ nhớ nếu chạy quá lâu
    private let maxPyramids = 500
    private var pyramidPipelineState: MTLRenderPipelineState!
    private var pyramidVertexBuffer: MTLBuffer!
    private var pyramidVertexCount: Int = 0
    
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
    
    init(
        session: ARSession,
        metalDevice device: MTLDevice,
        renderDestination: MTKView
    ) {
        self.session = session
        self.device = device
        self.renderDestination = renderDestination
        
        library = device.makeDefaultLibrary()!
        commandQueue = device.makeCommandQueue()!
        
        // initialize our buffers
        for _ in 0 ..< maxInFlightBuffers {
            rgbUniformsBuffers.append(.init(device: device, count: 1, index: 0))
            pointCloudUniformsBuffers.append(.init(device: device, count: 1, index: kPointCloudUniforms.rawValue))
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
        
        // MARK: THÊM MỚI: KHỞI TẠO PYRAMID ---
        pyramidPipelineState = makeGeometryPipelineState()
        (pyramidVertexBuffer, pyramidVertexCount) = makePyramidBuffer()
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
        guard let currentFrame = session.currentFrame else {
            return
        }
        
        // 1. CHUYỂN VIỆC TẠO COMMAND BUFFER LÊN ĐẦU
        // Chúng ta cần vẽ mỗi frame bất kể camera có di chuyển hay không (để update xoay/zoom)
        guard let renderDescriptor = renderDestination.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderDescriptor) else {
            return
        }
        
        // Xử lý semaphore để đồng bộ CPU/GPU
        _ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)
        commandBuffer.addCompletedHandler { [weak self] commandBuffer in
            if let self = self {
                self.inFlightSemaphore.signal()
            }
        }
        
        // 2. CẬP NHẬT DỮ LIỆU FRAME (Bao gồm cả ma trận xoay/zoom của user)
        // Hàm này tính toán pointCloudUniforms.viewProjectionMatrix dựa trên rotation/scale hiện tại
        update(frame: currentFrame)
        updateCapturedImageTextures(frame: currentFrame)
        
        // Cập nhật buffer index
        currentBufferIndex = (currentBufferIndex + 1) % maxInFlightBuffers
        pointCloudUniformsBuffers[currentBufferIndex][0] = pointCloudUniforms
        
        // 3. TÍNH TOÁN OVERLAP (Logic cũ)
        var shouldAccumulatePoints = false
        
        // Kiểm tra cache frame cũ để tính overlap
        if let lastFrameCache = ImageProcessor.shared.lastFrameCache, let lastFrame = lastFrameCache.frame {
            let distance = overlapCalculator.calculateDynamicDistance(currentFrame.sceneDepth?.depthMap)
            let pointsCount = currentFrame.rawFeaturePoints?.points.count ?? 0
            
            let overlapRatio: CGFloat
            if pointsCount <= 250 {
                overlapRatio = overlapCalculator.calculateFromFov(lastFrame, currentFrame, distance)
            } else {
                overlapRatio = overlapCalculator.calculateFromFeaturePoints(lastFrame, currentFrame, distance)
            }
            
            // Logic mới: Chỉ đánh dấu flag là false, KHÔNG return hàm draw
            if overlapRatio <= 0.9 {
                shouldAccumulatePoints = true
            }
        } else {
            // Nếu chưa có lastFrame (frame đầu tiên), luôn accumulate
            let fps: Int = session.configuration?.videoFormat.framesPerSecond ?? 0
            ImageProcessor.shared.lastFrameCache = FrameCache(0, currentFrame, fps)
            shouldAccumulatePoints = true
        }

        // 4. THỰC HIỆN TÍCH LŨY ĐIỂM (Chỉ khi đủ điều kiện)
        // Kết hợp điều kiện shouldAccumulate (của hệ thống) và overlap (của thuật toán)
        if shouldAccumulatePoints,
           shouldAccumulate(frame: currentFrame),
           updateDepthTextures(frame: currentFrame) {
            
            accumulatePoints(frame: currentFrame, commandBuffer: commandBuffer, renderEncoder: renderEncoder)
            
            // Cập nhật lại cache sau khi đã accumulate thành công
            let fps: Int = session.configuration?.videoFormat.framesPerSecond ?? 0
            ImageProcessor.shared.lastFrameCache = FrameCache(0, currentFrame, fps)
        }
        
        // 5. VẼ (RENDER) - PHẦN NÀY LUÔN CHẠY
        
        // A. Vẽ nền Camera RGB
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
        
        // B. Vẽ Point Cloud (Particles)
        // Vì update(frame:) đã chạy ở trên, viewProjectionMatrix đã bao gồm rotation/zoom mới nhất
        renderEncoder.setDepthStencilState(depthStencilState)
        renderEncoder.setRenderPipelineState(particlePipelineState)
        renderEncoder.setVertexBuffer(pointCloudUniformsBuffers[currentBufferIndex])
        renderEncoder.setVertexBuffer(particlesBuffer)
        renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: currentPointCount)
        
        // C. Vẽ Hình Chóp (Pyramids Trail)
        if let pyramidPipeline = pyramidPipelineState,
           let pyramidBuffer = pyramidVertexBuffer,
           !cameraHistoryTransforms.isEmpty {
            
            let viewProjMatrix = pointCloudUniforms.viewProjectionMatrix
            
            var mvpMatrices: [matrix_float4x4] = []
            mvpMatrices.reserveCapacity(cameraHistoryTransforms.count + 1)
            
            for oldTransform in cameraHistoryTransforms {
                let mvp = viewProjMatrix * oldTransform
                mvpMatrices.append(mvp)
            }
            
            if let currentCamTransform = session.currentFrame?.camera.transform {
                let currentMVP = viewProjMatrix * currentCamTransform
                mvpMatrices.append(currentMVP)
            }
            
            let instanceCount = mvpMatrices.count
            
            renderEncoder.pushDebugGroup("Draw Pyramids Trail")
            renderEncoder.setRenderPipelineState(pyramidPipeline)
            renderEncoder.setDepthStencilState(depthStencilState)
            
            renderEncoder.setVertexBuffer(pyramidBuffer, offset: 0, index: 0)
            
            let mvpBufferSize = mvpMatrices.count * MemoryLayout<matrix_float4x4>.stride
            if let instanceBuffer = device.makeBuffer(bytes: mvpMatrices, length: mvpBufferSize, options: []) {
                renderEncoder.setVertexBuffer(instanceBuffer, offset: 0, index: 1)
                renderEncoder.drawPrimitives(type: .triangle,
                                           vertexStart: 0,
                                           vertexCount: pyramidVertexCount,
                                           instanceCount: instanceCount)
            }
            
            renderEncoder.popDebugGroup()
        }
        
        // Kết thúc và gửi lệnh GPU
        renderEncoder.endEncoding()
        commandBuffer.present(renderDestination.currentDrawable!)
        commandBuffer.commit()
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
    
    private func accumulatePoints(
        frame: ARFrame,
        commandBuffer: MTLCommandBuffer,
        renderEncoder: MTLRenderCommandEncoder
    ) {
        pointCloudUniforms.pointCloudCurrentIndex = Int32(currentPointIndex)
        
        // --- THÊM MỚI: LƯU VỊ TRÍ CAMERA VÀO LỊCH SỬ ---
        if cameraHistoryTransforms.count < maxPyramids {
            cameraHistoryTransforms.append(frame.camera.transform)
        } else {
            // Nếu đầy, xóa cái cũ nhất để thêm cái mới (FIFO)
            cameraHistoryTransforms.removeFirst()
            cameraHistoryTransforms.append(frame.camera.transform)
        }
        // -----------------------------------------------
        
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
    
    // MARK: Function for Pỷamis shape
    // --- THÊM MỚI: TẠO PIPELINE CHO HÌNH KHỐI ---
    func makeGeometryPipelineState() -> MTLRenderPipelineState? {
        guard let vertexFunction = library.makeFunction(name: "geometryVertex"),
              let fragmentFunction = library.makeFunction(name: "geometryFragment") else {
            return nil
        }
        
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        descriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
        
        // Cấu hình Blending để hỗ trợ độ trong suốt (Alpha = 0.4)
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        // Định nghĩa layout vertex
        let vertexDescriptor = MTLVertexDescriptor()
        // Position
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        // Color
        vertexDescriptor.attributes[1].format = .float4
        vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
        vertexDescriptor.attributes[1].bufferIndex = 0
        
        vertexDescriptor.layouts[0].stride = MemoryLayout<SimpleVertex>.stride
        
        descriptor.vertexDescriptor = vertexDescriptor
        
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    // --- THÊM MỚI: TẠO DỮ LIỆU HÌNH CHÓP ---
    func makePyramidBuffer() -> (MTLBuffer?, Int) {
        // Màu xanh, alpha 0.4
        let color = SIMD4<Float>(0, 0, 1, 0.4)
        
        // Kích thước hình chóp (đơn vị mét)
        let w: Float = 0.05 // width
        let h: Float = 0.05 // height
        let d: Float = 0.15 // depth (độ dài chóp)
        
        // Đỉnh chóp tại (0,0,0) - Tương ứng vị trí Camera
        let apex = SIMD3<Float>(0, 0, 0)
        
        // 4 đỉnh đáy (nằm về phía trước camera, ARKit camera nhìn về hướng -Z)
        let v0 = SIMD3<Float>(-w, -h, -d)
        let v1 = SIMD3<Float>( w, -h, -d)
        let v2 = SIMD3<Float>( w,  h, -d)
        let v3 = SIMD3<Float>(-w,  h, -d)
        
        // Tạo các tam giác (Vertices)
        let vertices: [SimpleVertex] = [
            // Mặt bên 1
            SimpleVertex(position: apex, color: color), SimpleVertex(position: v0, color: color), SimpleVertex(position: v1, color: color),
            // Mặt bên 2
            SimpleVertex(position: apex, color: color), SimpleVertex(position: v1, color: color), SimpleVertex(position: v2, color: color),
            // Mặt bên 3
            SimpleVertex(position: apex, color: color), SimpleVertex(position: v2, color: color), SimpleVertex(position: v3, color: color),
            // Mặt bên 4
            SimpleVertex(position: apex, color: color), SimpleVertex(position: v3, color: color), SimpleVertex(position: v0, color: color),
            // Đáy (vẽ bằng 2 tam giác)
            SimpleVertex(position: v0, color: color), SimpleVertex(position: v2, color: color), SimpleVertex(position: v1, color: color),
            SimpleVertex(position: v0, color: color), SimpleVertex(position: v3, color: color), SimpleVertex(position: v2, color: color)
        ]
        
        let buffer = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<SimpleVertex>.stride, options: [])
        return (buffer, vertices.count)
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
