//
//  CaptureSession.swift
//  Quick3D
//
//  Created by HaNST on 16/10/25.
//

import Foundation
import ARKit
import ZIPFoundation

fileprivate func getCameraDirectory() throws -> URL {
    let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let directoryName = "Camera"
    let directoryUrl = documentDirectory.appendingPathComponent(directoryName)
    if !FileManager.default.fileExists(atPath: directoryUrl.path) {
        try FileManager.default.createDirectory(at: directoryUrl, withIntermediateDirectories: true, attributes: nil)
    }
    return directoryUrl
}

class CaptureSession {
    
    private static let queue = DispatchQueue(label: "ltd.landlog.scquick3d.CaptureSession", attributes: [])
    
    static var current: CaptureSession?
    
    static func start(_ isRTK: Bool = false, onFileError: ((Error) -> Void)? = nil) throws {
        if let session = current {
            session.clear()
        }
        current = try .init(isRTK, onFileError: onFileError)
        current?.imageResolution = .maximum
        current?.overlapRate = 0.9
    }
    
    static func stop() {
        current?.clear()
        current = nil
    }
    
    func clear() {
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }
    
    actor FrameActor {
        private var frames: [FrameMetadata] = []
        private var images: [JpegImage] = []
        
        func add(_ frame: FrameMetadata, image: JpegImage) {
            frames.append(frame)
            images.append(image)
        }
        
        func getFrames() -> [FrameMetadata] {
            return frames
        }
        
        func getImages() -> [JpegImage] {
            return images
        }
    }
    
    actor StorageActor {
        
        func write(_ data: Data, url: URL, override: Bool = false) throws {
            if override && FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            return try StorageManager.shared.write(url, data: data)
        }
        
        func waiting() {
        }
        
    }
    
    let id = UUID()
    
    var name: String
    let url: URL
    
    let isRTK: Bool
    
    let onFileError: ((Error) -> Void)?
    
//    let frames: FrameActor = .init()
    let storage: StorageActor = .init()
    
    var last: FrameMetadata? = nil
    var isProcessing: Bool = false
    
    var imageResolution: ImageResolutionEnum = .maximum
    
    var overlapRate = 0.8
    
    var frames: [FrameMetadata] = []
    
    var images: [JpegImage] = []
    
    init(_ isRTK: Bool, onFileError: ((Error) -> Void)? = nil) throws {
        self.isRTK = isRTK
        self.onFileError = onFileError
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        self.name = df.string(from: Date())
        self.url = try getCameraDirectory().appendingPathComponent(self.name)
        try FileManager.default.createDirectory(at: self.url, withIntermediateDirectories: true, attributes: nil)
    }
    
    func add(_ frame: FrameMetadata, image: JpegImage) {
        Self.queue.sync {
            frames.append(frame)
            images.append(image)
        }
    }
    
    func getGPSFolderURL() -> URL {
        let folderUrl = url.appendingPathComponent("_gps")
        if !FileManager.default.fileExists(atPath: folderUrl.path) {
            try? FileManager.default.createDirectory(at: folderUrl, withIntermediateDirectories: true, attributes: nil)
        }
        return folderUrl
    }
}

extension CaptureSession {
    func zip() throws -> URL {
        var destinationURL = try getCameraDirectory()
        destinationURL.appendPathComponent("\(name)-save.zip")
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.zipItem(at: url, to: destinationURL, shouldKeepParent: false)
            try FileManager.default.removeItem(at: url)
        } else {
            throw NSError(domain: "CaptureSession", code: 0, userInfo: [NSLocalizedDescriptionKey: "Session folder not found."])
        }
        return destinationURL
    }
    
    func zipWithProgress(onProgress: @escaping (Double) -> Void) throws -> URL {
        var destinationURL = try getCameraDirectory()
        destinationURL.appendPathComponent("\(name).zip")

        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: url.path) else {
            throw NSError(domain: "CaptureSession", code: 0, userInfo: [
                NSLocalizedDescriptionKey: "Session folder not found."
            ])
        }

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        let archive = try Archive(url: destinationURL, accessMode: .create)

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: []
        ) else { return destinationURL }

        var totalSize: Int64 = 0
        var fileList: [URL] = []

        for case let fileURL as URL in enumerator {
            if let isFile = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile, isFile == true {
                if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += Int64(size)
                }
                fileList.append(fileURL)
            }
        }

        guard totalSize > 0 else { return destinationURL }

        var processedSize: Int64 = 0
        var lastReportedProgress: Double = 0

        for fileURL in fileList {
            let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            var relativePath = fileURL.path.replacingOccurrences(of: url.path + "/", with: "")
            if relativePath.hasPrefix("/private") {
                relativePath = String(relativePath.dropFirst("/private".count))
            }
            let fileProgress = Progress(totalUnitCount: Int64(fileSize))

            let observer = fileProgress.observe(\.completedUnitCount) { progress, _ in
                let newProcessed = processedSize + progress.completedUnitCount
                let ratio = Double(newProcessed) / Double(totalSize)

                // Only update if progress increased at least 0.001
                if ratio - lastReportedProgress > 0.001 {
                    lastReportedProgress = ratio
                    DispatchQueue.main.async {
                        onProgress(ratio)
                    }
                }
            }

            try archive.addEntry(
                with: relativePath,
                fileURL: fileURL,
                compressionMethod: .deflate,
                progress: fileProgress
            )

            processedSize += Int64(fileSize)
            observer.invalidate()
        }

        DispatchQueue.main.async { onProgress(1.0) }

        try fileManager.removeItem(at: url)
        return destinationURL
    }
}
