//
//  EulerAngles.swift
//  Test4
//
//  Created by HaNST on 18/6/25.
//

import Foundation
import simd

public enum EulerAnglesOrder {
    case xyz
    case xzy
    case yxz
    case yzx
    case zxy
    case zyx
}

typealias EulerAngles = SIMD3<Double>

extension EulerAngles {
    
    var roll: Double {
        x
    }
    
    var pitch: Double {
        y
    }
    
    var yaw: Double {
        z
    }
    
    public init(_ value: SIMD3<Float>) {
        self.init(Double(value.x), Double(value.y), Double(value.z))
    }
    
    public static func clamp<T: Comparable>(_ value: T, _ minValue: T, _ maxValue: T) -> T {
        return Swift.min(Swift.max(value, minValue), maxValue)
    }
    
    public init(_ rotation: simd_double3x3, order: EulerAnglesOrder = .xyz) {
        
        let m11 = rotation.columns.0.x
        let m12 = rotation.columns.1.x
        let m13 = rotation.columns.2.x
        
        let m21 = rotation.columns.0.y
        let m22 = rotation.columns.1.y
        let m23 = rotation.columns.2.y
        
        let m31 = rotation.columns.0.z
        let m32 = rotation.columns.1.z
        let m33 = rotation.columns.2.z
        
        var x: Double
        var y: Double
        var z: Double
        
        switch order {
        case .xyz:
            y = asin(EulerAngles.clamp(m13, -1, 1));
            if (abs(m13) < 0.9999999) {
                x = atan2(-m23, m33);
                z = atan2(-m12, m11);
            } else {
                x = atan2(m32, m22);
                z = 0;
            }
            break
        case .xzy:
            z = asin(-EulerAngles.clamp(m12, -1, 1));
            if (abs(m12) < 0.9999999) {
                x = atan2(m32, m22);
                y = atan2(m13, m11);
            } else {
                x = atan2(-m23, m33);
                y = 0;
            }
            break
        case .yxz:
            x = asin(-EulerAngles.clamp(m23, -1, 1));
            if (abs(m23) < 0.9999999) {
                y = atan2( m13, m33 );
                z = atan2( m21, m22 );
            } else {
                y = atan2(-m31, m11);
                z = 0;
            }
            break
        case .yzx:
            z = asin(EulerAngles.clamp(m21, -1, 1));
            if (abs(m21) < 0.9999999) {
                x = atan2(-m23, m22);
                y = atan2(-m31, m11);
            } else {
                x = 0;
                y = atan2(m13, m33);
            }
            break
        case .zxy:
            x = asin(EulerAngles.clamp(m32, -1, 1));
            if (abs(m32) < 0.9999999) {
                y = atan2(-m31, m33);
                z = atan2(-m12, m22);
            } else {
                y = 0;
                z = atan2(m21, m11);
            }
            break
        case .zyx:
            y = asin(-EulerAngles.clamp(m31, -1, 1));
            if (abs(m31) < 0.9999999) {
                x = atan2(m32, m33);
                z = atan2(m21, m11);
            } else {
                x = 0;
                z = atan2(-m12, m22);
            }
            break
        }
        
        self.init(x, y, z)
    }
    
    func getRotationMatrix(order: EulerAnglesOrder = .xyz) -> simd_double3x3 {
        let sinx = sin(self.x)
        let cosx = cos(self.x)
        let siny = sin(self.y)
        let cosy = cos(self.y)
        let sinz = sin(self.z)
        let cosz = cos(self.z)
        
        let rx = simd_double3x3(
            simd_double3(1.0,  0.0,  0.0),
            simd_double3(0.0, cosx, sinx),
            simd_double3(0.0, -sinx,  cosx)
        )

        let ry = simd_double3x3(
            simd_double3(cosy, 0.0, -siny),
            simd_double3(0.0, 1.0,  0.0),
            simd_double3(siny, 0.0, cosy)
        )

        let rz = simd_double3x3(
            simd_double3(cosz, sinz, 0.0),
            simd_double3(-sinz, cosz, 0.0),
            simd_double3( 0.0,   0.0, 1.0)
        )
        
        switch order {
        case .xyz:
            return rx * ry * rz
        case .xzy:
            return rx * rz * ry
        case .yxz:
            return ry * rx * rz
        case .yzx:
            return ry * rz * rx
        case .zxy:
            return rz * rx * ry
        case .zyx:
            return rz * ry * rx
        }
    }

    func transform() -> EulerAngles {
        let _eulerAngles = EulerAngles(-self.z, self.x, -self.y)
        
        let _t1 = _eulerAngles.getRotationMatrix(order: .zyx)
        
        let _r1 = simd_double3x3(
            simd_double3(-1.0,  0.0,  0.0),
            simd_double3( 0.0,  1.0,  0.0),
            simd_double3( 0.0,  0.0, -1.0)
        )
        
        let _r2 = simd_double3x3(
            simd_double3( 0.0, -0.0,  1.0),
            simd_double3( 0.0,  1.0,  0.0),
            simd_double3(-1.0,  0.0,  0.0)
        )
        
        let _t2 = _t1 * _r1 * _r2
        
        return EulerAngles(_t2, order: .zyx)
    }
    
    func transform(adjustment: EulerAngles) -> EulerAngles {
        let _eulerAngles = EulerAngles(-self.z, self.x , -self.y)
        
        let _t1 = _eulerAngles.getRotationMatrix(order: .zyx)
        
        let _r1 = simd_double3x3(
            simd_double3(-1.0,  0.0,  0.0),
            simd_double3( 0.0,  1.0,  0.0),
            simd_double3( 0.0,  0.0, -1.0)
        )
        
        let _r2 = simd_double3x3(
            simd_double3( 0.0, -0.0,  1.0),
            simd_double3( 0.0,  1.0,  0.0),
            simd_double3(-1.0,  0.0,  0.0)
        )
        
        let _t = adjustment.getRotationMatrix(order: .zyx)
        
        let _t2 = _t1 * _t * _r1 * _r2 * _t
        
        return EulerAngles(_t2, order: .zyx)
    }
    
}

