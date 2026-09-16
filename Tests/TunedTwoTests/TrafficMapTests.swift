//
//  TrafficMapTests.swift
//  TunedTwoTests
//

import Foundation
import AppKit
import Testing
@testable import TunedTwo

@MainActor
@Suite("TrafficMap parsing")
struct TrafficMapTests {

    @Test("parses a valid TMT filename")
    func parseValidName() throws {
        let info = try #require(TrafficMap.parseLOTName("TMT_035apk_2_1_20260914_1514_036f.png"))

        #expect(info.provider == "035apk")
        #expect(info.X == 2)
        #expect(info.Y == 1)
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

    @Test("returns nil when X or Y are not integers")
    func rejectsNonIntegerCoordinates() {
        #expect(TrafficMap.parseLOTName("TMT_035apk_a_1_20260914_1514_036f.png") == nil)
        #expect(TrafficMap.parseLOTName("TMT_035apk_2_b_20260914_1514_036f.png") == nil)
    }

    @Test("returns nil for malformed hex")
    func rejectsInvalidHex() {
        #expect(TrafficMap.parseLOTName("TMT_035apk_2_1_20260914_1514_gggg.png") == nil)
        #expect(TrafficMap.parseLOTName("TMT_035apk_2_1_20260914_1514_12345.png") == nil)
    }

    // MARK: - Tile stitching

    @Test("leaves composite nil when no tiles are available")
    func noTilesEmptyComposite() {
        let map = TrafficMap()
        map.stitchTiles()
        #expect(map.composite == nil)
    }

    @Test("stitches a single tile onto a 3x3 background canvas")
    func stitchesSingleTile() throws {
        let map = TrafficMap()
        let tileColor = NSColor.red
        let tileData = try #require(Self.pngData(color: tileColor, size: NSSize(width: 10, height: 10)))

        map.processLOTFile(name: "TMT_prov_1_1_20260914_1514_0001.png", data: Array(tileData))

        let compositeImage = try #require(map.composite)
        #expect(compositeImage.size == NSSize(width: 30, height: 30))

        // The top-left cell should match the tile color.
        let sampledColor = try #require(Self.pixelColor(in: compositeImage, at: NSPoint(x: 4, y: 4)))
        #expect(Self.areColorsEqual(sampledColor, tileColor))
    }

    @Test("places tiles in the correct 3x3 grid positions")
    func stitchesTileGrid() throws {
        let map = TrafficMap()
        let colors: [NSColor] = [
            .red, .green, .blue,
            .yellow, .cyan, .magenta,
            .orange, .purple, .brown
        ]

        for (offset, color) in colors.enumerated() {
            let x = (offset / 3) + 1
            let y = (offset % 3) + 1
            let tileData = try #require(Self.pngData(color: color, size: NSSize(width: 8, height: 8)))
            let name = String(format: "TMT_prov_%d_%d_20260914_1514_%04x.png", x, y, offset)
            map.processLOTFile(name: name, data: Array(tileData))
        }

        let compositeImage = try #require(map.composite)
        #expect(compositeImage.size == NSSize(width: 24, height: 24))

        // Sample the center of each grid cell.
        for (offset, color) in colors.enumerated() {
            let point = NSPoint(x: CGFloat(offset / 3) * 8 + 4,
                                y: CGFloat(2 - (offset % 3)) * 8 + 4)
            let sampledColor = try #require(Self.pixelColor(in: compositeImage, at: point))
            #expect(Self.areColorsEqual(sampledColor, color))
        }
    }

    // MARK: - Helpers

    private static func utcDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return components.date!
    }

    private static func pngData(color: NSColor, size: NSSize) -> Data? {
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }

    private static func pixelColor(in image: NSImage, at point: NSPoint) -> NSColor? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.colorAt(x: Int(point.x), y: Int(point.y))
    }

    private static func areColorsEqual(_ lhs: NSColor, _ rhs: NSColor) -> Bool {
        guard let lhsComponents = lhs.cgColor.components,
              let rhsComponents = rhs.cgColor.components,
              lhsComponents.count >= 3,
              rhsComponents.count >= 3 else {
            return false
        }
        let tolerance: CGFloat = 0.02
        return abs(lhsComponents[0] - rhsComponents[0]) < tolerance &&
               abs(lhsComponents[1] - rhsComponents[1]) < tolerance &&
               abs(lhsComponents[2] - rhsComponents[2]) < tolerance
    }
}
