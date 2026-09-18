//
//  Map.swift
//  TunedTwo
//

/// A geographic location as latitude and longitude in degrees,
/// and and optional altitude in meters.
public struct Location: Equatable, Hashable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let altitude: Double?

    public init(latitude: Double, longitude: Double, altitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
    }

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = nil
    }

    public init(latitude: Float, longitude: Float) {
        self.latitude = Double(latitude)
        self.longitude = Double(longitude)
        self.altitude = nil
    }
}
