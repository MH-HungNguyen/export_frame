//
//  EulerAnglesModel.swift
//  export_frame
//
//  Created by HungNT on 24/11/25.
//

import Foundation
import CoreLocation
import simd

class EulerAnglesModel: NSObject {
    var yaw: Double
    var roll: Double
    var pitch: Double
    
    init(yaw: Double, roll: Double, pitch: Double) {
        self.yaw = yaw
        self.roll = roll
        self.pitch = pitch
    }
    
    func setAngles(_ model: EulerAnglesModel) {
        self.yaw = model.yaw
        self.roll = model.roll
        self.pitch = model.pitch
    }
    
    static func get(eulerAngles: simd_float3) -> EulerAnglesModel {
        let x = -Double(eulerAngles.z)
        let y = Double(eulerAngles.x)
        let z = -Double(eulerAngles.y)
        return EulerAnglesModel(yaw: z.degrees, roll: x.degrees, pitch: y.degrees)
    }
    
    static func transform(eulerAngles: simd_float3) -> EulerAnglesModel {
        let x = -Double(eulerAngles.z)
        let y = Double(eulerAngles.x)
        let z = -Double(eulerAngles.y)

        let sinx = sin(x)
        let cosx = cos(x)
        let siny = sin(y)
        let cosy = cos(y)
        let sinz = sin(z)
        let cosz = cos(z)
        
        let rx = simd_double3x3(
            simd_double3(1.0,  0.0,  0.0),
            simd_double3(0.0, cosx, -sinx),
            simd_double3(0.0, sinx,  cosx)
        )

        let ry = simd_double3x3(
            simd_double3( cosy, 0.0, siny),
            simd_double3(  0.0, 1.0,  0.0),
            simd_double3(-siny, 0.0, cosy)
        )

        let rz = simd_double3x3(
            simd_double3(cosz, -sinz, 0.0),
            simd_double3(sinz,  cosz, 0.0),
            simd_double3( 0.0,   0.0, 1.0)
        )

        let rotationMatrix = rx * ry * rz
        
        let r1 = simd_double3x3(
            simd_double3(0.0, 0.0, -1.0),
            simd_double3(0.0, 1.0,  0.0),
            simd_double3(1.0, 0.0,  0.0)
        )
        
        let r2 = simd_double3x3(
            simd_double3(-1.0, 0.0,  0.0),
            simd_double3( 0.0, 1.0,  0.0),
            simd_double3( 0.0, 0.0, -1.0)
        )
        
        let combinedRotationMatrix = r1 * r2 * rotationMatrix
        
        let r11 = combinedRotationMatrix.columns.0.x
        let r12 = combinedRotationMatrix.columns.0.y
        let r13 = combinedRotationMatrix.columns.0.z
        let r21 = combinedRotationMatrix.columns.1.x
        let r22 = combinedRotationMatrix.columns.1.y
        let r23 = combinedRotationMatrix.columns.1.z
        let r31 = combinedRotationMatrix.columns.2.x
        let r32 = combinedRotationMatrix.columns.2.y
        let r33 = combinedRotationMatrix.columns.2.z
        
        let combinedPitch = asin(-r31)
        var combinedYaw: Double
        var combinedRoll: Double
        if abs(r31) < 1.0 {
            combinedYaw = atan2(r21, r11)
            combinedRoll = atan2(r32, r33)
        } else {
            combinedYaw = atan2(-r12, r22)
            combinedRoll = 0.0
        }
        return EulerAnglesModel(yaw: combinedYaw.degrees, roll: combinedRoll.degrees, pitch: combinedPitch.degrees)
    }
}
