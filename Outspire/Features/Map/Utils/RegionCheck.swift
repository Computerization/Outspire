import CoreLocation
import Foundation

@MainActor
class RegionChecker: ObservableObject {
    /// Add a shared singleton instance
    static let shared = RegionChecker()

    @Published var regionCode: String?
    @Published var isTaipeiInChina: Bool = false
    @Published var isCheckingRegion = false
    @Published var isCheckComplete: Bool = false

    /// Make init private to enforce singleton pattern
    private init() {
        // Run the Taiwan check on initialization
        checkTaipeiRepresentation()
    }

    func checkRegion() {
        guard !isCheckingRegion else { return }
        isCheckingRegion = true

        // Primary method to check region - uses the Taiwan test
        checkTaipeiRepresentation()

        // Also perform URL check as a fallback or additional data point
        fetchRegionCode()
    }

    func isChinaRegion() -> Bool {
        // Use the Taiwan check as the primary determinant
        isTaipeiInChina
    }

    func fetchRegionCode() {
        // This is kept as a secondary/optional check
        guard let url = URL(string: "https://gspe1-ssl.ls.apple.com/pep/gcc") else {
            isCheckingRegion = false
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            if let data,
               let code = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            {
                DispatchQueue.main.async {
                    self?.regionCode = code
                    self?.isCheckingRegion = false
                }
            } else {
                print("Failed to fetch region code: \(error?.localizedDescription ?? "Unknown error")")
                DispatchQueue.main.async {
                    self?.isCheckingRegion = false
                }
            }
        }.resume()
    }

    private func checkTaipeiRepresentation() {
        // Taipei coordinates
        let taipeiLocation = CLLocationCoordinate2D(latitude: 25.032969, longitude: 121.565418)

        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: taipeiLocation.latitude, longitude: taipeiLocation.longitude)

        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            guard let self else { return }

            if let placemark = placemarks?.first {
                // Check how MapKit represents Taipei's country
                if let country = placemark.country, let countryCode = placemark.isoCountryCode {
                    DispatchQueue.main.async {
                        // If Taipei is shown as part of China (CN), this confirms Chinese MapKit
                        self.isTaipeiInChina = countryCode == "CN"
                        self.isCheckComplete = true
                        self.isCheckingRegion = false
                        print("Taipei is shown as part of: \(country) (\(countryCode))")
                    }
                }
            } else if let error {
                print("Geocoding error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isCheckComplete = true
                    self.isCheckingRegion = false
                }
            }
        }
    }
}
