import CoreLocation
import MapKit
import SwiftUI

struct MapView: View {
    // Change from @StateObject to @ObservedObject and use the shared instance
    @ObservedObject private var regionChecker = RegionChecker.shared
    @State private var region: MKCoordinateRegion
    @State private var position: MapCameraPosition

    private let campusLocations: [CampusLocation]
    private let campusBoundary: [CLLocationCoordinate2D]
    private let baseCoordinate = CLLocationCoordinate2D(latitude: 31.14704, longitude: 121.40758)

    init() {
        let initialRegion = MKCoordinateRegion(
            center: baseCoordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
        )

        self._region = State(initialValue: initialRegion)
        self._position = State(initialValue: .region(initialRegion))

        self.campusLocations = [
            CampusLocation(name: "WFLA International Campus", coordinate: baseCoordinate)
        ]

        self.campusBoundary = [
            CLLocationCoordinate2D(latitude: 31.14792, longitude: 121.40819),
            CLLocationCoordinate2D(latitude: 31.14736, longitude: 121.40848),
            CLLocationCoordinate2D(latitude: 31.14714, longitude: 121.40814),
            CLLocationCoordinate2D(latitude: 31.14693, longitude: 121.40787),
            CLLocationCoordinate2D(latitude: 31.14674, longitude: 121.40769),
            CLLocationCoordinate2D(latitude: 31.14659, longitude: 121.40755),
            CLLocationCoordinate2D(latitude: 31.14637, longitude: 121.40735),
            CLLocationCoordinate2D(latitude: 31.14748, longitude: 121.40686),
            CLLocationCoordinate2D(latitude: 31.14792, longitude: 121.40819)
        ]
    }

    var body: some View {
        VStack {
            Map(position: $position) {
                // Pre-compute converted coordinates
                let convertedBoundary = convertedBoundaryCoordinates
                let convertedLocations = convertedCampusLocations

                // Markers
                ForEach(convertedLocations) { location in
                    Marker(location.name, coordinate: location.coordinate)
                        .tint(.red)
                }

                // Boundary polygon
                MapPolygon(coordinates: convertedBoundary)
                    .foregroundStyle(.cyan.opacity(0.3))
                    .stroke(.cyan, lineWidth: 2)
            }
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear(perform: setupMap)
            .onChange(of: position) { _, _ in handlePositionChange() }
            .onChange(of: regionChecker.regionCode) { _, _ in updateRegionForChina() }
        }
    }

    // MARK: - Computed Properties

    private var convertedBoundaryCoordinates: [CLLocationCoordinate2D] {
        regionChecker.isChinaRegion() ?
            campusBoundary.map(CoordinateConverter.coordinateHandler) :
            campusBoundary
    }

    private var convertedCampusLocations: [CampusLocation] {
        campusLocations.map { location in
            let coordinate = regionChecker.isChinaRegion() ?
                CoordinateConverter.coordinateHandler(location.coordinate) :
                location.coordinate
            return CampusLocation(name: location.name, coordinate: coordinate)
        }
    }

    // MARK: - Private Methods

    private func setupMap() {
        // Use the checkRegion method on the shared instance
        regionChecker.checkRegion()
    }

    private func handlePositionChange() {
        // Only recheck region if the center has changed significantly
        guard let currentCenter = position.region?.center else { return }
        let distance = currentCenter.distance(from: region.center)
        if distance > 1000 { // Adjust threshold as needed (in meters)
            // Use checkRegion method on the shared instance
            regionChecker.checkRegion()
        }
    }

    private func updateRegionForChina() {
        guard regionChecker.isChinaRegion() else { return }

        let adjustedCoordinate = CoordinateConverter.coordinateHandler(baseCoordinate)
        let newRegion = MKCoordinateRegion(
            center: adjustedCoordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
        )

        region = newRegion
        position = .region(newRegion)
    }
}

// MARK: - Supporting Structures

struct CampusLocation: Identifiable {
    let id = UUID()
    let name: String
    let coordinate: CLLocationCoordinate2D
}

// MARK: - Extensions

extension CLLocationCoordinate2D {
    func distance(from coordinate: CLLocationCoordinate2D) -> CLLocationDistance {
        let location1 = CLLocation(latitude: latitude, longitude: longitude)
        let location2 = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return location1.distance(from: location2)
    }
}

#Preview {
    MapView()
}
