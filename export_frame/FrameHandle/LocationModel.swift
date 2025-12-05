import Foundation
import CoreLocation
import VigramSDK

let defaultCoordinate: String = "EPSG:4326"

struct LocationModel: Codable {
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let horizontal: Double
    let vertical: Double
    let course: Double
    let courseAccuracy: Double
    let coordinate: String
    let isRTK: Bool
    
    init() {
        self.latitude = 0
        self.longitude = 0
        self.altitude = 0
        self.horizontal = 0
        self.vertical = 0
        self.course = 0
        self.courseAccuracy = 0
        self.coordinate = defaultCoordinate
        self.isRTK = false
    }
    
    init(_ location: CLLocation, coordinate: String = defaultCoordinate, isRTK: Bool = false) {
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
        self.altitude = location.ellipsoidalAltitude
        self.horizontal = location.horizontalAccuracy
        self.vertical = location.verticalAccuracy
        self.course = location.course
        self.courseAccuracy = location.courseAccuracy
        self.coordinate = coordinate
        self.isRTK = isRTK
    }
    
    init(_ data: EnvironmentData, coordinate: String = defaultCoordinate) {
        self.latitude = data.correctedCoordinate.latitude
        self.longitude = data.correctedCoordinate.longitude
        self.altitude = data.correctedCoordinate.altitude
        self.horizontal = data.horizontalAccuracy
        self.vertical = data.verticalAccuracy
        self.course = 0
        self.courseAccuracy = 0
        self.coordinate = coordinate
        self.isRTK = true
    }
    
    init(
        latitude: Double,
        longitude: Double,
        altitude: Double,
        horizontal: Double,
        vertical: Double,
        heading: Double,
        coordinate: String,
        isRTK: Bool = false
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.horizontal = horizontal
        self.vertical = vertical
        self.course = heading
        self.courseAccuracy = 0
        self.coordinate = coordinate
        self.isRTK = isRTK
    }
    
    init(
        latitude: Double,
        longitude: Double,
        altitude: Double,
        horizontal: Double,
        vertical: Double,
        heading: Double
    ) {
        self.init(
            latitude: latitude,
            longitude: longitude,
            altitude: altitude,
            horizontal: horizontal,
            vertical: vertical,
            heading: heading,
            coordinate: defaultCoordinate
        )
    }
    
    init(
        latitude: Double,
        longitude: Double,
        altitude: Double,
        horizontal: Double,
        vertical: Double
    ) {
        self.init(
            latitude: latitude,
            longitude: longitude,
            altitude: altitude,
            horizontal: horizontal,
            vertical: vertical,
            heading: 0
        )
    }
    
    init(
        latitude: Double,
        longitude: Double,
        altitude: Double,
        horizontal: Double,
        vertical: Double,
        coordinate: String
    ) {
        self.init(
            latitude: latitude,
            longitude: longitude,
            altitude: altitude,
            horizontal: horizontal,
            vertical: vertical,
            heading: 0,
            coordinate: coordinate
        )
    }
    
    init(
        latitude: Double,
        longitude: Double,
        altitude: Double
    ) {
        self.init(
            latitude: latitude,
            longitude: longitude,
            altitude: altitude,
            horizontal: 0.01,
            vertical: 0.01,
            heading: 0
        )
    }
}
