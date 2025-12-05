//
//  ImageDateHelper.swift
//  Quick3D
//
//  Created by HaNST on 13/1/25.
//

import Foundation

final class ImageDataHelper {
    
    static func getOffest(_ reader: FileDataReader, start: Int, bytes: [UInt8]) throws -> Int {
        let count = reader.size
        for offset in start..<count {
            if offset + bytes.count >= count {
                break
            }
            var match = true
            for i in 0..<bytes.count {
                let d = try reader.get(offset + i)
                if bytes[i] != d {
                    match = false
                    break
                }
            }
            if match {
                return offset
            }
        }
        return -1
    }
    
    static func getTag(_ reader: FileDataReader, offset: Int, start: Int) throws -> (tag: [UInt8], type: Int, count: Int, offset: Int, value: [UInt8]) {
        
        let tagData = [UInt8](try reader.get(offset, offset+12))
        
        let tag: [UInt8] = [UInt8](tagData[0...1])
        let type = Int.bytes([UInt8](tagData[2...3]))
        let count = Int.bytes([UInt8](tagData[4...7]))
        let _valueOffset = [UInt8](tagData[8...11])
        var valueOffset = Int.bytes(_valueOffset)
        var value: [UInt8] = []
        
        let typeSize = type == 1 ? 1 :
                    type == 2 ? 1 :
                    type == 3 ? 2 :
                    type == 4 ? 4 :
                    type == 5 ? 8 :
                    type == 7 ? 1 :
                    type == 9 ? 4 :
                    type == 10 ? 8 : 0
        
        let size = typeSize * count
        
        if size <= 4 {
            valueOffset = -1
            value = _valueOffset
        } else {
            valueOffset = start + valueOffset
            value = [UInt8](try reader.get(valueOffset, valueOffset+size))
        }
        
        return (tag, type, count, valueOffset, value)
    }
    
    static func getIFD(_ reader: FileDataReader, offset: Int) throws -> (start: Int, entries: Int) {
        let IFDOffset = try getOffest(reader, start: offset, bytes: [0x00, 0x00, 0x00, 0x08])
        let entries = Int.bytes([UInt8](try reader.get(IFDOffset+4, IFDOffset+6)))
        return (start: IFDOffset + 6, entries: entries)
    }
    
    static func getGPSInfoOffset(_ reader: FileDataReader) throws -> (latitudeOffset: Int, longitudeOffset: Int, altitudeOffset: Int) {
        
        var latitudeOffset: Int = -1
        var longitudeOffset: Int = -1
        var altitudeOffset: Int = -1
        
        let startOffset = try getOffest(reader, start: 0, bytes: [0x45, 0x78, 0x69, 0x66, 0x00, 0x00]) + 6
        let ifd = try getIFD(reader, offset: startOffset)
        
        var offset: Int = ifd.start
        for _ in 0..<ifd.entries {
            let tag = try getTag(reader, offset: offset, start: startOffset)
            offset = offset + 12
            if tag.tag[0] == 0x88 && tag.tag[1] == 0x25 {
                var gpsOffset = startOffset + Int.bytes(tag.value)
                let gpsEntries = Int.bytes([UInt8]((try reader.get(gpsOffset, gpsOffset+2))))
                for _ in 0..<gpsEntries {
                    let gpsTag = try getTag(reader, offset: gpsOffset+2, start: startOffset)
                    if gpsTag.tag[0] == 0x00 && gpsTag.tag[1] == 0x02 {
                        latitudeOffset = gpsTag.offset
                    }
                    if gpsTag.tag[0] == 0x00 && gpsTag.tag[1] == 0x04 {
                        longitudeOffset = gpsTag.offset
                    }
                    if gpsTag.tag[0] == 0x00 && gpsTag.tag[1] == 0x06 {
                        altitudeOffset = gpsTag.offset
                    }
                    gpsOffset = gpsOffset + 12
                }
                break
            }
        }
        
        return (latitudeOffset: latitudeOffset, longitudeOffset: longitudeOffset, altitudeOffset: altitudeOffset)
    }
    
    static func toDMS(_ value: Double) -> (degrees: (num : Int32, den : Int32), minutes: (num : Int32, den : Int32), seconds: (num : Int32, den : Int32)) {
        let degrees = Int32(value)
        let minutes = Int32((value - Double(degrees)) * 60)
        let seconds = ((value - Double(degrees)) * 60 - Double(minutes)) * 60
        let secondsFraction = seconds.fraction
        return ((degrees, 1), (minutes, 1), (Int32(secondsFraction.num), Int32(secondsFraction.den)))
    }
    
    static func updateData(_ data: Data, offset: Int, value: (num: Int32, den:Int32)) -> Data {
        var mutatedData = data
        let numBytes = value.num.bytes
        let denBytes = value.den.bytes
        for i in 0...3 {
            mutatedData[offset + i] = numBytes[i]
        }
        for i in 4...7 {
            mutatedData[offset + i] = denBytes[i-4]
        }
        return mutatedData
    }
    
    static func updateData(_ writer: FileDataWriter, offset: Int, value: Double) throws {
        let dms = toDMS(value)
        var mutatedData = updateData(Data(count: 24), offset: 0, value: dms.degrees)
        mutatedData = updateData(mutatedData, offset: 8, value: dms.minutes)
        mutatedData = updateData(mutatedData, offset: 16, value: dms.seconds)
        try writer.write(offset: offset, data: mutatedData)
    }
    
    static func updateGPSData(_ url: URL, latitude: Double, longitude: Double) throws {
        let reader = try FileDataReader(url: url)
        let writer = FileDataWriter(url: url)
        
        let gpsInfo = try getGPSInfoOffset(reader)
        
        if gpsInfo.latitudeOffset != -1 {
            try updateData(writer, offset: gpsInfo.latitudeOffset, value: latitude)
        }
        if gpsInfo.longitudeOffset != -1 {
            try updateData(writer, offset: gpsInfo.longitudeOffset, value: longitude)
        }
    }
}
