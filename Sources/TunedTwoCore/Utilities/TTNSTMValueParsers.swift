//
//  TTNSTMValueParsers.swift
//  TunedTwo
//
//  Typed helpers for extracting coordinates, RGB tuples, station entries,
//  and other parenthesized values from raw TTN/STM strings.
//

import Foundation

/// A geographic coordinate as latitude and longitude in degrees.
public struct TTNSTMCoordinate: Equatable, Hashable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// An RGB color with 8-bit components.
public struct TTNSTMRGB: Equatable, Hashable, Sendable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

/// A station entry pairing a station identifier with a frequency label.
public struct TTNSTMStation: Equatable, Sendable {
    public let stationID: String
    public let frequency: String

    public init(stationID: String, frequency: String) {
        self.stationID = stationID
        self.frequency = frequency
    }
}

/// Errors raised while parsing individual tuple-style values.
public enum TTNSTMValueParserError: Error, Equatable {
    case missingOpeningParenthesis
    case missingClosingParenthesis
    case unbalancedParentheses
}

/// Parsers for the parenthesized value literals used in TTN/STM files.
public enum TTNSTMValueParser {
    /// Split a parenthesized tuple such as `(a, b, c)` into its trimmed
    /// string components.
    ///
    /// - Throws: `TTNSTMValueParserError` if the tuple is malformed.
    public static func parseTuple(_ raw: String) throws -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)

        guard trimmed.hasPrefix("(") else {
            throw TTNSTMValueParserError.missingOpeningParenthesis
        }
        guard trimmed.hasSuffix(")") else {
            throw TTNSTMValueParserError.missingClosingParenthesis
        }

        let content = trimmed.dropFirst().dropLast()
        var components: [String] = []
        var current = ""
        var depth = 0

        for char in content {
            switch char {
            case "(":
                depth += 1
                current.append(char)
            case ")":
                depth -= 1
                guard depth >= 0 else {
                    throw TTNSTMValueParserError.unbalancedParentheses
                }
                current.append(char)
            case "," where depth == 0:
                components.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            default:
                current.append(char)
            }
        }

        guard depth == 0 else {
            throw TTNSTMValueParserError.unbalancedParentheses
        }

        components.append(current.trimmingCharacters(in: .whitespaces))
        return components
    }

    /// Parse a `(latitude, longitude)` coordinate tuple.
    public static func parseCoordinate(_ raw: String) -> TTNSTMCoordinate? {
        guard let components = try? parseTuple(raw),
              components.count == 2,
              let latitude = Double(components[0]),
              let longitude = Double(components[1]) else {
            return nil
        }
        return TTNSTMCoordinate(latitude: latitude, longitude: longitude)
    }

    /// Parse an `(r, g, b)` RGB tuple.
    public static func parseRGB(_ raw: String) -> TTNSTMRGB? {
        guard let components = try? parseTuple(raw),
              components.count == 3,
              let red = UInt8(components[0]),
              let green = UInt8(components[1]),
              let blue = UInt8(components[2]) else {
            return nil
        }
        return TTNSTMRGB(red: red, green: green, blue: blue)
    }

    /// Parse a `(stationID, frequency)` station tuple.
    public static func parseStation(_ raw: String) -> TTNSTMStation? {
        guard let components = try? parseTuple(raw),
              components.count == 2 else {
            return nil
        }
        return TTNSTMStation(stationID: components[0], frequency: components[1])
    }
}
