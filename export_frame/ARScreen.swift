//
//  ARScreen.swift
//  ShadowExp
//
//  Created by HungNT on 23/10/25.
//

import SwiftUI
import AVFoundation
import UIKit
import Combine

struct ARScreen: View {
    @Environment(\.dismiss) var dismiss
    
    @StateObject var arDelegate = ARDataDelegate()
    
    @State private var isStarted: Bool = false
    
    var body: some View {
        ZStack {
            
            ARViewContainer(arDelegate: arDelegate)
            .edgesIgnoringSafeArea(.all)
            .onDisappear {
                //arViewContainer.pauseSession()
            }
            
            VStack {
                Spacer()
                
                if arDelegate.isCapture {
                    MetalARView(manager: arDelegate)
                        .frame(height: 400)
                }
                
                Spacer()
                    .frame(height: 20)
                
                Text("Index count: \(arDelegate.currentIndex)")
                    .foregroundColor(.white)
                    .background(.gray)
                
                Button {
                    arDelegate.isCapture.toggle()
                    if !arDelegate.isCapture {
                        dismiss()
                    }
                    //print("Frank isCapture: \(arDelegate.isCapture)")
                    arDelegate.renderer?.isRecording = !arDelegate.isCapture
                } label: {
                    Text(arDelegate.isCapture ? "Stop" : "Start")
                        .foregroundColor(.white)
                        .font(.headline)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 30)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(arDelegate.isCapture ? Color.red : Color.blue)
                        )
                }
            }
        }
        .onAppear {
            checkCamera(authorized: {}, unauthorized: {})
        }
    }
    
    func checkCamera(authorized: (() -> Void)?, unauthorized: (() -> Void)?) {
        let status =  AVCaptureDevice.authorizationStatus(for: .video)
        switch(status){
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video, completionHandler: {accessGranted in
                    if !accessGranted {
                        unauthorized?()
                    } else {
                        authorized?()
                    }
                })
                break
            case .denied:
                unauthorized?()
                break
            case .restricted, .authorized:
                authorized?()
                break
            @unknown default: break
        }
    }
}
