//
//  Double++.swift
//  Quick3D
//
//  Created by MOR on 20/1/25.
//

import Foundation

extension Double {
    var fraction: (num : Int, den : Int) {
        let eps : Double = 1.0E-6
        var x = self
        var a = floor(x)
        var (h1, k1, h, k) = (1, 0, Int(a), 1)

        while x - a > eps * Double(k) * Double(k) {
            x = 1.0/(x - a)
            a = floor(x)
            (h1, k1, h, k) = (h, k, h1 + Int(a) * h, k1 + Int(a) * k)
        }
        return (h, k)
    }
    
    var fractionString: String {
        var x = self
        x = self.rounding()
        let f = x.fraction
        return "\(f.num)/\(f.den)"
    }
    
    var radians: Double {
        self * .pi / 180.0
    }
    
    var degrees: Double {
        self * 180.0 / .pi
    }
    
    func rounding(places: Int = 5) -> Double {
        let multiplier = pow(10.0, Double(places))
        return (self * multiplier).rounded() / multiplier
    }
    
    func string(maximumFractionDigits: Int = 2) -> String {
        let s = String(format: "%.\(maximumFractionDigits)f", self)
        for i in stride(from: 0, to: -maximumFractionDigits, by: -1) {
            if s[s.index(s.endIndex, offsetBy: i - 1)] != "0" {
                return String(s[..<s.index(s.endIndex, offsetBy: i)])
            }
        }
        return String(s[..<s.index(s.endIndex, offsetBy: -maximumFractionDigits - 1)])
    }
}
