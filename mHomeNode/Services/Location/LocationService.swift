import Foundation
@preconcurrency import CoreLocation
import OSLog

/// Service providing on-demand geolocation and reverse geocoding for tagging saved BLE scans
@Observable
@MainActor
public final class LocationService: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let logger = Logger(subsystem: "net.zehrer.homenode.mHomeNode", category: "LocationService")
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    public var currentLocation: ScanLocation?
    public var isLocating: Bool = false
    public var authorizationStatus: CLAuthorizationStatus = .notDetermined
    public var locationError: String?

    // MARK: - Auto-Location Tracking for Scans
    public var isAutoTracking: Bool = false
    public var distanceFilterThreshold: Double = 100.0
    public var lastAutoScanLocation: CLLocation?
    public var lastAutoScanTimestamp: Date?
    public var minDebounceInterval: TimeInterval = 30.0
    public var onSignificantLocationChange: ((_ newLocation: ScanLocation, _ distance: CLLocationDistance) -> Void)?

    private var locationContinuation: CheckedContinuation<ScanLocation?, Never>?

    public override init() {
        super.init()
        self.authorizationStatus = manager.authorizationStatus
        self.manager.delegate = self
        self.manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    /// Requests When-In-Use location permission if not already determined
    public func requestPermission() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    /// Asynchronously requests a single location fix and reverse-geocodes it into a place name
    public func fetchCurrentLocation() async -> ScanLocation? {
        requestPermission()

        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            logger.info("Location authorization not granted (status: \(status.rawValue))")
            return nil
        }

        isLocating = true
        locationError = nil

        return await withCheckedContinuation { continuation in
            self.locationContinuation = continuation
            self.manager.requestLocation()
        }
    }

    /// Starts continuous distance-filtered location tracking for automated scan sessions
    public func startAutoTracking(distanceThreshold: Double = 100.0) {
        requestPermission()
        self.distanceFilterThreshold = distanceThreshold
        self.manager.distanceFilter = distanceThreshold
        self.manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        self.isAutoTracking = true
        self.manager.startUpdatingLocation()
        logger.info("Started auto location tracking with distance threshold: \(distanceThreshold)m")
    }

    /// Stops continuous location tracking
    public func stopAutoTracking() {
        self.isAutoTracking = false
        self.manager.stopUpdatingLocation()
        self.manager.distanceFilter = kCLDistanceFilterNone
        logger.info("Stopped auto location tracking.")
    }

    /// Calculates distance in meters between two ScanLocation points
    nonisolated public static func distance(between loc1: ScanLocation, and loc2: ScanLocation) -> Double {
        let cl1 = CLLocation(latitude: loc1.latitude, longitude: loc1.longitude)
        let cl2 = CLLocation(latitude: loc2.latitude, longitude: loc2.longitude)
        return cl1.distance(from: cl2)
    }

    // MARK: - CLLocationManagerDelegate

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        self.authorizationStatus = manager.authorizationStatus
        logger.debug("Location authorization status updated: \(manager.authorizationStatus.rawValue)")
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let clLocation = locations.last else {
            finishLocationRequest(nil)
            return
        }

        let lat = clLocation.coordinate.latitude
        let lon = clLocation.coordinate.longitude
        let alt = clLocation.altitude
        let acc = clLocation.horizontalAccuracy

        // Reverse geocode in background
        geocoder.reverseGeocodeLocation(clLocation) { [weak self] placemarks, error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                var placeName: String? = nil

                if let placemark = placemarks?.first {
                    var parts: [String] = []
                    if let subLocality = placemark.subLocality ?? placemark.thoroughfare {
                        parts.append(subLocality)
                    }
                    if let locality = placemark.locality {
                        parts.append(locality)
                    } else if let area = placemark.administrativeArea {
                        parts.append(area)
                    }
                    if let country = placemark.country, parts.isEmpty {
                        parts.append(country)
                    }
                    placeName = parts.joined(separator: ", ")
                }

                let scanLoc = ScanLocation(
                    latitude: lat,
                    longitude: lon,
                    altitude: alt,
                    horizontalAccuracy: acc,
                    placeName: placeName
                )

                self.currentLocation = scanLoc
                self.finishLocationRequest(scanLoc)

                // Handle auto tracking triggers
                if self.isAutoTracking {
                    let movedDistance: CLLocationDistance
                    if let last = self.lastAutoScanLocation {
                        movedDistance = clLocation.distance(from: last)
                    } else {
                        movedDistance = Double.greatestFiniteMagnitude
                    }

                    let now = Date()
                    let timeSinceLast = now.timeIntervalSince(self.lastAutoScanTimestamp ?? .distantPast)

                    if (self.lastAutoScanLocation == nil || movedDistance >= self.distanceFilterThreshold) && timeSinceLast >= self.minDebounceInterval {
                        self.lastAutoScanLocation = clLocation
                        self.lastAutoScanTimestamp = now
                        self.logger.info("Significant location change detected (\(Int(movedDistance))m). Triggering auto scan.")
                        self.onSignificantLocationChange?(scanLoc, movedDistance)
                    }
                }
            }
        }
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        logger.warning("Location manager failed: \(error.localizedDescription)")
        self.locationError = error.localizedDescription
        finishLocationRequest(nil)
    }

    private func finishLocationRequest(_ location: ScanLocation?) {
        isLocating = false
        if let cont = locationContinuation {
            locationContinuation = nil
            cont.resume(returning: location)
        }
    }
}

