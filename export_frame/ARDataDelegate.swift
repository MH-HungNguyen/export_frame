//
//  ARDataDelegate.swift
//  ShadowExp
//
//  Created by HungNT on 31/10/25.
//

import ARKit
import SwiftUI
import Combine

final class ARDataDelegate: NSObject, ARSessionDelegate, ObservableObject, TaskDelegate {
    
    // Thuộc tính @Published để thông báo cho SwiftUI khi frame thay đổi
    @Published var currentFrame: ARFrame?
    
    // Thuộc tính @Published để gửi các cảnh báo (ví dụ: mất theo dõi)
    @Published var trackingState: ARCamera.TrackingState?
    
    @Published var currentIndex: Int = 0
    @Published var isCapture: Bool = false
    
    private var lastFrame: ARFrame? = nil
    private let overlapCalculator: OverlapCalculator = FovOverlapCalculator()
    
    private var startTime: Date = Date()
    private var endTime: Date = Date()
    private var overlapRatio: CGFloat = 0.0
    
    private var imageProcessor: ImageProcessor = ImageProcessor()
    private var isProcessing = false
    
    // Renderer properties (will need to be set/bound in the Renderer class)
    @Published var confidenceThreshold: Int = 1 // Default to Medium
    @Published var rgbRadius: Float = 0//0.5
    @Published var pickFrames: Int = 5
    
    var renderer: Renderer?
    var arSession: ARSession?
    
    override init() {
        try! CaptureSession.start()
    }

    // Hàm delegate chính được gọi mỗi khi có frame mới
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        
        if arSession == nil {
            arSession = session
        }
        
        if !isCapture {
            return
        }
        
        switch frame.camera.trackingState {
            case .normal:
                break
            default:
                return
        }
        
        if self.isProcessing { return }
        
        isProcessing = true
        
        Task { [weak self] in
            defer {
                self?.isProcessing = false
            }
            
            guard let self = self,
                  let captureSession = CaptureSession.current else { return }
            
            let fps: Int = session.configuration?.videoFormat.framesPerSecond ?? 0
            
            guard let lastFrameCache = ImageProcessor.shared.lastFrameCache, let lastFrame = lastFrameCache.frame else {
                ImageProcessor.shared.lastFrameCache = FrameCache(0, frame, fps)
                return
            }
            
            let distance = overlapCalculator.calculateDynamicDistance(frame.sceneDepth?.depthMap)
            let pointsCount = frame.rawFeaturePoints?.points.count ?? 0

            let overlapRatio: CGFloat
            if pointsCount <= 250 {
                overlapRatio = overlapCalculator.calculateFromFov(lastFrame, frame, distance)
            } else {
                overlapRatio = overlapCalculator.calculateFromFeaturePoints(lastFrame, frame, distance)
            }
            //print("Frank overlapRatio: \(overlapRatio)")
            if overlapRatio > captureSession.overlapRate {
                return
            }
            
            if #available(iOS 16.0, *), captureSession.imageResolution == .maximum {
                let highFrame = try await session.captureHighResolutionFrame()
                ImageProcessor.shared.lastFrameCache = FrameCache(lastFrameCache.index + 1, highFrame, fps)
                guard let lastIndex = try? await ImageProcessor.shared.handleFrame(highFrame, fps) else { return  }
                await MainActor.run {
                    self.currentIndex = lastIndex
                }
            } else {
                ImageProcessor.shared.lastFrameCache = FrameCache(lastFrameCache.index + 1, frame, fps)
                guard let lastIndex = try? await ImageProcessor.shared.handleFrame(frame, fps) else { return  }
                await MainActor.run {
                    self.currentIndex = lastIndex
                }
            }
        }
    }
    
    // (Tùy chọn) Thêm các hàm delegate khác nếu cần, ví dụ:
    func session(_ session: ARSession, didFailWithError error: Error) {
        print("AR Session Lỗi: \(error.localizedDescription)")
    }
    
    // MARK: - TaskDelegate
    func didStartTask() {
    }
    
    func didFinishTask() {
    }
}
