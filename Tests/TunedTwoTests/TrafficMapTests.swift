//
//  TrafficMapTests.swift
//  TunedTwoTests
//
//  Headless tests for traffic-map parsing, ingest rules, and stitching.
//  Pure CoreGraphics: no AppKit, no window server, no app host — the test
//  bundle links only against TunedTwoCore.
//

import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import TunedTwoCore

@Suite("TrafficMap parsing")
struct TrafficMapTests {

    // MARK: - Filename parsing

    @Test("parses a valid TMT filename")
    func parseValidName() throws {
        let info = try #require(TrafficMap.parseLOTName("TMT_035apk_2_1_20260914_1514_036f.png"))

        #expect(info.provider == "035apk")
        // First grid component is the row, second is the column:
        // 2_1 = middle row, left column.
        #expect(info.row == 2)
        #expect(info.column == 1)
        #expect(info.hex == 0x036f)

        let expectedTimestamp = Self.utcDate(year: 2026, month: 9, day: 14, hour: 15, minute: 14)
        #expect(info.timestamp == expectedTimestamp)
    }

    @Test("parses hex digits in uppercase")
    func parseUppercaseHex() throws {
        let info = try #require(TrafficMap.parseLOTName("TMT_000n3_0_0_20260101_0000_ABCD.png"))
        #expect(info.hex == 0xabcd)
    }

    @Test("returns nil for a non-PNG extension")
    func rejectsOtherExtensions() {
        #expect(TrafficMap.parseLOTName("TMT_035apk_2_1_20260914_1514_036f.jpg") == nil)
    }

    @Test("returns nil when the TMT prefix is missing")
    func rejectsMissingPrefix() {
        #expect(TrafficMap.parseLOTName("WRONG_035apk_2_1_20260914_1514_036f.png") == nil)
    }

    @Test("returns nil when a component is missing")
    func rejectsMissingComponent() {
        #expect(TrafficMap.parseLOTName("TMT_035apk_2_1_20260914_036f.png") == nil)
    }

    @Test("returns nil when row or column are not integers")
    func rejectsNonIntegerCoordinates() {
        #expect(TrafficMap.parseLOTName("TMT_035apk_a_1_20260914_1514_036f.png") == nil)
        #expect(TrafficMap.parseLOTName("TMT_035apk_2_b_20260914_1514_036f.png") == nil)
    }

    @Test("returns nil for malformed hex")
    func rejectsInvalidHex() {
        #expect(TrafficMap.parseLOTName("TMT_035apk_2_1_20260914_1514_gggg.png") == nil)
        #expect(TrafficMap.parseLOTName("TMT_035apk_2_1_20260914_1514_12345.png") == nil)
    }

    // MARK: - Ingest outcomes

    @Test("rejects non-TMT filenames without storing anything")
    func rejectsNonTMTFiles() throws {
        var map = TrafficMap()
        let png = try #require(Self.pngData(color: Self.red, width: 8, height: 8))

        let outcome = map.processImageFile(name: "STN_035apk_2_1_20260914_1514_036f.png", data: Array(png))
        #expect(outcome == .notTrafficMapFile)
        #expect(map.tiles.allSatisfy { $0 == nil })
        #expect(map.provider == nil)
    }

    @Test("rejects undecodable image bytes")
    func rejectsUndecodableBytes() {
        var map = TrafficMap()
        let outcome = map.processImageFile(name: "TMT_prov_1_1_20260914_1514_0001.png", data: Array("not a png".utf8))
        #expect(outcome == .undecodableImage)
        #expect(map.tiles.allSatisfy { $0 == nil })
    }

    @Test("rejects grid coordinates outside 1...3 instead of trapping")
    func rejectsOutOfBoundsGrid() {
        var map = TrafficMap()

        // Row/column of 0 parse fine but are outside the grid.
        #expect(
            map.processImageFile(name: "TMT_prov_0_0_20260914_1514_0001.png", data: [0x89, 0x50, 0x4E, 0x47])
                == .outOfGrid)
        #expect(
            map.processImageFile(name: "TMT_prov_4_1_20260914_1514_0001.png", data: [0x89, 0x50, 0x4E, 0x47])
                == .outOfGrid)
        #expect(
            map.processImageFile(name: "TMT_prov_1_4_20260914_1514_0001.png", data: [0x89, 0x50, 0x4E, 0x47])
                == .outOfGrid)
        #expect(map.tiles.allSatisfy { $0 == nil })
    }

    @Test("retains parsed tile metadata")
    func retainsTileInfo() throws {
        var map = TrafficMap()
        let png = try #require(Self.pngData(color: Self.red, width: 8, height: 8))
        map.processImageFile(name: "TMT_035apk_2_1_20260914_1514_036f.png", data: Array(png))

        let tile = try #require(map.tiles[(2 - 1) * 3 + (1 - 1)])
        #expect(tile.info.provider == "035apk")
        #expect(tile.info.row == 2)
        #expect(tile.info.column == 1)
        #expect(tile.info.timestamp == Self.utcDate(year: 2026, month: 9, day: 14, hour: 15, minute: 14))
        #expect(map.provider == "035apk")
    }

    // MARK: - Newer-wins rule

    @Test("keeps the stored tile when an older duplicate arrives")
    func ignoresStaleTile() throws {
        var map = TrafficMap()
        let newer = try #require(Self.pngData(color: Self.red, width: 8, height: 8))
        let older = try #require(Self.pngData(color: Self.blue, width: 8, height: 8))

        map.processImageFile(name: "TMT_prov_1_1_20260914_1500_0001.png", data: Array(newer))
        let outcome = map.processImageFile(name: "TMT_prov_1_1_20260913_1500_0002.png", data: Array(older))

        #expect(
            outcome
                == .ignoredStale(
                    existingTimestamp: Self.utcDate(year: 2026, month: 9, day: 14, hour: 15, minute: 0),
                    incomingTimestamp: Self.utcDate(year: 2026, month: 9, day: 13, hour: 15, minute: 0)))
        #expect(map.tiles[0]?.info.hex == 0x0001)
    }

    @Test("replaces the stored tile when the timestamp is equal (retransmission)")
    func equalTimestampReplaces() throws {
        var map = TrafficMap()
        let first = try #require(Self.pngData(color: Self.red, width: 8, height: 8))
        let retransmission = try #require(Self.pngData(color: Self.green, width: 8, height: 8))

        map.processImageFile(name: "TMT_prov_1_1_20260914_1500_0001.png", data: Array(first))
        let outcome = map.processImageFile(name: "TMT_prov_1_1_20260914_1500_0002.png", data: Array(retransmission))

        #expect(outcome == .stored)
        #expect(map.tiles[0]?.info.hex == 0x0002)

        let composite = try #require(map.composite)
        #expect(Self.pixelColor(in: composite, x: 4, yFromTop: 4) == Self.green)
    }

    @Test("replaces the stored tile when a newer one arrives")
    func newerTileReplaces() throws {
        var map = TrafficMap()
        let older = try #require(Self.pngData(color: Self.red, width: 8, height: 8))
        let newer = try #require(Self.pngData(color: Self.blue, width: 8, height: 8))

        map.processImageFile(name: "TMT_prov_1_1_20260914_1500_0001.png", data: Array(older))
        let outcome = map.processImageFile(name: "TMT_prov_1_1_20260914_1600_0002.png", data: Array(newer))

        #expect(outcome == .stored)
        #expect(map.tiles[0]?.info.hex == 0x0002)

        let composite = try #require(map.composite)
        #expect(Self.pixelColor(in: composite, x: 4, yFromTop: 4) == Self.blue)
    }

    // MARK: - Provider reset

    @Test("a new provider resets the map")
    func providerChangeResets() throws {
        var map = TrafficMap()
        let tileA = try #require(Self.pngData(color: Self.red, width: 8, height: 8))
        let tileB = try #require(Self.pngData(color: Self.cyan, width: 8, height: 8))

        map.processImageFile(name: "TMT_035apk_1_1_20260914_1500_0001.png", data: Array(tileA))
        map.processImageFile(name: "TMT_035apk_3_3_20260914_1500_0002.png", data: Array(tileA))
        #expect(map.tiles.compactMap { $0 }.count == 2)

        // A tile from a different provider wipes the previous map.
        let outcome = map.processImageFile(name: "TMT_941xyz_2_2_20260914_1600_0003.png", data: Array(tileB))
        #expect(outcome == .stored)
        #expect(map.provider == "941xyz")
        #expect(map.tiles.compactMap { $0 }.count == 1)

        // The old provider's tiles are gone; only 2_2 (middle) holds a tile.
        let composite = try #require(map.composite)
        #expect(Self.pixelColor(in: composite, x: 4, yFromTop: 4) == Self.mapBackground)
        #expect(Self.pixelColor(in: composite, x: 12, yFromTop: 12) == Self.cyan)
        #expect(Self.pixelColor(in: composite, x: 20, yFromTop: 20) == Self.mapBackground)
    }

    // MARK: - Config files

    @Test("stores a parsed config file")
    func storesConfigFile() {
        var map = TrafficMap()
        let outcome = map.processConfigFile(data: Array(Self.sampleConfig.utf8))
        #expect(outcome == .storedConfig)
        #expect(map.provider == "035apk")
        #expect(map.config?.trafficMapID == "035apk")
        #expect(map.config?.backgroundRGBColor == TTNSTMRGB(red: 194, green: 187, blue: 96))
    }

    @Test("reports an invalid config file")
    func invalidConfigFile() {
        var map = TrafficMap()
        let outcome = map.processConfigFile(data: Array("not a config".utf8))
        #expect(outcome == .invalidConfig)
        #expect(map.config == nil)
    }

    @Test("a config from a different provider resets the map")
    func configProviderChangeResets() throws {
        var map = TrafficMap()
        let tile = try #require(Self.pngData(color: Self.red, width: 8, height: 8))
        map.processImageFile(name: "TMT_035apk_1_1_20260914_1500_0001.png", data: Array(tile))
        #expect(map.tiles.compactMap { $0 }.count == 1)

        let config = """
            TrafficMapProtocolVersionID="1.3"
            TrafficMapID="941xyz"
            StationList="(pIDH3Q,FM107.5)"
            NumRows="3"
            NumColumns="3"
            NumTransmittedTiles="9"
            CoordinatesRow1="(0,0)";"(1,1)";"(2,2)";"(3,3)"
            CoordinatesRow2="(0,0)";"(1,1)";"(2,2)";"(3,3)"
            CoordinatesRow3="(0,0)";"(1,1)";"(2,2)";"(3,3)"
            BackgroundRGBColor="(194,187,96)"
            CopyrightNotice="n/a"
            """
        let outcome = map.processConfigFile(data: Array(config.utf8))
        #expect(outcome == .storedConfig)
        #expect(map.provider == "941xyz")
        #expect(map.tiles.compactMap { $0 }.count == 0)
    }

    @Test("uses the config background color in the composite")
    func configBackgroundColorOverride() throws {
        var map = TrafficMap()
        let tile = try #require(Self.pngData(color: Self.red, width: 10, height: 10))
        map.processImageFile(name: "TMT_035apk_1_1_20260914_1500_0001.png", data: Array(tile))

        let config = """
            TrafficMapProtocolVersionID="1.3"
            TrafficMapID="035apk"
            StationList="(pIDH3Q,FM107.5)"
            NumRows="3"
            NumColumns="3"
            NumTransmittedTiles="9"
            CoordinatesRow1="(0,0)";"(1,1)";"(2,2)";"(3,3)"
            CoordinatesRow2="(0,0)";"(1,1)";"(2,2)";"(3,3)"
            CoordinatesRow3="(0,0)";"(1,1)";"(2,2)";"(3,3)"
            BackgroundRGBColor="(255,0,0)"
            CopyrightNotice="n/a"
            """
        map.processConfigFile(data: Array(config.utf8))

        let composite = try #require(map.composite)
        // Bottom-right background cell should now be red instead of the default tan.
        #expect(Self.pixelColor(in: composite, x: 25, yFromTop: 25) == Self.red)
    }

    // MARK: - Helpers

    private static let sampleConfig = """
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

    // MARK: - Tile stitching

    @Test("leaves composite nil when no tiles are available")
    func noTilesEmptyComposite() {
        let map = TrafficMap()
        #expect(map.composite == nil)
    }

    @Test("stitches a single tile onto a 3x3 background canvas")
    func stitchesSingleTile() throws {
        var map = TrafficMap()
        let tileData = try #require(Self.pngData(color: Self.red, width: 10, height: 10))

        // 1_1 is the upper-left tile.
        map.processImageFile(name: "TMT_prov_1_1_20260914_1514_0001.png", data: Array(tileData))

        let composite = try #require(map.composite)
        #expect(composite.width == 30)
        #expect(composite.height == 30)

        // The upper-left cell matches the tile color; the rest is background.
        #expect(Self.pixelColor(in: composite, x: 4, yFromTop: 4) == Self.red)
        #expect(Self.pixelColor(in: composite, x: 25, yFromTop: 25) == Self.mapBackground)
        #expect(Self.pixelColor(in: composite, x: 25, yFromTop: 4) == Self.mapBackground)
        #expect(Self.pixelColor(in: composite, x: 4, yFromTop: 25) == Self.mapBackground)
    }

    @Test("places tiles in the correct 3x3 grid positions (row 1 = top, column 1 = left)")
    func stitchesTileGrid() throws {
        var map = TrafficMap()
        // colors[row - 1][column - 1]
        let colors: [[(CGFloat, CGFloat, CGFloat)]] = [
            [Self.red, Self.green, Self.blue],
            [Self.yellow, Self.cyan, Self.magenta],
            [Self.orange, Self.purple, Self.brown],
        ]

        for row in 1...3 {
            for column in 1...3 {
                let color = colors[row - 1][column - 1]
                let tileData = try #require(Self.pngData(color: color, width: 8, height: 8))
                let name = String(
                    format: "TMT_prov_%d_%d_20260914_1514_%04x.png", row, column, (row - 1) * 3 + (column - 1))
                map.processImageFile(name: name, data: Array(tileData))
            }
        }

        let composite = try #require(map.composite)
        #expect(composite.width == 24)
        #expect(composite.height == 24)

        // Sample the center of each grid cell.
        for row in 1...3 {
            for column in 1...3 {
                let point = (x: (column - 1) * 8 + 4, yFromTop: (row - 1) * 8 + 4)
                #expect(
                    Self.pixelColor(in: composite, x: point.x, yFromTop: point.yFromTop) == colors[row - 1][column - 1]
                )
            }
        }
    }

    // MARK: - Helpers

    private static let red = (CGFloat(1), CGFloat(0), CGFloat(0))
    private static let green = (CGFloat(0), CGFloat(1), CGFloat(0))
    private static let blue = (CGFloat(0), CGFloat(0), CGFloat(1))
    private static let cyan = (CGFloat(0), CGFloat(1), CGFloat(1))
    private static let mapBackground = (CGFloat(194) / 255, CGFloat(187) / 255, CGFloat(96) / 255)

    private static let orange = (CGFloat(1), CGFloat(0.5), CGFloat(0))
    private static let purple = (CGFloat(0.5), CGFloat(0), CGFloat(0.5))
    private static let brown = (CGFloat(0.6), CGFloat(0.4), CGFloat(0.2))
    private static let yellow = (CGFloat(1), CGFloat(1), CGFloat(0))
    private static let magenta = (CGFloat(1), CGFloat(0), CGFloat(1))

    private static func utcDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return Calendar.utc.date(from: components)!
    }

    /// Render a solid color into a PNG, using only CoreGraphics.
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

    /// Read a pixel from a CGImage. `yFromTop` measures from the top of the
    /// image (row 1 of the traffic map is the top row).
    private static func pixelColor(in image: CGImage, x: Int, yFromTop: Int) -> (CGFloat, CGFloat, CGFloat)? {
        guard let context = Self.makeRGBContext(width: image.width, height: image.height) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let base = context.data else { return nil }
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        let offset = yFromTop * context.bytesPerRow + x * 4
        guard offset >= 0, offset + 2 < image.width * image.height * 4 else { return nil }
        return (CGFloat(bytes[offset]) / 255, CGFloat(bytes[offset + 1]) / 255, CGFloat(bytes[offset + 2]) / 255)
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

/// Exact RGB tuple equality for test colors (all colors here are opaque and
/// pass through the same sRGB pipeline, so exact comparison is meaningful).
private func == (lhs: (CGFloat, CGFloat, CGFloat)?, rhs: (CGFloat, CGFloat, CGFloat)) -> Bool {
    guard let lhs else { return false }
    let tolerance: CGFloat = 0.02
    return abs(lhs.0 - rhs.0) < tolerance && abs(lhs.1 - rhs.1) < tolerance && abs(lhs.2 - rhs.2) < tolerance
}
