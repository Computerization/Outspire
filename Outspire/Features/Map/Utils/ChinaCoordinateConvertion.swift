import CoreLocation

/// GCJ-02 conversion functions
enum CoordinateConverter {
    static let a = 6_378_245.0
    static let ee = 0.00669342162296594323

    static func transformLat(_ lat: Double, _ lon: Double) -> Double {
        var ret = -100.0 + 2.0 * lon + 3.0 * lat + 0.2 * lat * lat + 0.1 * lon * lat + 0.2 * sqrt(abs(lon))
        ret += (20.0 * sin(6.0 * lon * .pi) + 20.0 * sin(2.0 * lon * .pi)) * 2.0 / 3.0
        ret += (20.0 * sin(lat * .pi) + 40.0 * sin(lat / 3.0 * .pi)) * 2.0 / 3.0
        ret += (150.0 * sin(lat / 12.0 * .pi) + 300.0 * sin(lat / 30.0 * .pi)) * 2.0 / 3.0
        return ret
    }

    static func transformLon(_ lat: Double, _ lon: Double) -> Double {
        var ret = 300.0 + lon + 2.0 * lat + 0.1 * lon * lon + 0.1 * lon * lat + 0.1 * sqrt(abs(lon))
        ret += (20.0 * sin(6.0 * lon * .pi) + 20.0 * sin(2.0 * lon * .pi)) * 2.0 / 3.0
        ret += (20.0 * sin(lon * .pi) + 40.0 * sin(lon / 3.0 * .pi)) * 2.0 / 3.0
        ret += (150.0 * sin(lon / 12.0 * .pi) + 300.0 * sin(lon / 30.0 * .pi)) * 2.0 / 3.0
        return ret
    }

    static func coordinateHandler(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let lat = coordinate.latitude
        let lon = coordinate.longitude

        // Check if the coordinate is outside China (no conversion needed)
        if !isInChinaBounds(lat: lat, lon: lon) {
            return coordinate
        }

        let dLat = transformLat(lat - 35.0, lon - 105.0)
        let dLon = transformLon(lat - 35.0, lon - 105.0)

        let radLat = lat / 180.0 * .pi
        var magic = sin(radLat)
        magic = 1 - ee * magic * magic
        let sqrtMagic = sqrt(magic)

        let convertedLat = lat + (dLat * 180.0) / ((a * (1 - ee)) / (magic * sqrtMagic) * .pi)
        let convertedLon = lon + (dLon * 180.0) / (a / sqrtMagic * cos(radLat) * .pi)

        return CLLocationCoordinate2D(latitude: convertedLat, longitude: convertedLon)
    }

    static func reverseCoordinateHandler(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let lat = coordinate.latitude
        let lon = coordinate.longitude

        // Check if the coordinate is outside China (no conversion needed)
        if !isInChinaBounds(lat: lat, lon: lon) {
            return coordinate
        }

        var tempLat = lat
        var tempLon = lon
        var convertedLat = lat
        var convertedLon = lon

        for _ in 0 ..< 10 { // Iterative refinement for better accuracy
            convertedLat = tempLat
            convertedLon = tempLon

            let dLat = transformLat(tempLat - 35.0, tempLon - 105.0)
            let dLon = transformLon(tempLat - 35.0, tempLon - 105.0)

            let radLat = tempLat / 180.0 * .pi
            var magic = sin(radLat)
            magic = 1 - ee * magic * magic
            let sqrtMagic = sqrt(magic)

            tempLat = lat - (dLat * 180.0) / ((a * (1 - ee)) / (magic * sqrtMagic) * .pi)
            tempLon = lon - (dLon * 180.0) / (a / sqrtMagic * cos(radLat) * .pi)
        }

        return CLLocationCoordinate2D(latitude: convertedLat, longitude: convertedLon)
    }

    static func isInChinaBounds(lat: Double, lon: Double) -> Bool {
        // Rough bounding box for China
        lon >= 72.004 && lon <= 135.05 && lat >= 3.86 && lat <= 53.55
    }
}
