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

        let expectedTimestamp = MapTestHelpers.utcDate(year: 2026, month: 9, day: 14, hour: 15, minute: 14)
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
        let png = try #require(MapTestHelpers.pngData(color: MapTestHelpers.red, width: 8, height: 8))

        let outcome = map.processImageFile(name: "STN_035apk_2_1_20260914_1514_036f.png", data: png)
        #expect(outcome == .notTrafficMapFile)
        #expect(map.populatedTileCount() == 0)
        #expect(map.provider == nil)
    }

    @Test("rejects undecodable image bytes")
    func rejectsUndecodableBytes() {
        var map = TrafficMap()
        let outcome = map.processImageFile(name: "TMT_prov_1_1_20260914_1514_0001.png", data: Data("not a png".utf8))
        #expect(outcome == .undecodableImage)
        #expect(map.populatedTileCount() == 0)
    }

    @Test("rejects grid coordinates outside 1...3 instead of trapping")
    func rejectsOutOfBoundsGrid() {
        var map = TrafficMap()

        // Row/column of 0 parse fine but are outside the grid.
        #expect(
            map.processImageFile(name: "TMT_prov_0_0_20260914_1514_0001.png", data: Data([0x89, 0x50, 0x4E, 0x47]))
                == .outOfGrid)
        #expect(
            map.processImageFile(name: "TMT_prov_4_1_20260914_1514_0001.png", data: Data([0x89, 0x50, 0x4E, 0x47]))
                == .outOfGrid)
        #expect(
            map.processImageFile(name: "TMT_prov_1_4_20260914_1514_0001.png", data: Data([0x89, 0x50, 0x4E, 0x47]))
                == .outOfGrid)
        #expect(map.populatedTileCount() == 0)
    }

    // MARK: - Newer-wins rule

    @Test("keeps the stored tile when an older duplicate arrives")
    func ignoresStaleTile() throws {
        var map = TrafficMap()
        let newer = try #require(MapTestHelpers.pngData(color: MapTestHelpers.red, width: 8, height: 8))
        let older = try #require(MapTestHelpers.pngData(color: MapTestHelpers.blue, width: 8, height: 8))

        map.processImageFile(name: "TMT_prov_1_1_20260914_1500_0001.png", data: newer)
        let outcome = map.processImageFile(name: "TMT_prov_1_1_20260913_1500_0002.png", data: older)

        #expect(
            outcome
                == .ignoredStale(
                    existingTimestamp: MapTestHelpers.utcDate(year: 2026, month: 9, day: 14, hour: 15, minute: 0),
                    incomingTimestamp: MapTestHelpers.utcDate(year: 2026, month: 9, day: 13, hour: 15, minute: 0)))
    }

    @Test("replaces the stored tile when the timestamp is equal (retransmission)")
    func equalTimestampReplaces() throws {
        var map = TrafficMap()
        let first = try #require(MapTestHelpers.pngData(color: MapTestHelpers.red, width: 8, height: 8))
        let retransmission = try #require(MapTestHelpers.pngData(color: MapTestHelpers.green, width: 8, height: 8))

        map.processImageFile(name: "TMT_prov_1_1_20260914_1500_0001.png", data: first)
        let outcome = map.processImageFile(name: "TMT_prov_1_1_20260914_1500_0002.png", data: retransmission)

        #expect(outcome == .stored)

        let composite = try #require(map.composite)
        #expect(MapTestHelpers.pixelColor(in: composite, x: 4, yFromTop: 4) == MapTestHelpers.green)
    }

    @Test("replaces the stored tile when a newer one arrives")
    func newerTileReplaces() throws {
        var map = TrafficMap()
        let older = try #require(MapTestHelpers.pngData(color: MapTestHelpers.red, width: 8, height: 8))
        let newer = try #require(MapTestHelpers.pngData(color: MapTestHelpers.blue, width: 8, height: 8))

        map.processImageFile(name: "TMT_prov_1_1_20260914_1500_0001.png", data: older)
        let outcome = map.processImageFile(name: "TMT_prov_1_1_20260914_1600_0002.png", data: newer)

        #expect(outcome == .stored)

        let composite = try #require(map.composite)
        #expect(MapTestHelpers.pixelColor(in: composite, x: 4, yFromTop: 4) == MapTestHelpers.blue)
    }

    // MARK: - Provider reset

    @Test("a new provider resets the map")
    func providerChangeResets() throws {
        var map = TrafficMap()
        let tileA = try #require(MapTestHelpers.pngData(color: MapTestHelpers.red, width: 8, height: 8))
        let tileB = try #require(MapTestHelpers.pngData(color: MapTestHelpers.cyan, width: 8, height: 8))

        map.processImageFile(name: "TMT_035apk_1_1_20260914_1500_0001.png", data: tileA)
        map.processImageFile(name: "TMT_035apk_3_3_20260914_1500_0002.png", data: tileA)
        #expect(map.populatedTileCount() == 2)

        // A tile from a different provider wipes the previous map.
        let outcome = map.processImageFile(name: "TMT_941xyz_2_2_20260914_1600_0003.png", data: tileB)
        #expect(outcome == .stored)
        #expect(map.provider == "941xyz")
        #expect(map.populatedTileCount() == 1)

        // The old provider's tiles are gone; only 2_2 (middle) holds a tile.
        let composite = try #require(map.composite)
        #expect(MapTestHelpers.pixelColor(in: composite, x: 4, yFromTop: 4) == MapTestHelpers.mapBackground)
        #expect(MapTestHelpers.pixelColor(in: composite, x: 12, yFromTop: 12) == MapTestHelpers.cyan)
        #expect(MapTestHelpers.pixelColor(in: composite, x: 20, yFromTop: 20) == MapTestHelpers.mapBackground)
    }

    @Test("reverts to default TTN background when a TTM tile replaces a HERE map")
    func ttmTileResetsBackgroundAfterHere() throws {
        var map = TrafficMap()
        let hereTile = try #require(MapTestHelpers.pngData(color: MapTestHelpers.red, width: 8, height: 8))
        let ttmTile = try #require(MapTestHelpers.pngData(color: MapTestHelpers.blue, width: 8, height: 8))

        map.processHereImageFile(hereImage: Self.hereTrafficTile(n1: 1, n2: 9, sequence: 1, data: hereTile))
        #expect(map.provider == "HERE")

        let outcome = map.processImageFile(name: "TMT_035apk_1_1_20260914_1500_0001.png", data: ttmTile)
        #expect(outcome == .stored)
        #expect(map.provider == "035apk")

        let composite = try #require(map.composite)
        #expect(composite.width == 24)
        #expect(composite.height == 24)
        // The stored tile is blue in the upper-left; the empty center cell
        // should use the default TTN tan, not the HERE background color.
        #expect(MapTestHelpers.pixelColor(in: composite, x: 12, yFromTop: 12) == MapTestHelpers.mapBackground)
    }

    // MARK: - Config files

    @Test("stores a parsed config file")
    func storesConfigFile() {
        var map = TrafficMap()
        let outcome = map.processConfigFile(data: Data(Self.sampleConfig.utf8))
        #expect(outcome == .storedConfig)
        #expect(map.provider == "035apk")
        #expect(map.config?.trafficMapID == "035apk")
        #expect(map.config?.backgroundRGBColor == RGB(red: 194, green: 187, blue: 96))
    }

    @Test("reports an invalid config file")
    func invalidConfigFile() {
        var map = TrafficMap()
        let outcome = map.processConfigFile(data: Data("not a config".utf8))
        #expect(outcome == .invalidConfig)
        #expect(map.config == nil)
    }

    @Test("a config from a different provider resets the map")
    func configProviderChangeResets() throws {
        var map = TrafficMap()
        let tile = try #require(MapTestHelpers.pngData(color: MapTestHelpers.red, width: 8, height: 8))
        map.processImageFile(name: "TMT_035apk_1_1_20260914_1500_0001.png", data: tile)
        #expect(map.populatedTileCount() == 1)

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
        let outcome = map.processConfigFile(data: Data(config.utf8))
        #expect(outcome == .storedConfig)
        #expect(map.provider == "941xyz")
        #expect(map.populatedTileCount() == 0)
    }

    @Test("uses the config background color in the composite")
    func configBackgroundColorOverride() throws {
        var map = TrafficMap()
        let tile = try #require(MapTestHelpers.pngData(color: MapTestHelpers.red, width: 10, height: 10))
        map.processImageFile(name: "TMT_035apk_1_1_20260914_1500_0001.png", data: tile)

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
        map.processConfigFile(data: Data(config.utf8))

        let composite = try #require(map.composite)
        // Bottom-right background cell should now be red instead of the default tan.
        #expect(MapTestHelpers.pixelColor(in: composite, x: 25, yFromTop: 25) == MapTestHelpers.red)
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

    // MARK: - HERE images

    @Test("stores a valid HERE traffic tile")
    func storesValidHereTrafficTile() throws {
        var map = TrafficMap()
        let tile = try #require(MapTestHelpers.pngData(color: MapTestHelpers.red, width: 8, height: 8))
        let hereImage = Self.hereTrafficTile(n1: 1, n2: 9, sequence: 1, data: tile)

        let outcome = map.processHereImageFile(hereImage: hereImage)

        #expect(outcome == .stored)
        #expect(map.provider == "HERE")
        #expect(map.populatedTileCount() == 1)
        #expect(map.tileCount() == 9)
    }

    @Test("rejects a HERE weather image as not a traffic map")
    func rejectsHereWeatherImage() throws {
        var map = TrafficMap()
        let tile = try #require(MapTestHelpers.pngData(color: MapTestHelpers.red, width: 8, height: 8))
        let hereImage = TunerHereImage(
            type: .weather,
            name: "WeatherImage_0_0_u40h.png",
            sequence: 1,
            n1: 1,
            n2: 1,
            time: MapTestHelpers.utcDate(year: 2026, month: 11, day: 4, hour: 23, minute: 36),
            boundingBox: (
                Location(latitude: 42.38810, longitude: -88.29440),
                Location(latitude: 41.56410, longitude: -87.47040)
            ),
            data: tile)

        let outcome = map.processHereImageFile(hereImage: hereImage)

        #expect(outcome == .notTrafficMapFile)
        #expect(map.populatedTileCount() == 0)
    }

    @Test("rejects undecodable HERE traffic bytes")
    func rejectsUndecodableHereTrafficBytes() {
        var map = TrafficMap()
        let hereImage = Self.hereTrafficTile(n1: 1, n2: 9, sequence: 1, data: Data("not a png".utf8))

        let outcome = map.processHereImageFile(hereImage: hereImage)

        #expect(outcome == .undecodableImage)
        #expect(map.populatedTileCount() == 0)
    }

    @Test("stitches HERE traffic tiles into the correct grid positions")
    func stitchesHereTrafficTiles() throws {
        var map = TrafficMap()
        // colors[row][column] using the 0-based row/column derived from n1.
        let colors: [[(CGFloat, CGFloat, CGFloat)]] = [
            [MapTestHelpers.red, MapTestHelpers.green, MapTestHelpers.blue],
            [MapTestHelpers.yellow, MapTestHelpers.cyan, MapTestHelpers.magenta],
            [MapTestHelpers.orange, MapTestHelpers.purple, MapTestHelpers.brown],
        ]

        for n1 in 1...9 {
            let row = (n1 - 1) / 3
            let column = (n1 - 1) % 3
            let color = colors[row][column]
            let tile = try #require(MapTestHelpers.pngData(color: color, width: 8, height: 8))
            let hereImage = Self.hereTrafficTile(n1: n1, n2: 9, sequence: 1, data: tile)
            map.processHereImageFile(hereImage: hereImage)
        }

        #expect(map.populatedTileCount() == 9)

        let composite = try #require(map.composite)
        #expect(composite.width == 24)
        #expect(composite.height == 24)

        for n1 in 1...9 {
            let row = (n1 - 1) / 3
            let column = (n1 - 1) % 3
            let point = (x: column * 8 + 4, yFromTop: row * 8 + 4)
            #expect(
                MapTestHelpers.pixelColor(in: composite, x: point.x, yFromTop: point.yFromTop) == colors[row][column])
        }
    }

    @Test("parses a HERE traffic filename")
    func parseHereTrafficName() throws {
        let info = try #require(TrafficMap.parseHereTrafficName("1793835363_trafficMap_1_2_u40h.png"))

        #expect(info.name == "1793835363_trafficMap_1_2_u40h.png")
        #expect(info.sequence == 65535)
        #expect(info.n1 == 6)
        #expect(info.n2 == 9)
        #expect(info.time == Date(timeIntervalSince1970: 1_793_835_363))
    }

    @Test("parses a HERE traffic filename ignoring any trailing suffix")
    func parseHereTrafficNameIgnoresTrailingSuffix() throws {
        let info = try #require(TrafficMap.parseHereTrafficName("1793835363_trafficMap_0_0.png"))

        #expect(info.n1 == 1)
        #expect(info.n2 == 9)
    }

    @Test("returns nil for non-HERE traffic filenames")
    func rejectsNonHereTrafficNames() {
        #expect(TrafficMap.parseHereTrafficName("WeatherImage_0_0_u40h.png") == nil)
        #expect(TrafficMap.parseHereTrafficName("TMT_035apk_1_1_20260914_1514_036f.png") == nil)
        #expect(TrafficMap.parseHereTrafficName("1793835363_trafficMap_0_0_u40h.jpg") == nil)
        #expect(TrafficMap.parseHereTrafficName("1793835363_trafficMap_3_0_u40h.png") == nil)
        #expect(TrafficMap.parseHereTrafficName("trafficMap_0_0_u40h.png") == nil)
    }

    @Test("stores a HERE traffic tile from file metadata")
    func storesHereTrafficTileFromInfo() throws {
        var map = TrafficMap()
        let tile = try #require(MapTestHelpers.pngData(color: MapTestHelpers.red, width: 8, height: 8))
        let info = HereTrafficFileInfo(
            name: "trafficMap_1_1_u40h.png", sequence: 65535, n1: 5, n2: 9,
            time: MapTestHelpers.utcDate(year: 2026, month: 11, day: 4, hour: 23, minute: 31))

        let outcome = map.processHereImageFile(info: info, data: tile)

        #expect(outcome == .stored)
        #expect(map.provider == "HERE")
        #expect(map.populatedTileCount() == 1)
    }

    @Test("reference bounding boxes cover all nine HERE traffic slots")
    func hereTrafficBoundsAreComplete() throws {
        for n1 in 1...9 {
            let bounds = try #require(Self.hereTrafficTileBounds[n1])
            // boundingBox.0 is the north-west corner, boundingBox.1 is the south-east corner.
            #expect(bounds.0.latitude > bounds.1.latitude)
            #expect(bounds.0.longitude < bounds.1.longitude)
        }
    }

    @Test("overwrites a HERE tile when the same slot arrives again")
    func hereTileOverwriteSameSlot() throws {
        var map = TrafficMap()
        let redTile = try #require(MapTestHelpers.pngData(color: MapTestHelpers.red, width: 8, height: 8))
        let blueTile = try #require(MapTestHelpers.pngData(color: MapTestHelpers.blue, width: 8, height: 8))

        map.processHereImageFile(hereImage: Self.hereTrafficTile(n1: 5, n2: 9, sequence: 1, data: redTile))
        let outcome = map.processHereImageFile(
            hereImage: Self.hereTrafficTile(n1: 5, n2: 9, sequence: 2, data: blueTile))

        // The HERE path currently overwrites on every ingest; it does not suppress stale tiles.
        #expect(outcome == .stored)
        #expect(map.populatedTileCount() == 1)

        let composite = try #require(map.composite)
        #expect(MapTestHelpers.pixelColor(in: composite, x: 12, yFromTop: 12) == MapTestHelpers.blue)
    }

    // MARK: - Tile stitching

    @Test("leaves composite nil when no tiles are available")
    func noTilesEmptyComposite() {
        let map = TrafficMap()
        #expect(map.composite == nil)
    }

    @Test("stitches a single tile onto a 3x3 background canvas")
    func stitchesSingleTile() throws {
        var map = TrafficMap()
        let tileData = try #require(MapTestHelpers.pngData(color: MapTestHelpers.red, width: 10, height: 10))

        // 1_1 is the upper-left tile.
        map.processImageFile(name: "TMT_prov_1_1_20260914_1514_0001.png", data: tileData)

        let composite = try #require(map.composite)
        #expect(composite.width == 30)
        #expect(composite.height == 30)

        // The upper-left cell matches the tile color; the rest is background.
        #expect(MapTestHelpers.pixelColor(in: composite, x: 4, yFromTop: 4) == MapTestHelpers.red)
        #expect(MapTestHelpers.pixelColor(in: composite, x: 25, yFromTop: 25) == MapTestHelpers.mapBackground)
        #expect(MapTestHelpers.pixelColor(in: composite, x: 25, yFromTop: 4) == MapTestHelpers.mapBackground)
        #expect(MapTestHelpers.pixelColor(in: composite, x: 4, yFromTop: 25) == MapTestHelpers.mapBackground)
    }

    @Test("places tiles in the correct 3x3 grid positions (row 1 = top, column 1 = left)")
    func stitchesTileGrid() throws {
        var map = TrafficMap()
        // colors[row - 1][column - 1]
        let colors: [[(CGFloat, CGFloat, CGFloat)]] = [
            [MapTestHelpers.red, MapTestHelpers.green, MapTestHelpers.blue],
            [MapTestHelpers.yellow, MapTestHelpers.cyan, MapTestHelpers.magenta],
            [MapTestHelpers.orange, MapTestHelpers.purple, MapTestHelpers.brown],
        ]

        for row in 1...3 {
            for column in 1...3 {
                let color = colors[row - 1][column - 1]
                let tileData = try #require(MapTestHelpers.pngData(color: color, width: 8, height: 8))
                let name = String(
                    format: "TMT_prov_%d_%d_20260914_1514_%04x.png", row, column, (row - 1) * 3 + (column - 1))
                map.processImageFile(name: name, data: tileData)
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
                    MapTestHelpers.pixelColor(in: composite, x: point.x, yFromTop: point.yFromTop)
                        == colors[row - 1][column - 1]
                )
            }
        }
    }

    // MARK: - Helpers

    private static func makeCoords(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> (Location, Location) {
        (Location(latitude: lat1, longitude: lon1), Location(latitude: lat2, longitude: lon2))
    }

    /// Reference per-tile bounding boxes for a 3×3 HERE traffic grid (`n2=9`).
    /// `boundingBox.0` is the north-west corner, `boundingBox.1` is the
    /// south-east corner.
    private static let hereTrafficTileBounds: [Int: (Location, Location)] = [
        1: makeCoords(lat1: 41.97378, lon1: -88.01971, lat2: 41.76926, lon2: -87.74505),
        2: makeCoords(lat1: 41.97378, lon1: -88.29437, lat2: 41.76926, lon2: -87.47039),
        3: makeCoords(lat1: 41.97378, lon1: -88.56903, lat2: 41.76926, lon2: -87.19573),
        4: makeCoords(lat1: 42.17765, lon1: -88.01971, lat2: 41.56408, lon2: -87.74505),
        5: makeCoords(lat1: 42.17765, lon1: -88.29437, lat2: 41.56408, lon2: -87.47039),
        6: makeCoords(lat1: 42.17765, lon1: -88.56903, lat2: 41.56408, lon2: -87.19573),
        7: makeCoords(lat1: 42.38086, lon1: -88.01971, lat2: 41.35825, lon2: -87.74505),
        8: makeCoords(lat1: 42.38086, lon1: -88.29437, lat2: 41.35825, lon2: -87.47039),
        9: makeCoords(lat1: 42.38086, lon1: -88.56903, lat2: 41.35825, lon2: -87.19573),
    ]

    private static func hereTrafficTile(n1: Int, n2: Int, sequence: Int, data: Data) -> TunerHereImage {
        guard let bounds = Self.hereTrafficTileBounds[n1] else {
            fatalError("No reference bounding box for HERE traffic tile n1=\(n1)")
        }
        let row = (n1 - 1) / 3
        let column = (n1 - 1) % 3
        return TunerHereImage(
            type: .traffic,
            name: "1793835363_trafficMap_\(row)_\(column)_u40h.png",
            sequence: sequence,
            n1: n1,
            n2: n2,
            time: MapTestHelpers.utcDate(year: 2026, month: 11, day: 4, hour: 23, minute: 31),
            boundingBox: bounds,
            data: data)
    }
}
