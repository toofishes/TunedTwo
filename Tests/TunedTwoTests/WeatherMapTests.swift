//
//  WeatherMapTests.swift
//  TunedTwoTests
//
//  Headless tests for weather-radar filename parsing, ingest rules, and
//  config-file integration.
//

import CoreGraphics
import Foundation
import ImageIO
import MapKit
import Testing

@testable import TunedTwoCore

@Suite("WeatherMap parsing")
struct WeatherMapTests {

    // MARK: - Filename parsing

    @Test("parses a valid DWRO filename")
    func parseValidName() throws {
        let info = try #require(WeatherMap.parseLOTName("DWRO_035apk_rev02_20260916_1358_040f.png"))

        #expect(info.provider == "035apk")
        #expect(info.revision == "rev02")
        #expect(info.hex == 0x040f)

        let expectedTimestamp = Self.utcDate(year: 2026, month: 9, day: 16, hour: 13, minute: 58)
        #expect(info.timestamp == expectedTimestamp)
    }

    @Test("returns nil for a non-PNG extension")
    func rejectsOtherExtensions() {
        #expect(WeatherMap.parseLOTName("DWRO_035apk_rev02_20260916_1358_040f.jpg") == nil)
    }

    @Test("returns nil when the DWRO prefix is missing")
    func rejectsMissingPrefix() {
        #expect(WeatherMap.parseLOTName("WRONG_035apk_rev02_20260916_1358_040f.png") == nil)
    }

    // MARK: - Ingest outcomes

    @Test("rejects non-DWRO filenames without storing anything")
    func rejectsNonWeatherFiles() throws {
        var map = WeatherMap()
        let png = try #require(Self.pngData(color: Self.red, width: 8, height: 8))

        let outcome = map.processImageFile(name: "STN_035apk_rev02_20260916_1358_040f.png", data: png)
        #expect(outcome == .notWeatherMapFile)
        #expect(map.image == nil)
        #expect(map.provider == nil)
    }

    @Test("rejects undecodable image bytes")
    func rejectsUndecodableBytes() {
        var map = WeatherMap()
        let outcome = map.processImageFile(
            name: "DWRO_035apk_rev02_20260916_1358_040f.png", data: Data("not a png".utf8))
        #expect(outcome == .undecodableImage)
        #expect(map.image == nil)
    }

    @Test("retains parsed image metadata")
    func retainsImageInfo() throws {
        var map = WeatherMap()
        let png = try #require(Self.pngData(color: Self.red, width: 8, height: 8))
        map.processImageFile(name: "DWRO_035apk_rev02_20260916_1358_040f.png", data: png)

        #expect(map.provider == "035apk")
        #expect(map.timestamp == Self.utcDate(year: 2026, month: 9, day: 16, hour: 13, minute: 58))
        #expect(map.image != nil)
    }

    // MARK: - Newer-wins rule

    @Test("keeps the stored image when an older one arrives")
    func ignoresStaleImage() throws {
        var map = WeatherMap()
        let newer = try #require(Self.pngData(color: Self.red, width: 8, height: 8))
        let older = try #require(Self.pngData(color: Self.blue, width: 8, height: 8))

        map.processImageFile(name: "DWRO_prov_rev01_20260916_1500_0001.png", data: newer)
        let outcome = map.processImageFile(name: "DWRO_prov_rev01_20260915_1500_0002.png", data: older)

        #expect(
            outcome
                == .ignoredStale(
                    existingTimestamp: Self.utcDate(year: 2026, month: 9, day: 16, hour: 15, minute: 0),
                    incomingTimestamp: Self.utcDate(year: 2026, month: 9, day: 15, hour: 15, minute: 0)))
        #expect(map.timestamp == Self.utcDate(year: 2026, month: 9, day: 16, hour: 15, minute: 0))
    }

    // MARK: - Config files

    @Test("stores a parsed config file")
    func storesConfigFile() {
        var map = WeatherMap()
        let outcome = map.processConfigFile(data: Data(Self.sampleConfig.utf8))
        #expect(outcome == .storedConfig)
        #expect(map.provider == "035apk")
        #expect(map.coordinates?.count == 2)
    }

    @Test("reports an invalid config file")
    func invalidConfigFile() {
        var map = WeatherMap()
        let outcome = map.processConfigFile(data: Data("not a config".utf8))
        #expect(outcome == .invalidConfig)
    }

    @Test("a config from a different provider clears the stored image")
    func configProviderChangeClearsImage() throws {
        var map = WeatherMap()
        let png = try #require(Self.pngData(color: Self.red, width: 8, height: 8))
        map.processImageFile(name: "DWRO_035apk_rev02_20260916_1358_040f.png", data: png)
        #expect(map.image != nil)

        let config = """
            DopplerWeatherRadarProtocolVersionID="1.0"
            DWR_Area_ID="941xyz"
            StationList="(pIDH3Q,FM107.5)"
            Coordinates="(0,0)";"(1,1)"
            Legend_Rain="(1,(0,255,0))"
            Legend_MixIce="(1,(255,170,255))"
            Legend_Snow="(1,(0,255,255))"
            CopyrightNotice="n/a"
            """
        let outcome = map.processConfigFile(data: Data(config.utf8))
        #expect(outcome == .storedConfig)
        #expect(map.provider == "941xyz")
        #expect(map.image == nil)
    }

    // MARK: - Helpers

    private static let sampleConfig = """
        DopplerWeatherRadarProtocolVersionID="1.0"
        DWR_Area_ID="035apk"
        StationList="(pIDH3Q,FM107.5)";"(pIERmg,FM93.9)";"(pIEhwg,FM103.5)";"(pIDS0w,FM95.5)";"(pIAZvA,FM102.7)"
        Coordinates="(43.69360,-90.68990)";"(39.67031,-85.30001)"
        Legend_Rain="(1,(0,255,0))";"(2,(0,170,0))";"(3,(0,102,0))";"(4,(255,238,0))";"(5,(238,119,0))";"(6,(221,0,0))"
        Legend_MixIce="(1,(255,170,255))";"(2,(244,85,176))"
        Legend_Snow="(1,(0,255,255))";"(2,(0,0,255))"
        CopyrightNotice="Copyright © 2026 iHeartMedia, Inc. All rights reserved."
        """

    private static let red = (CGFloat(1), CGFloat(0), CGFloat(0))
    private static let blue = (CGFloat(0), CGFloat(0), CGFloat(1))

    private static func utcDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return Calendar.utc.date(from: components)!
    }

    private static func pngData(color: (CGFloat, CGFloat, CGFloat), width: Int, height: Int) -> Data? {
        guard let context = Self.makeRGBContext(width: width, height: height) else { return nil }
        context.setFillColor(red: color.0, green: color.1, blue: color.2, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { return nil }

        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(mutableData, "public.png" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return mutableData as Data
    }

    private static func makeRGBContext(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }
}
