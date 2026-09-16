//
//  WeatherMap.swift
//  TunedTwo
//
//  Tracks a DWRO weather radar image, including metadata.
//

import Foundation
import CoreGraphics
import ImageIO

/// Parsed parts of a TMT filename: `DWRO_{provider}_{rev}_{date}_{time}_{hex}.png`
///
/// Example: `DWRO_035apk_rev02_20260916_1358_040f.png`
///
/// - The third component is the **row** within the 3×3 map (1 = top).
/// - The fourth component is the **column** within the map (1 = left).
///   So `3_1` is the *lower-left* tile — the naming in the filename is
///   row_column, not x_y, despite how it looks.
/// - Date and time are UTC, to minute resolution.
/// - The trailing hex value is a version/sequence number for the tile.
public struct WeatherInfo: Equatable, Sendable {
    public let provider: String
    public let revision: String
    public let timestamp: Date
    public let hex: UInt16
}

/// Outcome of offering one LOT file to `WeatherMap.processLOTFile(name:data:)`.
/// Used by the CLI for reporting and by tests for exact assertions.
public enum WeatherMapIngestOutcome: Equatable, Sendable {
    /// The image was decoded and stored (a new slot, or an update whose
    /// timestamp was greater than or equal to the stored one).
    case stored
    /// The image parsed and decoded, but the stored image is
    /// strictly newer. Nothing changed.
    case ignoredStale(existingTimestamp: Date, incomingTimestamp: Date)
    /// The filename is not a DWRO traffic-map file at all.
    case notWeatherMapFile
    /// The filename parsed, but the bytes are not a decodable image.
    case undecodableImage
}

/// The current weather map.
public struct WeatherMap {
    public private(set) var info: WeatherInfo?
    public private(set) var image: CGImage?

    public init() {
    }

    // MARK: - Filename parsing

    /// Parse a DWRO filename into parts. Strict: returns nil for anything
    /// that is not a plausible DWRO name (used to filter LOT weather).
    public static func parseLOTName(_ lotName: String) -> WeatherInfo? {
        guard lotName.hasSuffix(".png") else { return nil }

        let baseName = String(lotName.dropLast(4))
        let components = baseName.components(separatedBy: "_")
        guard components.count == 6 else { return nil }

        guard components[0] == "DWRO" else { return nil }

        let provider = components[1]
        guard !provider.isEmpty else { return nil }

        let revision = components[2]

        let dateString = components[3]
        let timeString = components[4]
        guard dateString.count == 8, timeString.count == 4 else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        var dateComponents = DateComponents()
        dateComponents.calendar = calendar

        guard let year = Int(dateString.prefix(4)),
              let month = Int(dateString.dropFirst(4).prefix(2)),
              let day = Int(dateString.dropFirst(6).prefix(2)),
              let hour = Int(timeString.prefix(2)),
              let minute = Int(timeString.dropFirst(2).prefix(2)) else {
            return nil
        }

        dateComponents.year = year
        dateComponents.month = month
        dateComponents.day = day
        dateComponents.hour = hour
        dateComponents.minute = minute

        guard let timestamp = dateComponents.date else { return nil }

        guard let hex = UInt16(components[5], radix: 16) else { return nil }

        return WeatherInfo(provider: provider, revision: revision, timestamp: timestamp, hex: hex)
    }

    // MARK: - Ingest

    /// Offer one LOT file to the map.
    @discardableResult
    public mutating func processLOTFile(name: String, data: [UInt8]) -> WeatherMapIngestOutcome {
        guard let newInfo = Self.parseLOTName(name) else { return .notWeatherMapFile }
        guard let source = CGImageSourceCreateWithData(Data(data) as CFData, nil) else { return .undecodableImage }
        guard let newImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return .undecodableImage }

        if let currentInfo = info {
            if currentInfo.timestamp > newInfo.timestamp {
                return .ignoredStale(existingTimestamp: currentInfo.timestamp,
                                     incomingTimestamp: newInfo.timestamp)
            }
        }

        info = newInfo
        image = newImage
        return .stored
    }
}
