//
//  FovOverlapCalculator.swift
//  ShadowExp
//
//  Created by HungNT on 31/10/25.
//

import Foundation
import ARKit

import Foundation
import ARKit

protocol OverlapCalculator {
    
    func calculateFromFov(
        _ frame1: ARFrame,
        _ frame2: ARFrame
    ) -> CGFloat
    
    func calculateFromFov(
        _ frame1: ARFrame,
        _ frame2: ARFrame,
        _ distance: Float
    ) -> CGFloat
    
    func calculateFromFov(
        _ frame1: FrameMetadata,
        _ frame2: ARFrame,
        _ distance: Float
    ) -> CGFloat
    
    func calculateFromFeaturePoints(
        _ frame1: ARFrame,
        _ frame2: ARFrame,
        _ distance: Float
    ) -> CGFloat
    
    func calculateFromFeaturePoints(
        _ frame1: FrameMetadata,
        _ frame2: ARFrame,
        _ distance: Float
    ) -> CGFloat

    func calculateDynamicDistance(_ depthMap: CVPixelBuffer?) -> Float
}

class FovOverlapCalculator: OverlapCalculator {
    
    private let MIN_THRESHOLD: Float = 0.01
    
    func calculateFromFov(_ frame1: ARFrame, _ frame2: ARFrame) -> CGFloat {
        let previousTransform = frame1.camera.transform
        let currentTransform = frame2.camera.transform
        
        // Lấy vector hướng nhìn của mỗi camera (trục Z âm của camera)
        // Get the view vector of each camera (negative Z axis of the camera)
        let col2_1: simd_float4 = previousTransform.columns.2
        let direction1 = -simd_float3(col2_1.x, col2_1.y, col2_1.z)
        
        let col2_2: simd_float4 = currentTransform.columns.2
        let direction2 = -simd_float3(col2_2.x, col2_2.y, col2_2.z)
        
        // Chiếu các vector hướng xuống mặt phẳng XZ (mặt phẳng ngang) để chỉ tính yaw
        // Project the vectors down to the XZ plane (horizontal plane) to calculate yaw only
        let flatDirection1 = SIMD2<Float>(direction1.x, direction1.z)
        let flatDirection2 = SIMD2<Float>(direction2.x, direction2.z)

        // Tính góc của mỗi vector so với trục X dương trên mặt phẳng XZ
        // Calculate the angle of each vector relative to the positive X-axis on the XZ plane
        let angle1 = atan2(flatDirection1.y, flatDirection1.x)
        let angle2 = atan2(flatDirection2.y, flatDirection2.x)

        // Tính sự khác biệt góc và chuẩn hóa về khoảng [-PI, PI]
        // Calculate the angle difference and normalize to the interval [-PI, PI]
        var yawDifference = angle2 - angle1
        while yawDifference > .pi { yawDifference -= 2 * .pi }
        while yawDifference < -.pi { yawDifference += 2 * .pi }
        let yawDiff = abs(yawDifference)
        
        let pitch1 = atan2(direction1.y, sqrt(direction1.x * direction1.x + direction1.z * direction1.z))
        let pitch2 = atan2(direction2.y, sqrt(direction2.x * direction2.x + direction2.z * direction2.z))
        let pitchDifference = abs(pitch2 - pitch1)
        
        // Get FOV of camera
        let currentImageResolution = frame2.camera.imageResolution
        let currentFOV = frame2.fieldOfView(for: currentImageResolution)
        
        // Calculate transform between two frame
        let relativeTransform = currentTransform.inverse * previousTransform
        
        // Get translation vector from relative matrix
        let translation = simd_float3(
            x: relativeTransform.columns.3.x,
            y: relativeTransform.columns.3.y,
            z: relativeTransform.columns.3.z
        )
        
        // Ước lượng tỉ lệ overlap, assumedDistance là khoảng cách muốn tính toán overlap đến một mặt phẳng ảo.
        // Giả sử ở đây là mặt phẳng ảo cách camera 1 mét.
        // Estimate the overlap ratio, assumedDistance is the distance to calculate overlap from a virtual plane.
        // Suppose here the virtual plane is 1 meter away from the camera.
        let distance: Float = 1.0
        //let assumedDistance = calculateDynamicDistance(frame: )

        let currentViewHalfWidth = distance * tan(currentFOV.horizontal / 2)
        let currentViewHalfHeight = distance * tan(currentFOV.vertical / 2)

        let currentViewWidth = currentViewHalfWidth * 2
        let currentViewHeight = currentViewHalfHeight * 2
        
        // Tính tỉ lệ overlap trên cả 3 trục x, y, z khi di chuyển thiết bị
        // Calculate the overlap ratio on all 3 axes x, y, z when moving the device
        let overlapRatioX = max(0, 1 - abs(translation.x) / currentViewWidth)
        let overlapRatioY = max(0, 1 - abs(translation.y) / currentViewHeight)
        let overlapRatioZ = max(0, 1 - abs(translation.z) / (currentViewWidth * currentViewHeight))
        
        // Tính tỉ lệ overlap của yaw, và pitch khi xoay thiết bị
        // Calculate the overlap ratio of yaw, and pitch when rotating the device
        let overlapRatioYaw = max(0.0, 1.0 - (yawDiff / (currentFOV.horizontal  * 3.5)))
        let overlapRatioPitch = max(0.0, 1.0 - (pitchDifference / currentFOV.vertical))
        var angleOverlap = CGFloat(overlapRatioYaw * overlapRatioPitch)
        if angleOverlap > 0.9 {
            angleOverlap = 1
        }
        
        let overallOverlapRatio: CGFloat = CGFloat(overlapRatioX * overlapRatioY * overlapRatioZ) * angleOverlap
        
        return overallOverlapRatio
    }
    
    func calculateFromFov(
        _ frame1: ARFrame,
        _ frame2: ARFrame,
        _ distance: Float
    ) -> CGFloat {
        
        let previousTransform = frame1.camera.transform
        let currentTransform = frame2.camera.transform
        
        // Lấy vector hướng nhìn của mỗi camera (trục Z âm của camera)
        // Get the view vector of each camera (negative Z axis of the camera)
        let col2_1: simd_float4 = previousTransform.columns.2
        let direction1 = -simd_float3(col2_1.x, col2_1.y, col2_1.z)
        
        let col2_2: simd_float4 = currentTransform.columns.2
        let direction2 = -simd_float3(col2_2.x, col2_2.y, col2_2.z)
        
        // Chiếu các vector hướng xuống mặt phẳng XZ (mặt phẳng ngang) để chỉ tính yaw
        // Project the vectors down to the XZ plane (horizontal plane) to calculate yaw only
        let flatDirection1 = SIMD2<Float>(direction1.x, direction1.z)
        let flatDirection2 = SIMD2<Float>(direction2.x, direction2.z)

        // Tính góc của mỗi vector so với trục X dương trên mặt phẳng XZ
        // Calculate the angle of each vector relative to the positive X-axis on the XZ plane
        let angle1 = atan2(flatDirection1.y, flatDirection1.x)
        let angle2 = atan2(flatDirection2.y, flatDirection2.x)

        // Tính sự khác biệt góc và chuẩn hóa về khoảng [-PI, PI]
        // Calculate the angle difference and normalize to the interval [-PI, PI]
        var yawDifference = angle2 - angle1
        while yawDifference > .pi { yawDifference -= 2 * .pi }
        while yawDifference < -.pi { yawDifference += 2 * .pi }
        let yawDiff = abs(yawDifference)
        
        let pitch1 = atan2(direction1.y, sqrt(direction1.x * direction1.x + direction1.z * direction1.z))
        let pitch2 = atan2(direction2.y, sqrt(direction2.x * direction2.x + direction2.z * direction2.z))
        let pitchDifference = abs(pitch2 - pitch1)
        
        // Get FOV of camera
        let currentImageResolution = frame2.camera.imageResolution
        let currentFOV = frame2.fieldOfView(for: currentImageResolution)
        
        // Calculate transform between two frame
        let relativeTransform = currentTransform.inverse * previousTransform
        
        // Get translation vector from relative matrix
        let translation = simd_float3(
            x: relativeTransform.columns.3.x,
            y: relativeTransform.columns.3.y,
            z: relativeTransform.columns.3.z
        )
        
        // Ước lượng tỉ lệ overlap, assumedDistance là khoảng cách muốn tính toán overlap đến một mặt phẳng ảo.
        // Giả sử ở đây là mặt phẳng ảo cách camera 1 mét.
        // Estimate the overlap ratio, assumedDistance is the distance to calculate overlap from a virtual plane.
        // Suppose here the virtual plane is 1 meter away from the camera.
        //let assumedDistance: Float = 1.0
        //let assumedDistance = calculateDynamicDistance(frame: )

        let currentViewHalfWidth = distance * tan(currentFOV.horizontal / 2)
        let currentViewHalfHeight = distance * tan(currentFOV.vertical / 2)

        let currentViewWidth = currentViewHalfWidth * 2
        let currentViewHeight = currentViewHalfHeight * 2
        
        // Tính tỉ lệ overlap trên cả 3 trục x, y, z khi di chuyển thiết bị
        // Calculate the overlap ratio on all 3 axes x, y, z when moving the device
        let overlapRatioX = max(0, 1 - abs(translation.x) / currentViewWidth)
        let overlapRatioY = max(0, 1 - abs(translation.y) / currentViewHeight)
        let overlapRatioZ = max(0, 1 - abs(translation.z) / (currentViewWidth * currentViewHeight))
        
        // Tính tỉ lệ overlap của yaw, và pitch khi xoay thiết bị
        // Calculate the overlap ratio of yaw, and pitch when rotating the device
        let overlapRatioYaw = max(0.0, 1.0 - (yawDiff / (currentFOV.horizontal  * 3.5)))
        let overlapRatioPitch = max(0.0, 1.0 - (pitchDifference / currentFOV.vertical))
        var angleOverlap = CGFloat(overlapRatioYaw * overlapRatioPitch)
        if angleOverlap > 0.9 {
            angleOverlap = 1
        }
        
        let overallOverlapRatio: CGFloat = CGFloat(overlapRatioX * overlapRatioY * overlapRatioZ) * angleOverlap
        
        return overallOverlapRatio
    }

    func calculateFromFov(
        _ frame1: FrameMetadata,
        _ frame2: ARFrame,
        _ distance: Float
    ) -> CGFloat {
        
        let previousTransform = frame1.transform
        let currentTransform = frame2.camera.transform
        
        // Lấy vector hướng nhìn của mỗi camera (trục Z âm của camera)
        // Get the view vector of each camera (negative Z axis of the camera)
        let col2_1: simd_float4 = previousTransform.columns.2
        let direction1 = -simd_float3(col2_1.x, col2_1.y, col2_1.z)
        
        let col2_2: simd_float4 = currentTransform.columns.2
        let direction2 = -simd_float3(col2_2.x, col2_2.y, col2_2.z)
        
        // Chiếu các vector hướng xuống mặt phẳng XZ (mặt phẳng ngang) để chỉ tính yaw
        // Project the vectors down to the XZ plane (horizontal plane) to calculate yaw only
        let flatDirection1 = SIMD2<Float>(direction1.x, direction1.z)
        let flatDirection2 = SIMD2<Float>(direction2.x, direction2.z)

        // Tính góc của mỗi vector so với trục X dương trên mặt phẳng XZ
        // Calculate the angle of each vector relative to the positive X-axis on the XZ plane
        let angle1 = atan2(flatDirection1.y, flatDirection1.x)
        let angle2 = atan2(flatDirection2.y, flatDirection2.x)

        // Tính sự khác biệt góc và chuẩn hóa về khoảng [-PI, PI]
        // Calculate the angle difference and normalize to the interval [-PI, PI]
        var yawDifference = angle2 - angle1
        while yawDifference > .pi { yawDifference -= 2 * .pi }
        while yawDifference < -.pi { yawDifference += 2 * .pi }
        let yawDiff = abs(yawDifference)
        
        let pitch1 = atan2(direction1.y, sqrt(direction1.x * direction1.x + direction1.z * direction1.z))
        let pitch2 = atan2(direction2.y, sqrt(direction2.x * direction2.x + direction2.z * direction2.z))
        let pitchDifference = abs(pitch2 - pitch1)
        
        // Get FOV of camera
        let currentImageResolution = frame2.camera.imageResolution
        let currentFOV = frame2.fieldOfView(for: currentImageResolution)
        
        // Calculate transform between two frame
        let relativeTransform = currentTransform.inverse * previousTransform
        
        // Get translation vector from relative matrix
        let translation = simd_float3(
            x: relativeTransform.columns.3.x,
            y: relativeTransform.columns.3.y,
            z: relativeTransform.columns.3.z
        )
        
        // Ước lượng tỉ lệ overlap, assumedDistance là khoảng cách muốn tính toán overlap đến một mặt phẳng ảo.
        // Giả sử ở đây là mặt phẳng ảo cách camera 1 mét.
        // Estimate the overlap ratio, assumedDistance is the distance to calculate overlap from a virtual plane.
        // Suppose here the virtual plane is 1 meter away from the camera.
        //let assumedDistance: Float = 1.0
        //let assumedDistance = calculateDynamicDistance(frame: )
        print(distance)

        let currentViewHalfWidth = distance * tan(currentFOV.horizontal / 2)
        let currentViewHalfHeight = distance * tan(currentFOV.vertical / 2)

        let currentViewWidth = currentViewHalfWidth * 2
        let currentViewHeight = currentViewHalfHeight * 2
        
        // Tính tỉ lệ overlap trên cả 3 trục x, y, z khi di chuyển thiết bị
        // Calculate the overlap ratio on all 3 axes x, y, z when moving the device
        let overlapRatioX = max(0, 1 - abs(translation.x) / currentViewWidth)
        let overlapRatioY = max(0, 1 - abs(translation.y) / currentViewHeight)
        let overlapRatioZ = max(0, 1 - abs(translation.z) / (currentViewWidth * currentViewHeight))
        
        // Tính tỉ lệ overlap của yaw, và pitch khi xoay thiết bị
        // Calculate the overlap ratio of yaw, and pitch when rotating the device
        let overlapRatioYaw = max(0.0, 1.0 - (yawDiff / (currentFOV.horizontal  * 3.5)))
        let overlapRatioPitch = max(0.0, 1.0 - (pitchDifference / currentFOV.vertical))
        var angleOverlap = CGFloat(overlapRatioYaw * overlapRatioPitch)
        if angleOverlap > 0.9 {
            angleOverlap = 1
        }
        
        let overallOverlapRatio: CGFloat = CGFloat(overlapRatioX * overlapRatioY * overlapRatioZ) * angleOverlap
        
        return overallOverlapRatio
    }
    
    func calculateDynamicDistance(_ depthMap: CVPixelBuffer?) -> Float {
        guard let depthMap = depthMap else {
            return 1.0
        }
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        let baseAddress = CVPixelBufferGetBaseAddress(depthMap)
        let rowBytes = CVPixelBufferGetBytesPerRow(depthMap)

        var totalDepth: Float = 0
        var pixelCount: Int = 0

        for y in 0..<height {
            let rowData = baseAddress! + y * rowBytes
            let data = rowData.assumingMemoryBound(to: Float.self)
            for x in 0..<width {
                totalDepth += data[x]
                pixelCount += 1
            }
        }

        CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)

        let averageDepth = totalDepth / Float(pixelCount)
        return averageDepth
    }
    
    func calculateFromFeaturePoints(
        _ frame1: ARFrame,
        _ frame2: ARFrame,
        _ distance: Float
    ) -> CGFloat {
        let threshold = max(distance * 0.095, MIN_THRESHOLD)
        let matchCount = matchFeaturePoints(
            points1: frame1.rawFeaturePoints?.points ?? [],
            points2: frame2.rawFeaturePoints?.points ?? [],
            threshold: threshold
        )
        let minCount = min(
            (frame1.rawFeaturePoints?.points ?? []).count,
            (frame2.rawFeaturePoints?.points ?? []).count
        )
        if minCount == 0 {
            return 1.0
        }
        let overlapRatio = CGFloat(matchCount) / CGFloat(minCount)
        return overlapRatio
    }

    func calculateFromFeaturePoints(
        _ frame1: FrameMetadata,
        _ frame2: ARFrame,
        _ distance: Float
    ) -> CGFloat {
        let threshold = max(distance * 0.095, MIN_THRESHOLD)
        let matchCount = matchFeaturePoints(
            points1: frame1.featurePoints,
            points2: frame2.rawFeaturePoints?.points ?? [],
            threshold: threshold
        )
        let minCount = min(frame1.featurePoints.count, (frame2.rawFeaturePoints?.points ?? []).count)
        if minCount == 0 {
            return 1.0
        }
        let overlapRatio = CGFloat(matchCount) / CGFloat(minCount)
        return overlapRatio
    }

    private func matchFeaturePoints(
        points1: [vector_float3],
        points2: [vector_float3],
        threshold: Float
    ) -> Int {
        var matchCount = 0
        for point1 in points1 {
            for point2 in points2 {
                let distance = simd_distance(point1, point2)
                if distance < threshold {
                    matchCount += 1
                    break
                }
            }
        }
        return matchCount
    }
}

extension FrameMetadata {
    
    func fieldOfView(for imageResolution: CGSize) -> (horizontal: Float, vertical: Float) {
        let intrinsics = self.intrinsics

        // fx, fy là độ dài tiêu cự tính bằng pixel
        let fx = intrinsics[0, 0]
        let fy = intrinsics[1, 1]

        // imageResolution.width, imageResolution.height là kích thước ảnh (pixel)
        let imageWidth = Float(imageResolution.width)
        let imageHeight = Float(imageResolution.height)

        // Tính FOV ngang và dọc
        let horizontalFOV = 2 * atan(imageWidth / (2 * fx))
        let verticalFOV = 2 * atan(imageHeight / (2 * fy))

        return (horizontal: horizontalFOV, vertical: verticalFOV)
    }
}

extension ARFrame {

    func fieldOfView(for imageResolution: CGSize) -> (horizontal: Float, vertical: Float) {
        let intrinsics = self.camera.intrinsics

        // fx, fy là độ dài tiêu cự tính bằng pixel
        let fx = intrinsics[0, 0]
        let fy = intrinsics[1, 1]

        // imageResolution.width, imageResolution.height là kích thước ảnh (pixel)
        let imageWidth = Float(imageResolution.width)
        let imageHeight = Float(imageResolution.height)

        // Tính FOV ngang và dọc
        let horizontalFOV = 2 * atan(imageWidth / (2 * fx))
        let verticalFOV = 2 * atan(imageHeight / (2 * fy))

        return (horizontal: horizontalFOV, vertical: verticalFOV)
    }

}
