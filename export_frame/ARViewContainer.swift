//
//  ARViewContainer.swift
//  export_frame
//
//  Created by HungNT on 21/11/25.
//
import Foundation
import ARKit
import SceneKit
import SwiftUI

// Struct đại diện cho ARSCNView trong SwiftUI
struct ARViewContainer: UIViewRepresentable {
    let arView = ARSCNView(frame: .zero)
    @ObservedObject var arDelegate: ARDataDelegate
    
    // Tạo ARSCNView và cấu hình AR Session
    func makeUIView(context: Context) -> ARSCNView {
        print("Frank makeUIView ARViewContainer")
        
        // 1. Cấu hình ARWorldTrackingConfiguration
        let configuration = ARWorldTrackingConfiguration()
        
        // Bật phát hiện mặt phẳng ngang và dọc
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
        configuration.sceneReconstruction = .meshWithClassification
        configuration.isAutoFocusEnabled = true
        
        if #available(iOS 16.0, *), let recommendedFormat = ARWorldTrackingConfiguration.recommendedVideoFormatForHighResolutionFrameCapturing {
                configuration.videoFormat = recommendedFormat
        }
        
        // Cài đặt Delegate để nhận thông báo khi có mặt phẳng mới
        //arView.delegate = context.coordinator
        arView.session.delegate = arDelegate
        //arDelegate.arSession = arView.session
        
        // Tùy chọn: Hiển thị các điểm đặc trưng (feature points) để debug
        //arView.debugOptions = [ARSCNDebugOptions.showFeaturePoints]
        
        // Chạy AR Session
        arView.session.run(configuration)
        
        return arView
    }
    
    func pauseSession() {
        arView.session.pause()
        print("ARSession: PAUSED") // This fixes the warning
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}

    // 2. Tạo Coordinator để xử lý các sự kiện Delegate
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    // Coordinator Class
    class Coordinator: NSObject, ARSCNViewDelegate {
        
        // 1. NEW ANCHOR ADDED
        func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
            
        }
        
        // 2. ANCHOR UPDATED
        func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
            
        }

        // 3. ANCHOR REMOVED
        func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
            
        }
    }
}
