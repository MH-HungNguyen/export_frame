//
//  Ext.swift
//  export_frame
//
//  Created by HungNT on 24/11/25.
//

import Foundation
import simd

func make_simd_float3(_ vector: simd_float4) -> simd_float3 {
    return [vector.x, vector.y, vector.z]
}

extension Int32 {
    var bytes: [UInt8] {
        var _value = self
        let bytePointer = withUnsafeBytes(of: &_value) { Array($0) }
        return bytePointer.reversed()
    }
}

extension Int {
    static func bytes(_ bytes: [UInt8]) -> Int {
        if bytes.count == 2 {
            var value: UInt16 = 0
            (Data(bytes) as NSData).getBytes(&value, length: 2)
            value = UInt16(bigEndian: value)
            return Int(value)
        }
        if bytes.count == 4 {
            var value: UInt32 = 0
            (Data(bytes) as NSData).getBytes(&value, length: 4)
            value = UInt32(bigEndian: value)
            return Int(value)
        }
        return 0
    }
}

extension [Float] {
    var bytes: [UInt8] {
        var array = [UInt8]()
        for f in self {
            array += f.bytes
        }
        return array
    }
}

extension Float {
    var bytes: [UInt8] {
        withUnsafeBytes(of: self, Array.init)
    }
}

let pixelSize = 2.6 * 0.001
