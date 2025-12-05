//
//  JpegImage.swift
//  Quick3D
//
//  Created by HaNST on 15/11/24.
//

import Foundation
import UniformTypeIdentifiers
import SwiftUI
import ImageIO

// Helper để cache DateFormatter (Tránh khởi tạo lại nhiều lần)
private let jpgDateFormatter: DateFormatter = {
    let df = DateFormatter()
    df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
    return df
}()

final class JpegImage {
    private var fileURL: URL?
    private var latitude: Double = 0.0
    private var longitude: Double = 0.0
    private var metadata: CGMutableImageMetadata? = nil
    private var isRTK = false
    
    init(
        _ session: CaptureSession,
        fileName: String,
        data: CVPixelBuffer,
        imgId: String,
        imgContext: CIContext
    ) async throws {
        fileURL = session.url.appendingPathComponent(fileName)
        
        let ciImage = CIImage(cvPixelBuffer: data)
        let colorSpace = ciImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        
        let options: [CIImageRepresentationOption: Any] = [
            kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.8
        ]

        guard let jpegData = imgContext.jpegRepresentation(
            of: ciImage,
            colorSpace: colorSpace,
            options: options
        ) else {
             throw NSError(domain: "JpegImage", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create JPEG Data"])
        }
        
        // Write data directly
        try jpegData.write(to: self.fileURL!, options: .atomic)
        
        // Init metadata
        metadata = CGImageMetadataCreateMutable()
        // Register Namespaces
        registerNamespace(metadata!)
        
        setTag(XMP_MODEL, "Pix4Dcatch.iPhone15,6")
        setTag(XMP_MAKE, "Apple")
        setTag(XMP_CAMERA_CAPTURE_UUID, imgId)
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
    
    // Helper để set value ngắn gọn hơn
    func setTag(_ path: String, _ value: String) {
        guard let _metadata = metadata else {
            return
        }
        CGImageMetadataSetValueWithPath(_metadata, nil, path as CFString, value as CFString)
    }
    
    func setSubsecTimeOriginal(_ time: String?) {
        if let t = time {
            setTag(XMP_SUBSEC_TIME_ORIGINAL, t)
        }
    }
    
    func setCoordinate(_ coordinate: String) {
        setTag(XMP_CAMERA_HORIZ_CS, coordinate)
        setTag(XMP_CAMERA_VERT_CS, "ellipsoidal")
    }
    
    func setRTKLocation(
        _ location: LocationModel,
        rtkId: String? = nil,
        rtkSerialNumber: String? = nil
    ) {
        setTag(XMP_CAMERA_RTK_ALTITUDE, "\(location.altitude)")
        setTag(XMP_CAMERA_RTK_LONGITUDE, "\(location.longitude)")
        setTag(XMP_CAMERA_RTK_LATITUDE, "\(location.latitude)")
        setTag(XMP_CAMERA_RTK_XY_ACCURACY, "\(location.horizontal)")
        setTag(XMP_CAMERA_RTK_Z_ACCURACY, "\(location.vertical)")
        
        setTag(XMP_CAMERA_RTK_YAW, "0.0")
        setTag(XMP_CAMERA_RTK_ROLL, "0.0")
        setTag(XMP_CAMERA_RTK_PITCH, "0.0")
        setTag(XMP_CAMERA_RTK_MODEL, "newVidoc")
        
        if let id = rtkId {
            setTag(XMP_CAMERA_RTK_ID, id)
        }
        if let serialNumber = rtkSerialNumber {
            setTag(XMP_CAMERA_RTK_SERIAL_NUMBER, serialNumber)
        }
        
        self.isRTK = true
    }
    
    func setGPSLocation(_ location: LocationModel) {
        let altitude = abs(location.altitude).fractionString
        let altitudeRef = location.altitude >= 0 ? "0": "1"
        self.longitude = abs(location.longitude)
        let longitudeRef = location.longitude > 0 ? "E" : "W"
        self.latitude = abs(location.latitude)
        let latitudeRef = location.latitude > 0 ? "N" : "S"
        
        setTag(XMP_CAMERA_GPS_ALTITUDE, altitude)
        setTag(XMP_CAMERA_GPS_ALTITUDE_REF, altitudeRef)
        setTag(XMP_CAMERA_GPS_LONGITUDE, "\(longitude)")
        setTag(XMP_CAMERA_GPS_LONGITUDE_REF, longitudeRef)
        setTag(XMP_CAMERA_GPS_LATITUDE, "\(latitude)")
        setTag(XMP_CAMERA_GPS_LATITUDE_REF, latitudeRef)
        
        setTag(XMP_CAMERA_GPS_XY_ACCURACY, "\(location.horizontal)")
        setTag(XMP_CAMERA_GPS_Z_ACCURACY, "\(location.vertical)")
    }
    
    func setFocalLengthPixel(
        _ focalLength: Double,
        _ principalPointX: Double,
        _ principalPointY: Double
    ) {
        let f = (focalLength * pixelSize).rounding(places: 4)
        let x = (principalPointX * pixelSize).rounding(places: 4)
        let y = (principalPointY * pixelSize).rounding(places: 4)
        setTag(XMP_CAMERA_FOCAL_LENGTH, f.fractionString)
        setTag(XMP_CAMERA_PERSPECTIVE_FOCAL_LENGTH, "\(f)")
        setTag(XMP_CAMERA_PRINCIPAL_POINT, "\(x),\(y)")
        setTag(XMP_CAMERA_MODEL_TYPE, "perspective")
        setTag(XMP_CAMERA_PERSPECTIVE_DISTORTION, "0.000001,0.0,0.0,0.0,0.0")
        setTag(XMP_CAMERA_FOCAL_PLANE_RESOLUTION_UNIT, "4")
        setTag(XMP_CAMERA_FOCAL_PLANE_X_RESOLUTION, "3998077/10395")
        setTag(XMP_CAMERA_FOCAL_PLANE_Y_RESOLUTION, "3998077/10395")
    }
    
    func setEulerAngles(eulerAngles: EulerAngles) {
        setTag(XMP_CAMERA_YAW, "\(eulerAngles.yaw)")
        setTag(XMP_CAMERA_ROLL, "\(eulerAngles.roll)")
        setTag(XMP_CAMERA_PITCH, "\(eulerAngles.pitch)")
    }
    
    func export() throws {
        guard let imgUrl = fileURL else {
            return
        }
        
        let dateStr = jpgDateFormatter.string(from: Date())
        setTag(XMP_PHOTOSHOP_CREATED_DATE, dateStr)
        setTag(XMP_PHOTOSHOP_CREATED_DATE_TIME, dateStr)
        
        setTag(XMP_LENS_MODEL, "iOS")
        setTag(XMP_IMAGE_ID, String.randomNumber(length: 20))
        setTag(XMP_ORIENTATION, "6")
        
        // MARK: Write XMP
        let error = NSError(domain: "DataMapImage", code: 0, userInfo: [NSLocalizedDescriptionKey: "Cannot save xmp data."])
        
        guard let imageSource = CGImageSourceCreateWithURL(imgUrl as CFURL, nil) else {
            throw error
        }
        
        guard let destination = CGImageDestinationCreateWithURL(imgUrl as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw error
        }
        
        let options: CFDictionary = [
            kCGImageDestinationMetadata: metadata!
        ] as CFDictionary
        
        if !CGImageDestinationCopyImageSource(destination, imageSource, options, nil) {
            throw error
        }
        
        try ImageDataHelper.updateGPSData(imgUrl, latitude: latitude, longitude: longitude)
    }
}
