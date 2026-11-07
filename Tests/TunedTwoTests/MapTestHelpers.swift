//
//  MapTestHelpers.swift
//  TunedTwoTests
//
//  Shared test utilities for traffic-map and weather-map tests.
//

import CoreGraphics
import Foundation
import ImageIO

@testable import TunedTwoCore

/// RGB color used by map-test helpers. Values are in the unit sRGB range.
///
/// Equality uses a small tolerance because CoreGraphics quantizes colors to
/// 8-bit channels, so values like `0.5` round-trip as `128 / 255`.
struct RGBColor: Equatable, Sendable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat

    static func == (lhs: RGBColor, rhs: RGBColor) -> Bool {
        let tolerance: CGFloat = 0.02
        return abs(lhs.red - rhs.red) < tolerance
            && abs(lhs.green - rhs.green) < tolerance
            && abs(lhs.blue - rhs.blue) < tolerance
    }
}

extension RGBColor {
    init(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

enum MapTestHelpers {
    static let red = RGBColor(1, 0, 0)
    static let green = RGBColor(0, 1, 0)
    static let blue = RGBColor(0, 0, 1)
    static let cyan = RGBColor(0, 1, 1)
    static let yellow = RGBColor(1, 1, 0)
    static let magenta = RGBColor(1, 0, 1)
    static let orange = RGBColor(1, 0.5, 0)
    static let purple = RGBColor(0.5, 0, 0.5)
    static let brown = RGBColor(0.6, 0.4, 0.2)

    /// Default TTN traffic-map background color used in composites.
    static let mapBackground = RGBColor(
        CGFloat(194) / 255, CGFloat(187) / 255, CGFloat(96) / 255)

    static func utcDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return Calendar.utc.date(from: components)!
    }

    /// Render a solid color into a PNG, using only CoreGraphics.
    static func pngData(color: RGBColor, width: Int, height: Int) -> Data? {
        guard let context = Self.makeRGBContext(width: width, height: height) else { return nil }
        context.setFillColor(red: color.red, green: color.green, blue: color.blue, alpha: 1)
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

    /// Read a pixel from a CGImage. `yFromTop` measures from the top of the image.
    static func pixelColor(in image: CGImage, x: Int, yFromTop: Int) -> RGBColor? {
        guard let context = Self.makeRGBContext(width: image.width, height: image.height) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let data = context.data else { return nil }
        let buffer = UnsafeRawBufferPointer(start: data, count: context.height * context.bytesPerRow)
        let offset = yFromTop * context.bytesPerRow + x * 4
        guard offset >= 0, offset + 2 < buffer.count else { return nil }
        return RGBColor(
            red: CGFloat(buffer[offset]) / 255,
            green: CGFloat(buffer[offset + 1]) / 255,
            blue: CGFloat(buffer[offset + 2]) / 255)
    }

    static func makeRGBContext(width: Int, height: Int) -> CGContext? {
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
