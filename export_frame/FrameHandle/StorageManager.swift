//
//  StorageManager.swift
//  Quick3D
//
//  Created by HaNST on 14/11/24.
//

import Foundation
import SwiftUI
import TIFF
import ZIPFoundation
import UniformTypeIdentifiers

final class StorageManager {
    
    static let shared = StorageManager()
    
    private var sessionURL: URL?
    
    private var temporaryURL: URL?
    
    var _sessionURL: URL {
        if sessionURL == nil {
            newSession()
        }
        return sessionURL!
    }
    
    var _temporaryURL: URL {
        if temporaryURL == nil {
            clearTemporaryData()
        }
        return temporaryURL!
    }
    
    private init() {
        newSession()
    }
    
    func clearSession() {
        if let url = sessionURL {
            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
            }
            sessionURL = nil
        }
    }
    
    func newSession() {
        clearTemporaryData()
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let sessionName = df.string(from: Date())
        let url = getDirectory().appendingPathComponent(sessionName)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        sessionURL = url
    }
    
    private func clearTemporaryData() {
        let url = getDirectory().appendingPathComponent("tmp")
        temporaryURL = url
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        } catch {
        }
    }
    
    private func getDirectory() -> URL {
        let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let directoryName = "Camera"
        let directoryUrl = documentDirectory.appendingPathComponent(directoryName)
        if !FileManager.default.fileExists(atPath: directoryUrl.path) {
            try? FileManager.default.createDirectory(at: directoryUrl, withIntermediateDirectories: true, attributes: nil)
        }
        return directoryUrl
    }
    
    func getFileURL(_ name: String) -> URL {
        return _sessionURL.appendingPathComponent(name)
    }
    
    func getTemporaryFileURL(_ name: String) -> URL {
        return _temporaryURL.appendingPathComponent(name)
    }
    
    func getCameraFileURL(_ name: String) -> URL {
        return getDirectory().appendingPathComponent(name)
    }
    
    func getFolder(_ name: String) -> URL {
        let folderUrl = _sessionURL.appendingPathComponent(name)
        
        if !FileManager.default.fileExists(atPath: folderUrl.path) {
            try? FileManager.default.createDirectory(at: folderUrl, withIntermediateDirectories: true, attributes: nil)
        }
        
        return folderUrl
    }
    
    func createFolder(_ name: String) -> URL? {
        guard let directoryUrl = sessionURL else { return nil }
        
        let folderUrl = directoryUrl.appendingPathComponent(name)
        
        if FileManager.default.fileExists(atPath: folderUrl.path) {
            return folderUrl
        }
        
        do {
            try FileManager.default.createDirectory(at: folderUrl, withIntermediateDirectories: true, attributes: nil)
        } catch {
            return nil
        }
        
        return folderUrl
    }
    
    func minifyJSON(_ jsonObject: Any) -> String {
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: jsonObject, options: [])
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
        } catch {
            print(error.localizedDescription)
        }
        return "{}"
    }
    
    func write(_ manifestModel: ManifestModel) {
        do {
            let jsonData = try JSONEncoder().encode(manifestModel)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
            let manifestURL = _sessionURL.appendingPathComponent("manifest.json")
            try write(manifestURL, text: jsonString)
            print("Write manifest file: \(manifestURL.path)")
        } catch {
            print("Error: \(error)")
        }
    }
    
    func zip() -> URL? {
        var destinationURL = getDirectory()
        destinationURL.appendPathComponent("\(_sessionURL.lastPathComponent).zip")
        do {
//            let items = try FileManager.default.contentsOfDirectory(at: _sessionURL, includingPropertiesForKeys: nil, options: [])
//            for item in items {
//                try FileManager.default.zipItem(at: item, to: destinationURL)
//            }

            try FileManager.default.zipItem(at: _sessionURL, to: destinationURL, shouldKeepParent: false)
            try FileManager.default.removeItem(at: _sessionURL)
            return destinationURL
        } catch {
            print("Creation of ZIP archive failed with error:\(error)")
            return nil
        }
    }
    
    func write(_ url: URL, data: Data) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            if let fileHandle = try? FileHandle(forWritingTo: url) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                fileHandle.closeFile()
            }
        } else {
            try data.write(to: url)
        }
    }
    
    func write(_ fileName: String, data: Data) throws {
        try write(getFileURL(fileName), data: data)
    }
    
    func write(_ url: URL, text: String) throws {
        guard let data = text.data(using: .utf8) else {
            return
        }
        try write(url, data: data)
    }

    func isDuplicateZipFileName(_ fileName: String) -> Bool {
        let targetFileName = "\(fileName.lowercased()).zip"
        let destinationURL = getDirectory()
            
        // 1. Get the list of items in the directory
        guard let existingFiles = try? FileManager.default.contentsOfDirectory(
            at: destinationURL,
            includingPropertiesForKeys: nil,
            options: []
        ) else {
            print("Error: Could not read directory contents.")
            return false
        }
        
        return existingFiles.contains(where: { $0.lastPathComponent.lowercased() == targetFileName })
    }
}

struct Vertex {
    let x: Float
    let y: Float
    let z: Float
    let r: Float
    let g: Float
    let b: Float
    
    init (x: Float, y: Float, z: Float, r: Float, g: Float, b: Float) {
        self.x = x
        self.y = y
        self.z = z
        self.r = r
        self.g = g
        self.b = b
    }
    
    init(_ simdVertex : SIMD3<Float>) {
        self.x = simdVertex.x
        self.y = simdVertex.y
        self.z = simdVertex.z
        self.r = 0
        self.g = 0
        self.b = 0
    }
    
//    init(_ point: ParticleUniforms) {
//        self.x = point.position.x
//        self.y = point.position.y
//        self.z = point.position.z
//        self.r = point.color.x
//        self.g = point.color.y
//        self.b = point.color.z
//    }
    
    var position: SIMD3<Float> {
        [x, y, z]
    }
    
    var color: SIMD3<Float> {
        [r, g, b]
    }
    
    var zUpPosition: SIMD3<Float> {
        [x, -z, y]
    }
    
    var zUp: Vertex {
        let position = zUpPosition
        return .init(x: position.x, y: position.y, z: position.z, r: r, g: g, b: b)
    }
}

extension StorageManager {
    
    func writeGLTFFile(fileName: String, min: [Float], max: [Float], count: Int, mode: Int, rgb: Bool) throws {
        
        let byteLength = rgb ? 24 : 12
        let size = byteLength * count
        
        var accessors : [Any] = [
            [
                "bufferView": 0,
                "byteOffset": 0,
                "componentType": 5126,
                "count": count,
                "normalized": false,
                "type": "VEC3",
                "min": min,
                "max": max
            ]
        ]
        
        if rgb {
            accessors.append([
                "type": "VEC3",
                "normalized": false,
                "componentType": 5126,
                "count": count,
                "bufferView": 0,
                "byteOffset": 12
            ])
        }
        
        let json: [String : Any] = [
            "nodes" : [
                [
                    "mesh" : 0,
                    "name": "\(fileName).gltf"
                ]
            ],
            "asset" : ["version": "2.0"],
            "buffers": [
                [
                    "uri": "\(fileName).bin",
                    "byteLength": size
                ]
            ],
            "bufferViews" : [
                [
                    "byteStride": byteLength,
                    "buffer": 0,
                    "byteOffset": 0,
                    "byteLength": size,
                    "target": 34962
                ]
            ],
            "accessors": accessors,
            "scenes": [
                [
                  "nodes": [
                    0
                  ],
                  "name": "Scene"
                ]
            ],
            "meshes": [
                [
                    "primitives": [
                        [
                            "mode": mode,
                            "attributes": rgb ? ["POSITION": 0, "COLOR_0": 1] : ["POSITION": 0]
                        ]
                    ],
                    "name": "\(fileName).gltf"
                ]
            ],
            "scene": 0
        ]
        
        guard let jsonString = try? minifyJSON(json) else { return }
        let gltfURL = getFileURL("\(fileName).gltf")
        try write(gltfURL, text: jsonString)
    }
    
    func writeGLTFFile(_ vertices: [Vertex], fileName: String, mode: Int, rgb: Bool, folderName: String = "") {
        
        var minX = Float.greatestFiniteMagnitude
        var minY = Float.greatestFiniteMagnitude
        var minZ = Float.greatestFiniteMagnitude
        var maxX = -Float.greatestFiniteMagnitude
        var maxY = -Float.greatestFiniteMagnitude
        var maxZ = -Float.greatestFiniteMagnitude
        
        var data : [Float] = []

        for vertex in vertices {
            data.append(vertex.x)
            data.append(vertex.y)
            data.append(vertex.z)
            
            if rgb {
                data.append(vertex.r)
                data.append(vertex.g)
                data.append(vertex.b)
            }
            
            minX = min(minX, vertex.x)
            minY = min(minY, vertex.y)
            minZ = min(minZ, vertex.z)
            maxX = max(maxX, vertex.x)
            maxY = max(maxY, vertex.y)
            maxZ = max(maxZ, vertex.z)
        }
        
        let binaryData = Data(data.bytes)
        
        do {
            try writeGLTFFile(fileName: "\(folderName)\(fileName)", min: [minX, minY, minZ], max: [maxX, maxY, maxZ], count: vertices.count, mode: mode, rgb: rgb)
            try write("\(folderName)\(fileName).bin", data: binaryData)
        } catch {
            print("Error: \(error)")
        }
        
    }
}
