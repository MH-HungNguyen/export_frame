//
//  String++.swift
//  export_frame
//
//  Created by HungNT on 24/11/25.
//

import Foundation

extension String {
    static func random(length: Int, letters: NSString) -> String {
        let len = UInt32(letters.length)
        var randomString = ""
        for _ in 0 ..< length {
            let rand = arc4random_uniform(len)
            var nextChar = letters.character(at: Int(rand))
            randomString += NSString(characters: &nextChar, length: 1) as String
        }
        return randomString
    }
    
    static func randomNumber(length: Int) -> String {
        return random(length: length, letters: "0123456789")
    }
    
    static func randomHexNumber(length: Int) -> String {
        return random(length: length, letters: "abcdef0123456789")
    }
}
