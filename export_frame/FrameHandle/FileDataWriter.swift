//
//  FileDataWriter.swift
//  Quick3D
//
//  Created by Admin on 27/10/25.
//

import Foundation

class FileDataWriter {
    
    let url: URL
    
    init(url: URL) {
        self.url = url
    }
    
    func write(offset: Int, data: Data) throws {
        do {
            let fileHandle = try FileHandle(forUpdating: url)
            try fileHandle.seek(toOffset: UInt64(offset))
            try fileHandle.write(contentsOf: data)
            try fileHandle.synchronize()
            fileHandle.closeFile()
        } catch {
            throw error
        }
    }
}
