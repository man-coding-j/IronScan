@preconcurrency import CoreLocation
import MapKit
import SwiftUI

struct NearbyCareFacility: Identifiable, Equatable {
    let id: String
    let name: String
    let phoneNumber: String?
    let websiteURL: URL?
    let address: String
    let coordinate: CLLocationCoordinate2D
    let distanceMeters: CLLocationDistance
    let availability: VenueAvailability

    static func == (lhs: NearbyCareFacility, rhs: NearbyCareFacility) -> Bool {
        lhs.id == rhs.id
            && lhs.name == rhs.name
            && lhs.phoneNumber == rhs.phoneNumber
            && lhs.websiteURL == rhs.websiteURL
            && lhs.address == rhs.address
            && lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
            && lhs.distanceMeters == rhs.distanceMeters
            && lhs.availability == rhs.availability
    }

    var distanceText: String {
        let miles = distanceMeters / 1_609.344
        if miles < 0.1 {
            return "Less than 0.1 miles away"
        }
        return String(format: "%.1f miles away", miles)
    }

    var mapItem: MKMapItem {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = name
        item.phoneNumber = phoneNumber
        item.url = websiteURL
        return item
    }
}

@MainActor
final class LocationManager: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    nonisolated static let searchQueries = [
        "Diagnostic Laboratory",
        "Quest Diagnostics",
        "Labcorp",
        "Urgent Care",
        "Hospital",
    ]

    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var facilities = [NearbyCareFacility]()
    @Published private(set) var isSearching = false
    @Published private(set) var message = "Location access is optional."
    @Published var cameraPosition = MapCameraPosition.automatic

    private let locationManager: CLLocationManager
    private let availabilityEngine: AvailabilityEngine
    private var hasRequestedSearch = false

    init(
        locationManager: CLLocationManager = CLLocationManager(),
        availabilityEngine: AvailabilityEngine = AvailabilityEngine()
    ) {
        self.locationManager = locationManager
        self.availabilityEngine = availabilityEngine
        authorizationStatus = locationManager.authorizationStatus
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var needsSettings: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    func findNearbyCare() {
        hasRequestedSearch = true
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            requestCurrentLocation()
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            message = "Location access is off. You can enable it in iOS Settings."
        @unknown default:
            message = "Location services are unavailable."
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if hasRequestedSearch,
           authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
            requestCurrentLocation()
        } else if needsSettings {
            isSearching = false
            message = "Location access is off. You can enable it in iOS Settings."
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            isSearching = false
            message = "A current location was not available."
            return
        }
        cameraPosition = .region(MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: 18_000,
            longitudinalMeters: 18_000
        ))
        Task { await searchNearby(centeredAt: location) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isSearching = false
        if let locationError = error as? CLError, locationError.code == .denied {
            message = "Location access is off. You can enable it in iOS Settings."
        } else {
            message = "Nearby care could not be loaded. You can search again."
        }
    }

    private func requestCurrentLocation() {
        isSearching = true
        message = "Finding nearby laboratories and clinics..."
        locationManager.requestLocation()
    }

    private func searchNearby(centeredAt location: CLLocation) async {
        let region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: 20_000,
            longitudinalMeters: 20_000
        )
        var results = [NearbyCareFacility]()
        var searchFailureCount = 0
        for query in Self.searchQueries {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.region = region
            do {
                let response = try await MKLocalSearch(request: request).start()
                results.append(contentsOf: response.mapItems.compactMap {
                    facility(from: $0, relativeTo: location)
                })
            } catch {
                searchFailureCount += 1
            }
        }

        var seenIdentifiers = Set<String>()
        facilities = results
            .filter { seenIdentifiers.insert($0.id).inserted }
            .sorted(by: { $0.distanceMeters < $1.distanceMeters })
            .prefix(30)
            .map { $0 }
        isSearching = false
        if facilities.isEmpty, searchFailureCount > 0 {
            message = "Nearby care could not be loaded. You can search again."
        } else if facilities.isEmpty {
            message = "No nearby results were found. Try searching in Apple Maps."
        } else {
            message = "Directory details and prototype hours must be confirmed with each location."
        }
    }

    private func facility(
        from item: MKMapItem,
        relativeTo location: CLLocation
    ) -> NearbyCareFacility? {
        let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let name, !name.isEmpty else { return nil }
        let coordinate = item.placemark.coordinate
        let identifier = [
            name.lowercased(),
            String(format: "%.5f", coordinate.latitude),
            String(format: "%.5f", coordinate.longitude),
        ].joined(separator: "|")
        let facilityLocation = CLLocation(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        return NearbyCareFacility(
            id: identifier,
            name: name,
            phoneNumber: item.phoneNumber,
            websiteURL: item.url,
            address: item.placemark.title ?? "Address unavailable",
            coordinate: coordinate,
            distanceMeters: facilityLocation.distance(from: location),
            availability: availabilityEngine.availability(for: name)
        )
    }
}

@MainActor
private func performLocalSearch(_ request: MKLocalSearch.Request) async throws -> MKLocalSearch.Response {
    try await withCheckedThrowingContinuation { continuation in
        MKLocalSearch(request: request).start { response, error in
            if let response {
                continuation.resume(returning: response)
            } else {
                continuation.resume(throwing: error ?? URLError(.unknown))
            }
        }
    }
}
