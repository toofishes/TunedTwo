//
//  TrafficMap.swift
//  TunedTwo
//

import Foundation
import AppKit

struct TMTInfo {
    let provider: String
    let X: Int
    let Y: Int
    let timestamp: Date
    let hex: UInt16
}

@MainActor
class TrafficMap {
    var tiles = [NSImage?](repeating: nil, count: 9)

    var composite: NSImage?

    /// Parse TMT filename into parts: TMT_{provider}_{X}_{Y}_{date}_{time}_{hex}.png
    /// Example Value: TMT_035apk_2_1_20260914_1514_036f.png
    nonisolated static func parseLOTName(_ lotName: String) -> TMTInfo? {
        guard lotName.hasSuffix(".png") else { return nil }

        let baseName = String(lotName.dropLast(4))
        let components = baseName.components(separatedBy: "_")
        guard components.count == 7 else { return nil }

        guard components[0] == "TMT" else { return nil }

        let provider = components[1]
        guard !provider.isEmpty else { return nil }

        guard let x = Int(components[2]) else { return nil }
        guard let y = Int(components[3]) else { return nil }

        let dateString = components[4]
        let timeString = components[5]
        guard dateString.count == 8, timeString.count == 4 else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        var dateComponents = DateComponents()
        dateComponents.calendar = calendar

        guard let year = Int(dateString.prefix(4)),
              let month = Int(dateString.dropFirst(4).prefix(2)),
              let day = Int(dateString.dropFirst(6).prefix(2)),
              let hour = Int(timeString.prefix(2)),
              let minute = Int(timeString.dropFirst(2).prefix(2)) else {
            return nil
        }

        dateComponents.year = year
        dateComponents.month = month
        dateComponents.day = day
        dateComponents.hour = hour
        dateComponents.minute = minute

        guard let timestamp = dateComponents.date else { return nil }

        guard let hex = UInt16(components[6], radix: 16) else { return nil }

        return TMTInfo(provider: provider, X: x, Y: y, timestamp: timestamp, hex: hex)
    }

    func processLOTFile(name: String, data: [UInt8]) {
        guard let info = TrafficMap.parseLOTName(name),
              let image = NSImage(data: Data(data)) else { return }
        let offset = (info.X - 1) + ((info.Y - 1) * 3)
        tiles[offset] = image
        stitchTiles()
    }

    func stitchTiles() {
        // find the first available image. if we find one, grab the dimensions.
        // build a composite image that is a 3x3 grid of all the images together.
        // we may not have all 9 images right away - if any are missing, fill the
        // composite image first with BackgroundRGBColor="(194,187,96)" and then
        // overlay what we have on top. Top left is image 1,1, stored at offset 0.

        guard let sampleImage = tiles.compactMap({ $0 }).first else { return }

        let tileSize = sampleImage.size
        let compositeSize = NSSize(width: tileSize.width * 3, height: tileSize.height * 3)

        let backgroundColor = NSColor(srgbRed: 194.0 / 255.0,
                                      green: 187.0 / 255.0,
                                      blue: 96.0 / 255.0,
                                      alpha: 1.0)

        composite = NSImage(size: compositeSize, flipped: false) { bounds in
            // Fill the canvas with the background color.
            backgroundColor.setFill()
            bounds.fill()

            // Overlay each available tile in its 3x3 grid position.
            for (offset, image) in self.tiles.enumerated() {
                guard let image else { continue }
                let at = CGPoint(
                    x: CGFloat(offset / 3) * tileSize.width,
                    y: CGFloat(2 - (offset % 3)) * tileSize.height
                )
                //image.draw(in: drawRect)
                image.draw(at: at, from: .zero, operation: .sourceOver, fraction: 1.0)
            }

            return true
        }
    }
}
