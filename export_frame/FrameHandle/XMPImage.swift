//
//  XMPImage.swift
//  Quick3D
//
//  Created by HaNST on 15/11/24.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers
import simd

let CAMERA_NAMESPACE = "http://pix4d.com/camera/1.0/" as CFString
let XMP_CAMERA_PREFIX = "Camera" as CFString

let XMP_CAMERA_RTK_PREFIX = "\(XMP_CAMERA_PREFIX):RTK"
let XMP_CAMERA_GPS_PREFIX = "\(XMP_CAMERA_PREFIX):GPS"

let XMP_CAMERA_BRAND_NAME = "\(XMP_CAMERA_PREFIX):BrandName"
let XMP_CAMERA_CAPTURE_UUID = "\(XMP_CAMERA_PREFIX):CaptureUUID"
let XMP_CAMERA_DEPTH_CONFIDENCE_RANGE_MIN = "\(XMP_CAMERA_PREFIX):DepthConfidenceRangeMin"
let XMP_CAMERA_DEPTH_CONFIDENCE_RANGE_MAX = "\(XMP_CAMERA_PREFIX):DepthConfidenceRangeMax"
let XMP_CAMERA_DEPTH_CONFIDENCE_UNIT = "\(XMP_CAMERA_PREFIX):DepthConfidenceUnit"
let XMP_CAMERA_DEPTH_UNIT = "\(XMP_CAMERA_PREFIX):DepthUnit"

let XMP_CAMERA_MODEL_TYPE = "\(XMP_CAMERA_PREFIX):ModelType"
let XMP_CAMERA_PERSPECTIVE_DISTORTION = "\(XMP_CAMERA_PREFIX):PerspectiveDistortion"
let XMP_CAMERA_PRINCIPAL_POINT = "\(XMP_CAMERA_PREFIX):PrincipalPoint"
let XMP_CAMERA_FOCAL_PLANE_X_RESOLUTION = "\(kCGImageMetadataPrefixExif):\(kCGImagePropertyExifFocalPlaneXResolution)"
let XMP_CAMERA_FOCAL_PLANE_Y_RESOLUTION = "\(kCGImageMetadataPrefixExif):\(kCGImagePropertyExifFocalPlaneYResolution)"
let XMP_CAMERA_FOCAL_PLANE_RESOLUTION_UNIT = "\(kCGImageMetadataPrefixExif):\(kCGImagePropertyExifFocalPlaneResolutionUnit)"
let XMP_CAMERA_PERSPECTIVE_FOCAL_LENGTH = "\(XMP_CAMERA_PREFIX):PerspectiveFocalLength"
let XMP_CAMERA_FOCAL_LENGTH = "\(kCGImageMetadataPrefixExif):\(kCGImagePropertyExifFocalLength)"

let XMP_CAMERA_HORIZ_CS = "\(XMP_CAMERA_PREFIX):HorizCS"
let XMP_CAMERA_VERT_CS = "\(XMP_CAMERA_PREFIX):VertCS"

let XMP_CAMERA_YAW = "\(XMP_CAMERA_PREFIX):Yaw"
let XMP_CAMERA_ROLL = "\(XMP_CAMERA_PREFIX):Roll"
let XMP_CAMERA_PITCH = "\(XMP_CAMERA_PREFIX):Pitch"

let XMP_CAMERA_RTK_YAW = "\(XMP_CAMERA_RTK_PREFIX)Yaw"
let XMP_CAMERA_RTK_ROLL = "\(XMP_CAMERA_RTK_PREFIX)Roll"
let XMP_CAMERA_RTK_PITCH = "\(XMP_CAMERA_RTK_PREFIX)Pitch"

let XMP_CAMERA_RTK_ALTITUDE = "\(XMP_CAMERA_RTK_PREFIX)Altitude"
let XMP_CAMERA_RTK_LONGITUDE = "\(XMP_CAMERA_RTK_PREFIX)Longitude"
let XMP_CAMERA_RTK_LATITUDE = "\(XMP_CAMERA_RTK_PREFIX)Latitude"
let XMP_CAMERA_RTK_XY_ACCURACY = "\(XMP_CAMERA_RTK_PREFIX)XYAccuracy"
let XMP_CAMERA_RTK_Z_ACCURACY = "\(XMP_CAMERA_RTK_PREFIX)ZAccuracy"

let XMP_CAMERA_RTK_MODEL = "\(XMP_CAMERA_RTK_PREFIX)Model"
let XMP_CAMERA_RTK_ID = "\(XMP_CAMERA_RTK_PREFIX)Id"
let XMP_CAMERA_RTK_SERIAL_NUMBER = "\(XMP_CAMERA_RTK_PREFIX)SerialNumber"

let XMP_CAMERA_GPS_ALTITUDE = "\(kCGImageMetadataPrefixExif):GPSAltitude"
let XMP_CAMERA_GPS_ALTITUDE_REF = "\(kCGImageMetadataPrefixExif):GPSAltitudeRef"
let XMP_CAMERA_GPS_LONGITUDE = "\(kCGImageMetadataPrefixExif):GPSLongitude"
let XMP_CAMERA_GPS_LONGITUDE_REF = "\(kCGImageMetadataPrefixExif):GPSLongitudeRef"
let XMP_CAMERA_GPS_LATITUDE = "\(kCGImageMetadataPrefixExif):GPSLatitude"
let XMP_CAMERA_GPS_LATITUDE_REF = "\(kCGImageMetadataPrefixExif):GPSLatitudeRef"
let XMP_CAMERA_GPS_XY_ACCURACY = "\(XMP_CAMERA_GPS_PREFIX)XYAccuracy"
let XMP_CAMERA_GPS_Z_ACCURACY = "\(XMP_CAMERA_GPS_PREFIX)ZAccuracy"

let XMP_CAMERA_APP_VERSION = "\(XMP_CAMERA_PREFIX):AppVersion"

let XMP_PHOTOSHOP_CREATED_DATE = "\(kCGImageMetadataPrefixPhotoshop):DateCreated"
let XMP_PHOTOSHOP_CREATED_DATE_TIME = "\(kCGImageMetadataPrefixPhotoshop):\(kCGImagePropertyExifDateTimeOriginal)"

let XMP_DATE_TIME_ORIGINAL = "\(kCGImageMetadataPrefixExif):\(kCGImagePropertyExifDateTimeOriginal)"
let XMP_ORIENTATION = "\(kCGImageMetadataPrefixTIFF):\(kCGImagePropertyTIFFOrientation)"
let XMP_PHOTOMETRIC_INTERPRETATION = "\(kCGImageMetadataPrefixTIFF):\(kCGImagePropertyTIFFPhotometricInterpretation)"
let XMP_COMPRESSION = "\(kCGImageMetadataPrefixTIFF):\(kCGImagePropertyTIFFCompression)"
let XMP_RESOLUTION_UNIT = "\(kCGImageMetadataPrefixTIFF):\(kCGImagePropertyTIFFResolutionUnit)"

let XMP_LENS_MODEL = "\(kCGImageMetadataPrefixExifEX):\(kCGImagePropertyExifLensModel)"
let XMP_MAKE = "\(kCGImageMetadataPrefixTIFF):\(kCGImagePropertyTIFFMake)"
let XMP_MODEL = "\(kCGImageMetadataPrefixTIFF):\(kCGImagePropertyTIFFModel)"
let XMP_IMAGE_ID = "\(kCGImageMetadataPrefixExif):\(kCGImagePropertyExifImageUniqueID)"
let XMP_SUBSEC_TIME_ORIGINAL = "\(kCGImageMetadataPrefixExif):\(kCGImagePropertyExifSubsecTimeOriginal)"
