import XCTest
import CoreLocation
@testable import mHomeNode

final class AutoLocationScanTests: XCTestCase {

    func testDistanceCalculationBetweenLocations() {
        // Marienplatz, Munich
        let loc1 = ScanLocation(latitude: 48.137154, longitude: 11.576124, placeName: "Marienplatz")
        // Karlsplatz (Stachus), Munich (approx 550m away)
        let loc2 = ScanLocation(latitude: 48.139268, longitude: 11.565893, placeName: "Karlsplatz")

        let dist = LocationService.distance(between: loc1, and: loc2)
        // Distance should be between 500m and 900m
        XCTAssertGreaterThan(dist, 500.0)
        XCTAssertLessThan(dist, 1000.0)
    }

    func testDistanceZeroForIdenticalLocations() {
        let loc = ScanLocation(latitude: 48.137154, longitude: 11.576124)
        let dist = LocationService.distance(between: loc, and: loc)
        XCTAssertEqual(dist, 0.0, accuracy: 0.001)
    }

    func testShortDistanceThresholdEvaluation() {
        let loc1 = ScanLocation(latitude: 48.137154, longitude: 11.576124)
        // Move ~10 meters north
        let loc2 = ScanLocation(latitude: 48.137244, longitude: 11.576124)

        let dist = LocationService.distance(between: loc1, and: loc2)
        XCTAssertGreaterThan(dist, 5.0)
        XCTAssertLessThan(dist, 20.0)

        // Threshold check
        let threshold = 100.0
        XCTAssertFalse(dist >= threshold, "10m movement should not exceed 100m threshold")
    }

    func testSignificantDistanceThresholdEvaluation() {
        let loc1 = ScanLocation(latitude: 48.137154, longitude: 11.576124)
        // Move ~250 meters
        let loc2 = ScanLocation(latitude: 48.139400, longitude: 11.576124)

        let dist = LocationService.distance(between: loc1, and: loc2)
        let threshold = 100.0
        XCTAssertTrue(dist >= threshold, "250m movement should exceed 100m threshold")
    }
}
