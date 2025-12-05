//
//  FileDataReader.swift
//  Quick3D
//
//  Created by HaNST on 27/10/25.
//

import Foundation

class FileDataReader {
    private var data: Data = Data()
    private var offset: Int = -1
    
    let bufferSize: Int
    let url: URL
    let size: Int
    
    init(url: URL, bufferSize: Int = 1000) throws {
        self.bufferSize = bufferSize
        self.url = url
        self.size = try FileDataReader.getSize(url)
    }
    
    func get(_ index: Int) throws -> UInt8 {
        try fetch(index)
        return data[index]
    }
    
    func get(_ start: Int, _ end: Int) throws -> Data {
        try fetch(end)
        return data[start..<end]
    }
    
    func fetch(_ index: Int) throws {
        while index > offset {
            try fetch()
        }
    }
    
    func fetch() throws {
        do {
            let fileHandle = try FileHandle(forReadingFrom: url)
            if offset < 0 {
                offset = 0
            }
            try fileHandle.seek(toOffset: UInt64(offset))
            let data = try fileHandle.read(upToCount: bufferSize)
            fileHandle.closeFile()
            
            if let data = data {
                self.data.append(data)
                offset = self.data.count
            } else {
                throw NSError(domain: "FileDataReader", code: 0, userInfo: [NSLocalizedDescriptionKey: "Cannot read file."])
            }
        } catch {
            throw error
        }
    }
    
    static func getSize(_ url: URL) throws -> Int {
        do {
            let fileHandle = try FileHandle(forReadingFrom: url)
            let fileSize =  try fileHandle.seekToEnd()
            fileHandle.closeFile()
            return Int(fileSize)
        } catch {
            throw error
        }
    }
}
