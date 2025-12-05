//
//  DepthConfidenceImage.swift
//  Quick3D
//
//  Created by HungNT on 25/11/25.
//

import Foundation
import ImageIO
import CoreImage
import UniformTypeIdentifiers
import UIKit

class DepthConfidenceImage {
    
    // MARK: - Static Resources
    // Cache DateFormatter để tránh khởi tạo nhiều lần (Performance Boost)
    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return df
    }()
    
    // Define Custom Errors
    enum DepthError: Error {
        case missingData
        case cannotCreateDestination
        case cannotCreateImage
        case saveFailed
    }

    // MARK: - Init
    init(
        _ session: CaptureSession,
        fileName: String,
        data: CVPixelBuffer?,
        imgId: String
    ) async throws {
        guard let pixelBuffer = data else {
            throw DepthError.missingData
        }
        
        let fileUrl = session.url.appendingPathComponent(fileName)
        
        // 1. Tạo CIImage từ CVPixelBuffer (Zero-copy nếu có thể)
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        // Chuyển đổi sang CGImage để ghi
        // Lưu ý: CIContext tốn kém, nên cache CIContext trong singleton nếu gọi hàm này liên tục.
        // Ở đây tạo mới tạm thời cho đơn giản.
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            throw DepthError.cannotCreateImage
        }

        // 2. Chuẩn bị Image Destination (TIFF)
        guard let destination = CGImageDestinationCreateWithURL(
            fileUrl as CFURL,
            UTType.tiff.identifier as CFString,
            1,
            nil
        ) else {
            throw DepthError.cannotCreateDestination
        }
        
        // 3. Chuẩn bị Metadata (XMP + TIFF Properties)
        let xmpMetadata = createXMPMetadata(imgId)
        
        // Cấu hình TIFF Properties (Compression, Orientation...)
        // Tương đương với logic cũ: Compression = 1 (None), Photometric = 1 (BlackIsZero)
        let tiffDictionary: [String: Any] = [
            kCGImagePropertyTIFFCompression as String: 1,
            kCGImagePropertyTIFFPhotometricInterpretation as String: 1, // BlackIsZero
            kCGImagePropertyTIFFResolutionUnit as String: 2,
            kCGImageDestinationLossyCompressionQuality as String: 1.0,
        ]
        
        let properties: [String: Any] = [
            kCGImagePropertyTIFFDictionary as String: tiffDictionary
        ]

        // 4. Thêm ảnh và Metadata cùng lúc (Single Pass Write)
        // Hàm này gộp cả Image pixel data và XMP metadata vào file TIFF
        CGImageDestinationAddImageAndMetadata(
            destination,
            cgImage,
            xmpMetadata,
            properties as CFDictionary
        )
        
        // 5. Finalize (Ghi xuống đĩa)
        if !CGImageDestinationFinalize(destination) {
            throw DepthError.saveFailed
        }
    }
    
    // MARK: - Metadata Helpers
    private func createXMPMetadata(_ imgId: String) -> CGMutableImageMetadata {
        let metadata = CGImageMetadataCreateMutable()
        
        // Register Namespaces
        registerNamespace(metadata)
        
        // Common Values
        let dateString = Self.dateFormatter.string(from: Date()) as CFString
        
        // Helper để set value ngắn gọn hơn
        func setTag(_ path: String, _ value: String) {
            CGImageMetadataSetValueWithPath(metadata, nil, path as CFString, value as CFString)
        }
        
        // Pix4D / Camera Specific
        setTag(XMP_MODEL, "Pix4Dcatch.iPhone15,6")
        setTag(XMP_MAKE, "Apple")
        setTag(XMP_CAMERA_BRAND_NAME, "DepthConfidence")
        setTag(XMP_CAMERA_DEPTH_CONFIDENCE_RANGE_MIN, "0")
        setTag(XMP_CAMERA_DEPTH_CONFIDENCE_RANGE_MAX, "2")
        setTag(XMP_CAMERA_DEPTH_CONFIDENCE_UNIT, "int")
        setTag(XMP_CAMERA_CAPTURE_UUID, imgId)
        
        // Date Times
        setTag(XMP_DATE_TIME_ORIGINAL, dateString as String)
        setTag(XMP_PHOTOSHOP_CREATED_DATE, dateString as String)
        setTag(XMP_PHOTOSHOP_CREATED_DATE_TIME, dateString as String)
        
        // Technical Specs
        setTag(XMP_ORIENTATION, "1")
        setTag(XMP_PHOTOMETRIC_INTERPRETATION, "1")
        setTag(XMP_COMPRESSION, "1")
        setTag(XMP_RESOLUTION_UNIT, "2")
        
        return metadata
    }
    
    private func registerNamespace(_ metadata: CGMutableImageMetadata) {
        // Giả sử CAMERA_NAMESPACE và XMP_CAMERA_PREFIX là các hằng số global đã định nghĩa ở đâu đó
        CGImageMetadataRegisterNamespaceForPrefix(metadata, CAMERA_NAMESPACE, XMP_CAMERA_PREFIX, nil)
        
        // Các namespace chuẩn của hệ thống
        CGImageMetadataRegisterNamespaceForPrefix(metadata, kCGImageMetadataNamespacePhotoshop, kCGImageMetadataPrefixPhotoshop, nil)
        CGImageMetadataRegisterNamespaceForPrefix(metadata, kCGImageMetadataNamespaceExif, kCGImageMetadataPrefixExif, nil)
        CGImageMetadataRegisterNamespaceForPrefix(metadata, kCGImageMetadataNamespaceExifEX, kCGImageMetadataPrefixExifEX, nil)
        CGImageMetadataRegisterNamespaceForPrefix(metadata, kCGImageMetadataNamespaceTIFF, kCGImageMetadataPrefixTIFF, nil)
    }
}
