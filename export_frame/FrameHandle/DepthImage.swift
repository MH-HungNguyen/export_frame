//
//  XMPImage.swift
//  Quick3D
//
//  Created by HaNST on 15/11/24.
//

import Foundation
import ImageIO
import CoreImage
import UniformTypeIdentifiers
import UIKit

// Helper để cache DateFormatter (Tránh khởi tạo lại nhiều lần)
private let tiffDateFormatter: DateFormatter = {
    let df = DateFormatter()
    df.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return df
}()

class DepthImage {
    init(
        _ session: CaptureSession,
        fileName: String,
        data: CVPixelBuffer?,
        imgId: String
    ) async throws {
        guard let pixelBuffer = data else { return }

        let fileUrl = session.url.appendingPathComponent(fileName)
        
        // Chuyển xử lý sang background thread để không chặn Main Thread (nếu gọi từ UI)
        try await Task.detached(priority: .userInitiated) {
            try DepthImage.saveDepthTiff(
                pixelBuffer: pixelBuffer,
                to: fileUrl,
                imgId: imgId
            )
        }.value
    }
    
    private static func saveDepthTiff(
        pixelBuffer: CVPixelBuffer,
        to url: URL,
        imgId: String
    ) throws {
        // 1. Tạo CIImage từ CVPixelBuffer (Zero-copy nếu có thể, rất nhanh)
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        // 2. Tạo Context để render
        // Lưu ý: workingColorSpace null và format Lf (Linear Float 32) để giữ nguyên giá trị Depth
        let ctx = CIContext(options: [.workingColorSpace : NSNull()])
        
        // Render CIImage ra CGImage (giữ nguyên định dạng 32-bit float của depth map)
        guard let cgImage = ctx.createCGImage(ciImage, from: ciImage.extent, format: .Lf, colorSpace: CGColorSpace(name: CGColorSpace.linearGray)) else {
            throw NSError(domain: "DepthImage", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot create CGImage from Depth Data"])
        }
        
        // 3. Chuẩn bị Destination để ghi file TIFF
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.tiff.identifier as CFString, 1, nil) else {
            throw NSError(domain: "DepthImage", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot create image destination"])
        }
        
        // 4. Lấy và gán Metadata (XMP)
        let metadata = DepthImage.createMetadata(imgId: imgId)
        
        // 5. Thêm ảnh và metadata vào destination
        // Chúng ta dùng CGImageDestinationAddImageAndMetadata thay vì ghi file rồi mới add metadata
        // Sửa lại đoạn destination một chút nếu muốn ép buộc KHÔNG NÉN (None)
        let options = [
            kCGImageDestinationLossyCompressionQuality: 1.0, // Max quality
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFCompression: 1 // 1 = No Compression
            ]
        ] as CFDictionary
        CGImageDestinationAddImageAndMetadata(destination, cgImage, metadata, options)
        
        // 6. Finalize (Ghi đĩa 1 lần duy nhất)
        if !CGImageDestinationFinalize(destination) {
            throw NSError(domain: "DepthImage", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to write TIFF file"])
        }
    }
    
    // Tách logic tạo Metadata ra riêng
    private static func createMetadata(imgId: String) -> CGMutableImageMetadata {
        let metadata = CGImageMetadataCreateMutable()
        
        // Đăng ký Namespace (Giả sử các hằng số này bạn đã có global)
        // Lưu ý: Nếu namespace chưa có, bạn cần định nghĩa lại hoặc bỏ qua nếu ImageIO tự handle
        DepthImage.registerNamespace(metadata)
        
        let dateString = tiffDateFormatter.string(from: Date()) as CFString
        
        // Helper nhỏ để set value cho gọn code
        func set(_ path: CFString, _ value: CFString) {
            CGImageMetadataSetValueWithPath(metadata, nil, path, value)
        }
        
        // Set các giá trị XMP
        // Lưu ý: Đảm bảo các constant XMP_... của bạn là đúng chuẩn Path
        set(XMP_MODEL as CFString, "Pix4Dcatch.iPhone15,6" as CFString)
        set(XMP_MAKE as CFString, "Apple" as CFString)
        set(XMP_CAMERA_BRAND_NAME as CFString, "Depth" as CFString)
        set(XMP_CAMERA_DEPTH_UNIT as CFString, "m" as CFString)
        set(XMP_CAMERA_DEPTH_CONFIDENCE_RANGE_MIN as CFString, "0" as CFString)
        set(XMP_CAMERA_DEPTH_CONFIDENCE_RANGE_MAX as CFString, "2" as CFString)
        set(XMP_CAMERA_DEPTH_CONFIDENCE_UNIT as CFString, "int" as CFString)
        set(XMP_CAMERA_CAPTURE_UUID as CFString, imgId as CFString)
        
        set(XMP_DATE_TIME_ORIGINAL as CFString, dateString)
        set(XMP_PHOTOSHOP_CREATED_DATE as CFString, dateString)
        set(XMP_PHOTOSHOP_CREATED_DATE_TIME as CFString, dateString)
        
        set(XMP_ORIENTATION as CFString, "1" as CFString)
        set(XMP_PHOTOMETRIC_INTERPRETATION as CFString, "1" as CFString)
        set(XMP_COMPRESSION as CFString, "1" as CFString) // 1 = No compression
        set(XMP_RESOLUTION_UNIT as CFString, "2" as CFString) // 2 = Inch
        
        return metadata
    }
    
    private static func registerNamespace(_ metadata: CGMutableImageMetadata) {
        // Nếu bạn có file constants định nghĩa các prefix này thì dùng
        // Nếu không, ImageIO thường tự động handle EXIF/TIFF standard namespaces.
        // Chỉ cần register custom namespace (CAMERA_NAMESPACE)
        if let cameraNs = CAMERA_NAMESPACE as? CFString, let prefix = XMP_CAMERA_PREFIX as? CFString {
            CGImageMetadataRegisterNamespaceForPrefix(metadata, cameraNs, prefix, nil)
        }
        // Các namespace chuẩn (Exif, TIFF, Photoshop) thường không cần register thủ công trừ khi bạn dùng custom prefix lạ.
    }
}
