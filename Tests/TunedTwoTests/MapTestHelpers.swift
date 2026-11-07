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

enum MapTestHelpers {
    static let red = (CGFloat(1), CGFloat(0), CGFloat(0))
    static let green = (CGFloat(0), CGFloat(1), CGFloat(0))
    static let blue = (CGFloat(0), CGFloat(0), CGFloat(1))
    static let cyan = (CGFloat(0), CGFloat(1), CGFloat(1))
    static let yellow = (CGFloat(1), CGFloat(1), CGFloat(0))
    static let magenta = (CGFloat(1), CGFloat(0), CGFloat(1))
    static let orange = (CGFloat(1), CGFloat(0.5), CGFloat(0))
    static let purple = (CGFloat(0.5), CGFloat(0), CGFloat(0.5))
    static let brown = (CGFloat(0.6), CGFloat(0.4), CGFloat(0.2))

    /// Default TTN traffic-map background color used in composites.
    static let mapBackground = (CGFloat(194) / 255, CGFloat(187) / 255, CGFloat(96) / 255)

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
    static func pngData(color: (CGFloat, CGFloat, CGFloat), width: Int, height: Int) -> Data? {
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

    /// Read a pixel from a CGImage. `yFromTop` measures from the top of the image.
    static func pixelColor(in image: CGImage, x: Int, yFromTop: Int) -> (CGFloat, CGFloat, CGFloat)? {
        guard let context = Self.makeRGBContext(width: image.width, height: image.height) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let data = context.data else { return nil }
        let buffer = UnsafeRawBufferPointer(start: data, count: context.height * context.bytesPerRow)
        let offset = yFromTop * context.bytesPerRow + x * 4
        guard offset >= 0, offset + 2 < buffer.count else { return nil }
        return (CGFloat(buffer[offset]) / 255, CGFloat(buffer[offset + 1]) / 255, CGFloat(buffer[offset + 2]) / 255)
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

/// Exact RGB tuple equality for test colors (all colors here are opaque and
/// pass through the same sRGB pipeline, so exact comparison is meaningful).
func == (lhs: (CGFloat, CGFloat, CGFloat)?, rhs: (CGFloat, CGFloat, CGFloat)) -> Bool {
    guard let lhs else { return false }
    let tolerance: CGFloat = 0.02
    return abs(lhs.0 - rhs.0) < tolerance && abs(lhs.1 - rhs.1) < tolerance && abs(lhs.2 - rhs.2) < tolerance
}
