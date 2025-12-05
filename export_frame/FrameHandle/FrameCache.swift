//
//  FrameCache.swift
//  Quick3D
//
//  Created by HungNT on 27/11/25.
//

import Foundation
import ARKit

struct FrameCache {
    let id: String = String.randomHexNumber(length: 16)
    var index: Int = 0
    var frame: ARFrame? = nil
    
    let fps: Int
    let exif: [String: Any]
    
    let gpsLocation: LocationModel
    let rtkLocation: LocationModel?
    var location: LocationModel {
        rtkLocation ?? gpsLocation
    }
    
    init(_ index: Int, _ frame: ARFrame? = nil, _ fps: Int) {
        self.index = index
        self.frame = frame
        self.fps = fps
        
        if #available(iOS 16.0, *) {
            self.exif = frame?.exifData ?? [:]
        } else {
            self.exif = [:]
        }
        
        self.gpsLocation = LocationModel()//LocationManager.shared.gpsLocation
        self.rtkLocation = LocationModel()//LocationManager.shared.rtkLocation
    }
}

extension FrameCache {
    var imageName: String {
        String(format: "Image_%06d.jpg", index)
    }
    
    var imageNameWithoutExtension: String {
        String(format: "Image_%06d", index)
    }
    
    var depthMapImageName: String {
        String(format: "DepthMap_%06d.tiff", index)
    }
    
    var confidenceMapImageName: String {
        String(format: "Confidence_%06d.tiff", index)
    }
}
