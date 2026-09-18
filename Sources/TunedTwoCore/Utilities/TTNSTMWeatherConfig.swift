//
//  TTNSTMWeatherConfig.swift
//  TunedTwo
//
//  Typed parser for Doppler Weather Radar (DWR) TTN/STM config files.
//

import Foundation

/// One entry in a precipitation-type color legend.
public struct TTNSTMLegendEntry: Equatable, Sendable {
    /// Intensity or category level for this legend entry.
    public let level: Int
    /// Color assigned to this level.
    public let color: RGB

    public init(level: Int, color: RGB) {
        self.level = level
        self.color = color
    }
}

/// Parsed contents of a DWR weather-radar config file.
public struct TTNSTMWeatherConfig: Equatable, Sendable {
    public let protocolVersionID: String
    public let areaID: String
    public let stationList: [TTNSTMStation]
    public let coordinates: [Location]
    public let legendRain: [TTNSTMLegendEntry]
    public let legendMixIce: [TTNSTMLegendEntry]
    public let legendSnow: [TTNSTMLegendEntry]
    public let copyrightNotice: String

    public init(
        protocolVersionID: String,
        areaID: String,
        stationList: [TTNSTMStation],
        coordinates: [Location],
        legendRain: [TTNSTMLegendEntry],
        legendMixIce: [TTNSTMLegendEntry],
        legendSnow: [TTNSTMLegendEntry],
        copyrightNotice: String
    ) {
        self.protocolVersionID = protocolVersionID
        self.areaID = areaID
        self.stationList = stationList
        self.coordinates = coordinates
        self.legendRain = legendRain
        self.legendMixIce = legendMixIce
        self.legendSnow = legendSnow
        self.copyrightNotice = copyrightNotice
    }
}

/// Errors raised while converting a raw config into a typed weather config.
public enum TTNSTMWeatherConfigError: Error, Equatable {
    case missingKey(String)
    case invalidValue(key: String, value: String)
}

/// Parses a raw `TTNSTMConfig` into a typed `TTNSTMWeatherConfig`.
public enum TTNSTMWeatherConfigParser {
    /// Parse a weather config from a raw string.
    ///
    /// - Throws: `TTNSTMConfigError`, `TTNSTMWeatherConfigError`, or
    ///   `TTNSTMValueParserError`.
    public static func parse(_ input: String) throws -> TTNSTMWeatherConfig {
        let config = try TTNSTMConfigParser().parse(input)
        return try parse(config)
    }

    /// Parse a weather config from an already-tokenized raw config.
    public static func parse(_ config: TTNSTMConfig) throws -> TTNSTMWeatherConfig {
        func require(_ key: String) throws -> String {
            guard let value = config.singleValue(for: key) else {
                throw TTNSTMWeatherConfigError.missingKey(key)
            }
            return value
        }

        let protocolVersionID = try require("DopplerWeatherRadarProtocolVersionID")
        let areaID = try require("DWR_Area_ID")
        let copyrightNotice = try require("CopyrightNotice")

        let stationList = try parseStations(config.values(for: "StationList"))
        let coordinates = try parseCoordinates(config.values(for: "Coordinates"))

        return TTNSTMWeatherConfig(
            protocolVersionID: protocolVersionID,
            areaID: areaID,
            stationList: stationList,
            coordinates: coordinates,
            legendRain: try parseLegendEntries(config.values(for: "Legend_Rain")),
            legendMixIce: try parseLegendEntries(config.values(for: "Legend_MixIce")),
            legendSnow: try parseLegendEntries(config.values(for: "Legend_Snow")),
            copyrightNotice: copyrightNotice
        )
    }

    // MARK: - Helpers

    private static func parseStations(_ values: [String]?) throws -> [TTNSTMStation] {
        guard let values else { return [] }
        return try values.map { raw in
            guard let station = TTNSTMValueParser.parseStation(raw) else {
                throw TTNSTMWeatherConfigError.invalidValue(key: "StationList", value: raw)
            }
            return station
        }
    }

    private static func parseCoordinates(_ values: [String]?) throws -> [Location] {
        guard let values else { return [] }
        return try values.map { raw in
            guard let coordinate = TTNSTMValueParser.parseCoordinate(raw) else {
                throw TTNSTMWeatherConfigError.invalidValue(key: "Coordinates", value: raw)
            }
            return coordinate
        }
    }

    private static func parseLegendEntries(_ values: [String]?) throws -> [TTNSTMLegendEntry] {
        guard let values else { return [] }
        return try values.map { raw in
            let components = try TTNSTMValueParser.parseTuple(raw)
            guard components.count == 2,
                let level = Int(components[0]),
                let color = TTNSTMValueParser.parseRGB(components[1])
            else {
                throw TTNSTMWeatherConfigError.invalidValue(key: "Legend", value: raw)
            }
            return TTNSTMLegendEntry(level: level, color: color)
        }
    }
}
