//
//  TTNSTMTrafficConfig.swift
//  TunedTwo
//
//  Typed parser for Traffic Map (TMI) TTN/STM config files.
//

import Foundation

/// Parsed contents of a traffic-map config file.
public struct TTNSTMTrafficConfig: Equatable, Sendable {
    public let protocolVersionID: String
    public let trafficMapID: String
    public let stationList: [TTNSTMStation]
    public let numRows: Int
    public let numColumns: Int
    public let numTransmittedTiles: Int
    /// Coordinate entries for each row, keyed by `CoordinatesRow1`,
    /// `CoordinatesRow2`, and so on.
    public let coordinatesRows: [[TTNSTMCoordinate]]
    public let backgroundRGBColor: TTNSTMRGB
    public let copyrightNotice: String

    public init(protocolVersionID: String,
                trafficMapID: String,
                stationList: [TTNSTMStation],
                numRows: Int,
                numColumns: Int,
                numTransmittedTiles: Int,
                coordinatesRows: [[TTNSTMCoordinate]],
                backgroundRGBColor: TTNSTMRGB,
                copyrightNotice: String) {
        self.protocolVersionID = protocolVersionID
        self.trafficMapID = trafficMapID
        self.stationList = stationList
        self.numRows = numRows
        self.numColumns = numColumns
        self.numTransmittedTiles = numTransmittedTiles
        self.coordinatesRows = coordinatesRows
        self.backgroundRGBColor = backgroundRGBColor
        self.copyrightNotice = copyrightNotice
    }
}

/// Errors raised while converting a raw config into a typed traffic config.
public enum TTNSTMTrafficConfigError: Error, Equatable {
    case missingKey(String)
    case invalidValue(key: String, value: String)
}

/// Parses a raw `TTNSTMConfig` into a typed `TTNSTMTrafficConfig`.
public enum TTNSTMTrafficConfigParser {
    /// Parse a traffic config from a raw string.
    ///
    /// - Throws: `TTNSTMConfigError`, `TTNSTMTrafficConfigError`, or
    ///   `TTNSTMValueParserError`.
    public static func parse(_ input: String) throws -> TTNSTMTrafficConfig {
        let config = try TTNSTMConfigParser().parse(input)
        return try parse(config)
    }

    /// Parse a traffic config from an already-tokenized raw config.
    public static func parse(_ config: TTNSTMConfig) throws -> TTNSTMTrafficConfig {
        func require(_ key: String) throws -> String {
            guard let value = config.singleValue(for: key) else {
                throw TTNSTMTrafficConfigError.missingKey(key)
            }
            return value
        }

        func requireInt(_ key: String) throws -> Int {
            let raw = try require(key)
            guard let value = Int(raw) else {
                throw TTNSTMTrafficConfigError.invalidValue(key: key, value: raw)
            }
            return value
        }

        let protocolVersionID = try require("TrafficMapProtocolVersionID")
        let trafficMapID = try require("TrafficMapID")
        let numRows = try requireInt("NumRows")
        let numColumns = try requireInt("NumColumns")
        let numTransmittedTiles = try requireInt("NumTransmittedTiles")
        let copyrightNotice = try require("CopyrightNotice")

        let stationList = try parseStations(config.values(for: "StationList"))
        let coordinatesRows = try parseCoordinatesRows(config, numRows: numRows)

        let backgroundRaw = try require("BackgroundRGBColor")
        guard let backgroundRGBColor = TTNSTMValueParser.parseRGB(backgroundRaw) else {
            throw TTNSTMTrafficConfigError.invalidValue(key: "BackgroundRGBColor", value: backgroundRaw)
        }

        return TTNSTMTrafficConfig(
            protocolVersionID: protocolVersionID,
            trafficMapID: trafficMapID,
            stationList: stationList,
            numRows: numRows,
            numColumns: numColumns,
            numTransmittedTiles: numTransmittedTiles,
            coordinatesRows: coordinatesRows,
            backgroundRGBColor: backgroundRGBColor,
            copyrightNotice: copyrightNotice
        )
    }

    // MARK: - Helpers

    private static func parseStations(_ values: [String]?) throws -> [TTNSTMStation] {
        guard let values else { return [] }
        return try values.map { raw in
            guard let station = TTNSTMValueParser.parseStation(raw) else {
                throw TTNSTMTrafficConfigError.invalidValue(key: "StationList", value: raw)
            }
            return station
        }
    }

    private static func parseCoordinatesRows(_ config: TTNSTMConfig, numRows: Int) throws -> [[TTNSTMCoordinate]] {
        var rows: [[TTNSTMCoordinate]] = []
        for row in 1...numRows {
            let key = "CoordinatesRow\(row)"
            guard let values = config.values(for: key) else {
                throw TTNSTMTrafficConfigError.missingKey(key)
            }
            let coordinates = try values.map { raw -> TTNSTMCoordinate in
                guard let coordinate = TTNSTMValueParser.parseCoordinate(raw) else {
                    throw TTNSTMTrafficConfigError.invalidValue(key: key, value: raw)
                }
                return coordinate
            }
            rows.append(coordinates)
        }
        return rows
    }
}
