//
//  TTNSTMParserTests.swift
//  TunedTwoTests
//
//  Tests for the TTN/STM text-config parser and the weather/traffic
//  config parsers built on top of it.
//

import Foundation
import Testing

@testable import TunedTwoCore

@Suite("TTN/STM generic parser")
struct TTNSTMConfigParserTests {

    @Test("parses a single-value line")
    func singleValue() throws {
        let config = try TTNSTMConfigParser().parse(#"Key="value""#)
        #expect(config.values(for: "Key") == ["value"])
    }

    @Test("parses multiple semicolon-separated values")
    func multipleValues() throws {
        let config = try TTNSTMConfigParser().parse(#"Key="one";"two";"three""#)
        #expect(config.values(for: "Key") == ["one", "two", "three"])
    }

    @Test("trims whitespace around keys and values")
    func trimsWhitespace() throws {
        let config = try TTNSTMConfigParser().parse("  Key  =  \"value\"  ")
        #expect(config.singleValue(for: "Key") == "value")
    }

    @Test("ignores blank lines")
    func ignoresBlankLines() throws {
        let config = try TTNSTMConfigParser().parse(
            """
            Key1="a"

            Key2="b"
            """)
        #expect(config.singleValue(for: "Key1") == "a")
        #expect(config.singleValue(for: "Key2") == "b")
    }

    @Test("handles escaped quotes and backslashes")
    func escapes() throws {
        let config = try TTNSTMConfigParser().parse(#"Key="say \"hi\"";"c:\\path""#)
        #expect(config.values(for: "Key") == ["say \"hi\"", "c:\\path"])
    }

    @Test("throws when a line has no equals separator")
    func missingSeparator() {
        #expect(throws: TTNSTMConfigError.missingKeySeparator(line: "NoEqualsHere")) {
            try TTNSTMConfigParser().parse("NoEqualsHere")
        }
    }

    @Test("throws when the key is empty")
    func emptyKey() {
        #expect(throws: TTNSTMConfigError.emptyKey(line: "=\"value\"")) {
            try TTNSTMConfigParser().parse("=\"value\"")
        }
    }

    @Test("throws on unquoted value text")
    func unquotedValue() {
        #expect(throws: TTNSTMConfigError.malformedValue(line: "Key=not-quoted")) {
            try TTNSTMConfigParser().parse("Key=not-quoted")
        }
    }

    @Test("throws on an unclosed quote")
    func unclosedQuote() {
        #expect(throws: TTNSTMConfigError.malformedValue(line: #"Key="open"#)) {
            try TTNSTMConfigParser().parse(#"Key="open"#)
        }
    }
}

@Suite("TTN/STM value parsers")
struct TTNSTMValueParserTests {

    @Test("splits a simple tuple")
    func simpleTuple() throws {
        #expect(try TTNSTMValueParser.parseTuple("(a, b, c)") == ["a", "b", "c"])
    }

    @Test("throws for a missing parenthesis")
    func missingParenthesis() {
        #expect(throws: TTNSTMValueParserError.missingOpeningParenthesis) {
            try TTNSTMValueParser.parseTuple("a, b)")
        }
        #expect(throws: TTNSTMValueParserError.missingClosingParenthesis) {
            try TTNSTMValueParser.parseTuple("(a, b")
        }
    }

    @Test("parses a coordinate tuple")
    func coordinate() {
        let coordinate = TTNSTMValueParser.parseCoordinate("(43.69360, -90.68990)")
        #expect(coordinate?.latitude == 43.69360)
        #expect(coordinate?.longitude == -90.68990)
    }

    @Test("returns nil for a malformed coordinate")
    func malformedCoordinate() {
        #expect(TTNSTMValueParser.parseCoordinate("(43.69360)") == nil)
        #expect(TTNSTMValueParser.parseCoordinate("(lat, lon)") == nil)
    }

    @Test("parses an RGB tuple")
    func rgb() {
        let rgb = TTNSTMValueParser.parseRGB("(194, 187, 96)")
        #expect(rgb == RGB(red: 194, green: 187, blue: 96))
    }

    @Test("returns nil for an out-of-range RGB")
    func outOfRangeRGB() {
        #expect(TTNSTMValueParser.parseRGB("(256, 0, 0)") == nil)
    }

    @Test("parses a station tuple")
    func station() {
        let station = TTNSTMValueParser.parseStation("(pIDH3Q, FM107.5)")
        #expect(station == TTNSTMStation(stationID: "pIDH3Q", frequency: "FM107.5"))
    }
}

@Suite("TTN/STM weather config parser")
struct TTNSTMWeatherConfigParserTests {

    private static let sample = """
        DopplerWeatherRadarProtocolVersionID="1.0"
        DWR_Area_ID="035apk"
        StationList="(pIDH3Q,FM107.5)";"(pIERmg,FM93.9)";"(pIEhwg,FM103.5)";"(pIDS0w,FM95.5)";"(pIAZvA,FM102.7)"
        Coordinates="(43.69360,-90.68990)";"(39.67031,-85.30001)"
        Legend_Rain="(1,(0,255,0))";"(2,(0,170,0))";"(3,(0,102,0))";"(4,(255,238,0))";"(5,(238,119,0))";"(6,(221,0,0))"
        Legend_MixIce="(1,(255,170,255))";"(2,(244,85,176))"
        Legend_Snow="(1,(0,255,255))";"(2,(0,0,255))"
        CopyrightNotice="Copyright © 2026 iHeartMedia, Inc. All rights reserved."
        """

    @Test("parses the weather sample")
    func parseWeatherSample() throws {
        let config = try TTNSTMWeatherConfigParser.parse(Self.sample)

        #expect(config.protocolVersionID == "1.0")
        #expect(config.areaID == "035apk")
        #expect(config.copyrightNotice == "Copyright © 2026 iHeartMedia, Inc. All rights reserved.")

        #expect(config.stationList.count == 5)
        #expect(config.stationList.first == TTNSTMStation(stationID: "pIDH3Q", frequency: "FM107.5"))
        #expect(config.stationList.last == TTNSTMStation(stationID: "pIAZvA", frequency: "FM102.7"))

        #expect(config.coordinates.count == 2)
        #expect(config.coordinates[0] == Location(latitude: 43.69360, longitude: -90.68990))
        #expect(config.coordinates[1] == Location(latitude: 39.67031, longitude: -85.30001))

        #expect(config.legendRain.count == 6)
        #expect(config.legendRain[0] == TTNSTMLegendEntry(level: 1, color: RGB(red: 0, green: 255, blue: 0)))
        #expect(config.legendRain[5] == TTNSTMLegendEntry(level: 6, color: RGB(red: 221, green: 0, blue: 0)))

        #expect(config.legendMixIce.count == 2)
        #expect(
            config.legendMixIce[1] == TTNSTMLegendEntry(level: 2, color: RGB(red: 244, green: 85, blue: 176)))

        #expect(config.legendSnow.count == 2)
        #expect(config.legendSnow[1] == TTNSTMLegendEntry(level: 2, color: RGB(red: 0, green: 0, blue: 255)))
    }

    @Test("throws when a required weather key is missing")
    func missingKey() {
        let input = #"DWR_Area_ID="035apk""#
        #expect(throws: TTNSTMWeatherConfigError.missingKey("DopplerWeatherRadarProtocolVersionID")) {
            try TTNSTMWeatherConfigParser.parse(input)
        }
    }

    @Test("throws on a malformed legend entry")
    func malformedLegend() {
        let input = """
            DopplerWeatherRadarProtocolVersionID="1.0"
            DWR_Area_ID="035apk"
            Legend_Rain="(bad)"
            CopyrightNotice="n/a"
            """
        #expect(throws: TTNSTMWeatherConfigError.invalidValue(key: "Legend", value: "(bad)")) {
            try TTNSTMWeatherConfigParser.parse(input)
        }
    }
}

@Suite("TTN/STM traffic config parser")
struct TTNSTMTrafficConfigParserTests {

    private static let sample = """
        TrafficMapProtocolVersionID="1.3"
        TrafficMapID="035apk"
        StationList="(pIDH3Q,FM107.5)";"(pIERmg,FM93.9)";"(pIEhwg,FM103.5)";"(pIDS0w,FM95.5)";"(pIAZvA,FM102.7)"
        NumRows="3"
        NumColumns="3"
        NumTransmittedTiles="9"
        CoordinatesRow1="(42.38202,-88.35461)";"(42.02510,-87.99769)";"(42.38202,-87.64077)";"(42.02510,-87.28385)"
        CoordinatesRow2="(42.02510,-88.35461)";"(41.66818,-87.99769)";"(42.02510,-87.64077)";"(41.66818,-87.28385)"
        CoordinatesRow3="(41.66818,-88.35461)";"(41.31126,-87.99769)";"(41.66818,-87.64077)";"(41.31126,-87.28385)"
        BackgroundRGBColor="(194,187,96)"
        CopyrightNotice="Copyright © 2014 iHeartMedia, Inc. All rights reserved."
        """

    @Test("parses the traffic sample")
    func parseTrafficSample() throws {
        let config = try TTNSTMTrafficConfigParser.parse(Self.sample)

        #expect(config.protocolVersionID == "1.3")
        #expect(config.trafficMapID == "035apk")
        #expect(config.numRows == 3)
        #expect(config.numColumns == 3)
        #expect(config.numTransmittedTiles == 9)
        #expect(config.copyrightNotice == "Copyright © 2014 iHeartMedia, Inc. All rights reserved.")

        #expect(config.stationList.count == 5)
        #expect(config.stationList[2] == TTNSTMStation(stationID: "pIEhwg", frequency: "FM103.5"))

        #expect(config.coordinatesRows.count == 3)
        #expect(config.coordinatesRows[0].count == 4)
        #expect(config.coordinatesRows[0][0] == Location(latitude: 42.38202, longitude: -88.35461))
        #expect(config.coordinatesRows[2][3] == Location(latitude: 41.31126, longitude: -87.28385))

        #expect(config.backgroundRGBColor == RGB(red: 194, green: 187, blue: 96))
    }

    @Test("throws when a required traffic key is missing")
    func missingKey() {
        let input = #"TrafficMapID="035apk""#
        #expect(throws: TTNSTMTrafficConfigError.missingKey("TrafficMapProtocolVersionID")) {
            try TTNSTMTrafficConfigParser.parse(input)
        }
    }

    @Test("throws when a coordinates row is missing")
    func missingCoordinatesRow() {
        let input = """
            TrafficMapProtocolVersionID="1.3"
            TrafficMapID="035apk"
            NumRows="2"
            NumColumns="3"
            NumTransmittedTiles="6"
            CoordinatesRow1="(0,0)";"(1,1)";"(2,2)";"(3,3)"
            BackgroundRGBColor="(0,0,0)"
            CopyrightNotice="n/a"
            """
        #expect(throws: TTNSTMTrafficConfigError.missingKey("CoordinatesRow2")) {
            try TTNSTMTrafficConfigParser.parse(input)
        }
    }
}

@Suite("TTN/STM sample files")
struct TTNSTMSampleFileTests {

    @Test("loads and parses the bundled weather sample")
    func parseBundledWeatherSample() throws {
        let url = try sampleURL(named: "1635_DWRI_035apk_rev02_0663", directory: "weather_sample")
        let text = try String(contentsOf: url, encoding: .utf8)
        let config = try TTNSTMWeatherConfigParser.parse(text)
        #expect(config.areaID == "035apk")
        #expect(config.protocolVersionID == "1.0")
    }

    @Test("loads and parses the bundled traffic sample")
    func parseBundledTrafficSample() throws {
        let url = try sampleURL(named: "330_TMI_035apk_rev5_014a", directory: "traffic_sample")
        let text = try String(contentsOf: url, encoding: .utf8)
        let config = try TTNSTMTrafficConfigParser.parse(text)
        #expect(config.trafficMapID == "035apk")
        #expect(config.protocolVersionID == "1.3")
    }

    /// Locate a `.txt` sample file relative to this test source file.
    private func sampleURL(named name: String, directory: String) throws -> URL {
        let testsDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url =
            testsDirectory
            .appendingPathComponent("Resources")
            .appendingPathComponent(directory)
            .appendingPathComponent(name)
            .appendingPathExtension("txt")

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SampleLocationError.fileNotFound(url.path)
        }
        return url
    }

    private enum SampleLocationError: Error {
        case fileNotFound(String)
    }
}
