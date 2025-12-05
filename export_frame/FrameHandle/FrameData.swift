//
//  FrameData.swift
//  Quick3D
//
//  Created by HaNST on 1/10/25.
//

import Foundation
import ARKit
import simd
import Metal

class FrameMetadata {
    let id: String = String.randomHexNumber(length: 16)
    
    let index: Int
    
    let transform: simd_float4x4
    let projection: simd_float4x4
    let intrinsics: simd_float3x3
    let eulerAngles: simd_float3
    
    let exif: [String: Any]
    let imageResolution: CGSize
    let width: Double
    let height: Double
    let exposureDuration: TimeInterval
    let exposureOffset: Float
    let grainIntensity: Float
    
    let gpsLocation: LocationModel
    let rtkLocation: LocationModel?
    
    let viewMatrix: simd_float4x4
    let projectionMatrix: simd_float4x4
    let rotateMatrix: simd_float4x4
    
    let fps: Int
    
    let distance : Float = 1.0
    
    let angle : Float = 20
    
    var location: LocationModel {
        rtkLocation ?? gpsLocation
    }
    
    var isRTK: Bool {
        location.isRTK
    }
    
    var position: simd_float3 {
        make_simd_float3(transform.columns.3)
    }
    
    var featurePoints: [simd_float3]
    
    init(_ data: FrameMetadata) {
        self.index = data.index
        self.projection = data.projection
        self.transform = data.transform
        self.intrinsics = data.intrinsics
        self.eulerAngles = data.eulerAngles
        self.imageResolution = data.imageResolution
        self.width = data.width
        self.height = data.height
        self.exposureDuration = data.exposureDuration
        self.exposureOffset = data.exposureOffset
        self.grainIntensity = data.grainIntensity
        self.exif = data.exif
        self.gpsLocation = data.gpsLocation
        self.rtkLocation = data.rtkLocation
        self.rotateMatrix = data.rotateMatrix
        self.viewMatrix = data.viewMatrix
        self.projectionMatrix = data.projectionMatrix
        self.fps = data.fps
        self.featurePoints = data.featurePoints
    }
    
    init(_ frame: ARFrame, index: Int, fps: Int = 0) throws {
        self.index = index
        self.projection = frame.camera.projectionMatrix
        self.transform = frame.camera.transform
        self.intrinsics = frame.camera.intrinsics
        self.eulerAngles = frame.camera.eulerAngles
        self.imageResolution = frame.camera.imageResolution
        self.width = frame.camera.imageResolution.width
        self.height = frame.camera.imageResolution.height
        self.exposureDuration = frame.camera.exposureDuration
        self.exposureOffset = frame.camera.exposureOffset
        self.grainIntensity = frame.cameraGrainIntensity
        
        if #available(iOS 16.0, *) {
            self.exif = frame.exifData
        } else {
            self.exif = [:]
        }
        
        self.gpsLocation = LocationModel()//LocationManager.shared.gpsLocation
        self.rtkLocation = LocationModel()//LocationManager.shared.rtkLocation
        
        let orientation: UIInterfaceOrientation = .portrait//AppDelegate.orientationLock == .portrait ? .portrait : .landscapeRight
        self.rotateMatrix = FrameMetadata.makeRotateToARCameraMatrix(orientation: orientation)
        self.viewMatrix = frame.camera.viewMatrix(for: orientation)
        self.projectionMatrix = frame.camera.projectionMatrix(for: orientation, viewportSize: CGSize(), zNear: 0.001, zFar: 0)
        
        self.fps = fps
        self.featurePoints = frame.rawFeaturePoints?.points ?? []
    }
    
    static func makeRotateToARCameraMatrix(orientation: UIInterfaceOrientation) -> simd_float4x4 {
        let flipYZ = simd_float4x4(
            [1, 0, 0, 0],
            [0, -1, 0, 0],
            [0, 0, -1, 0],
            [0, 0, 0, 1])
        let rotationAngle = Float(cameraToDisplayRotation(orientation: orientation)) * Float.pi / 180
        return flipYZ * simd_float4x4(simd_quaternion(rotationAngle, SIMD3<Float>(0, 0, 1)))
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
    
}

class FrameData: FrameMetadata {
    
    //let imageY: MTLTexture
//    let imageCbCr: MTLTexture
//    let depthMap: MTLTexture
//    let confidenceMap: MTLTexture
    
    override init(_ frame: ARFrame, index: Int, fps: Int = 0) throws {
        guard CVPixelBufferGetPlaneCount(frame.capturedImage) >= 2 else {
            throw ARError.init(.invalidReferenceImage)
        }
        
        try super.init(frame, index: index, fps: fps)
    }
    
    
}

extension FrameMetadata {
    var imageName: String {
        String(format: "Image_%06d.jpg", index)
    }
    
    var imageNameWithoutExtension: String {
        String(format: "Image_%06d", index)
    }
    
    var depthMapImageName: String {
        String(format: "DepthMap_%06d.tiff", index)
    }
    
    var confidenceMapImageName: String {
        String(format: "Confidence_%06d.tiff", index)
    }
    
}

class InfoData: FrameMetadata {
    
    var ar: simd_double3 {
        [Double(transform.columns.3.x), Double(transform.columns.3.y), Double(transform.columns.3.z)]
    }
    
    var ar2D: simd_double2 {
        let p = transform.columns.3
        return simd_double2(Double(p.x), Double(p.z))
    }
    
    
    var manifest: ImageOutputModel {
        get {
            return ImageOutputModel(depthMap: depthMapImageName, photo: imageName, depthMapConfidence: confidenceMapImageName)
        }
    }
    
}
