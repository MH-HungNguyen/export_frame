//
//  ManifestModel.swift
//  Quick3D
//
//  Created by MOR on 26/11/24.
//

import Foundation

struct ManifestModel: Codable {
    var logFiles: [String]
    var inputs: [ImageOutputModel]
    
    enum CodingKeys: String, CodingKey {
        case logFiles = "log_files"
        case inputs = "inputs"
    }
    
    mutating func appendLogFile(_ file: String) {
        self.logFiles.append(file)
    }
    
    mutating func appendImage(_ image: ImageOutputModel) {
        self.inputs.append(image)
    }
}

struct ImageOutputModel: Codable {
    let depthMap: String
    let photo: String
    let depthMapConfidence: String
    
    enum CodingKeys: String, CodingKey {
        case depthMap = "depth_map"
        case depthMapConfidence = "depth_map_confidence"
        case photo = "photo"
    }
}
