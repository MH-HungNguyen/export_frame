//
//  ImageProcessor.swift
//  Quick3D
//
//  Created by Admin on 17/10/25.
//

import Foundation
import ARKit

final class ImageProcessor {
    static let shared = ImageProcessor()
    
    var frameQueue = FrameQueue()
    var lastFrameCache: FrameCache? = nil
    private(set) var isProcessing: Bool = false
    let imgContext = CIContext(options: [.useSoftwareRenderer: false])
    
    func resetQueue() {
        frameQueue.dequeueAll()
        lastFrameCache = nil
        isProcessing = false
    }
    
    func handleFrame(_ curFrame: ARFrame, _ fps: Int) async throws -> Int {
        let lastIndex: Int = lastFrameCache?.index ?? 0
        let curFrameCache = FrameCache(lastIndex, curFrame, fps)
        frameQueue.enqueue(curFrameCache)
        //print("Frank executionTime index: \(lastIndex), isProcessing: \(isProcessing), queue count: \(frameQueue.getCount())")
        if !isProcessing {
            Task {
                try await processFrame()
            }
        }
        return lastIndex
    }
    
    private func processFrame() async throws {
        if self.isProcessing {
            return
        }
        
        self.isProcessing = true
        
        defer {
            self.isProcessing = false
        }
        
        while let lastFrameCache = frameQueue.dequeue() {
            guard let session = CaptureSession.current else {
                break
            }
            
            guard let lastFrame = lastFrameCache.frame else {
                continue
            }
            
            do {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    // MARK: Export JPG image and write logs
                    group.addTask {
                        let startTime1 = Date()
                        let image = try await JpegImage(
                            session,
                            fileName: lastFrameCache.imageName,
                            data: lastFrame.capturedImage,
                            imgId: lastFrameCache.id,
                            imgContext: self.imgContext
                        )
                        image.setSubsecTimeOriginal(lastFrameCache.exif["SubsecTimeOriginal"] as? String)
                        image.setCoordinate(lastFrameCache.location.coordinate)
//                        if let location = lastFrameCache.rtkLocation {
//                            image.setRTKLocation(
//                                location,
//                                rtkId: RTKManager.shared.id,
//                                rtkSerialNumber: RTKManager.shared.serialNumber
//                            )
//                        }
                        
                        // Write logs
                        let metadata = try FrameMetadata(
                            lastFrame,
                            index: lastFrameCache.index,
                            fps: lastFrameCache.fps
                        )
                        session.add(metadata, image: image)
                        
                        let endTime1 = Date()
                        let executionTime1 = endTime1.timeIntervalSince(startTime1) * 1000
                        print("Frank executionTime export jpg: \(executionTime1) ms")
                    }
                    
                    // MARK: Export Confidence Tiff image
                    group.addTask {
                        let startTime2 = Date()
                        let _ = try await DepthConfidenceImage(
                            session,
                            fileName: lastFrameCache.confidenceMapImageName,
                            data: lastFrame.sceneDepth?.confidenceMap,
                            imgId: lastFrameCache.id
                        )
                        let endTime2 = Date()
                        let executionTime2 = endTime2.timeIntervalSince(startTime2) * 1000
                        print("Frank executionTime export confidence: \(executionTime2) ms")
                    }
                    
                    // MARK: Export Depth Tiff image
                    group.addTask {
                        let startTime3 = Date()
                        let _ = try await DepthImage(
                            session,
                            fileName: lastFrameCache.depthMapImageName,
                            data: lastFrame.sceneDepth?.depthMap,
                            imgId: lastFrameCache.id
                        )
                        let endTime3 = Date()
                        let executionTime3 = endTime3.timeIntervalSince(startTime3) * 1000
                        print("Frank executionTime export depth: \(executionTime3) ms")
                    }
                    
                    for try await _ in group {}
                }
            } catch {
                // Bắt lỗi của frame hiện tại để không ảnh hưởng frame sau
                print("Lỗi khi export frame \(lastFrameCache.id): \(error)")
            }
        }
    }
}
