//
//  TrafficMap.swift
//  TunedTwo
//
//  Assembles traffic-map tiles (TMT files) delivered over LOT into a
//  single composite image.
//

import CoreGraphics
import Foundation
import ImageIO

/// Parsed parts of a TMT filename: `TMT_{provider}_{row}_{col}_{date}_{time}_{hex}.png`
///
/// Example: `TMT_035apk_2_1_20260914_1514_036f.png`
///
/// - The third component is the **row** within the 3×3 map (1 = top).
/// - The fourth component is the **column** within the map (1 = left).
///   So `3_1` is the *lower-left* tile — the naming in the filename is
///   row_column, not x_y, despite how it looks.
/// - Date and time are UTC, to minute resolution.
/// - The trailing hex value is a version/sequence number for the tile.
public struct TMTInfo: Equatable, Sendable {
    public let provider: String
    /// Row within the map grid, 1 = top row.
    public let row: Int
    /// Column within the map grid, 1 = left column.
    public let column: Int
    public let timestamp: Date
    public let hex: UInt16
}

/// One successfully ingested traffic tile: its parsed metadata plus the
/// decoded image.
public struct TrafficMapTile {
    public let info: TMTInfo
    public let image: CGImage
}

/// Outcome of offering one LOT file to `TrafficMap.processImageFile(name:data:)`
/// or `TrafficMap.processConfigFile(data:)`.
/// Used by the CLI for reporting and by tests for exact assertions.
public enum TrafficMapIngestOutcome: Equatable, Sendable {
    /// The tile was decoded and stored (a new slot, or an update whose
    /// timestamp was greater than or equal to the stored one).
    case stored
    /// The tile parsed and decoded, but the stored tile for that slot is
    /// strictly newer. Nothing changed.
    case ignoredStale(existingTimestamp: Date, incomingTimestamp: Date)
    /// The filename is not a TMT traffic-map file at all.
    case notTrafficMapFile
    /// The filename parsed, but the bytes are not a decodable image.
    case undecodableImage
    /// The filename parsed, but row/column lie outside the 3×3 grid.
    case outOfGrid
    /// A text config file was parsed and stored.
    case storedConfig
    /// A text config file was recognized but could not be parsed.
    case invalidConfig
}

/// The 3×3 traffic map.
///
/// Ingest rules:
///
/// - Only tiles from the current `provider` are kept; a tile from a *new*
///   provider resets the whole map. (Providers in the same market that
///   share a traffic feed reuse maps this way.)
/// - Within a slot, a tile is stored only if its timestamp is greater than
///   or equal to the stored tile's — equal timestamps are retransmissions
///   with new content and still win.
public struct TrafficMap {
    /// Default background color used when no TTN config file has been received.
    private static let defaultTTNBackgroundColor = RGB(red: 194, green: 187, blue: 96)
    /// Default background color used when the map source is HERE.
    private static let defaultHereBackgroundColor = RGB(red: 0xE0, green: 0xE0, blue: 0xE8)

    private var backgroundColor: RGB = defaultTTNBackgroundColor

    private var rowCount = 3
    private var columnCount = 3

    /// Provider ID of the map currently being assembled (from the most
    /// recently ingested tile or text config file).
    public private(set) var provider: String?

    /// Most recently ingested TTN traffic map config file, if TTN is the source.
    public private(set) var config: TTNSTMTrafficConfig?

    /// Flat row-major storage: `tiles[(row - 1) * columnCount + (column - 1)]`.
    public private(set) var tiles: [TrafficMapTile?]

    public init() {
        tiles = Array(repeating: nil, count: rowCount * columnCount)
    }

    // MARK: - Filename parsing

    /// Parse a TMT filename into parts. Strict: returns nil for anything
    /// that is not a plausible TMT name (used to filter LOT traffic).
    ///
    /// Does not validate grid bounds — `1...rowCount` / `1...columnCount`
    /// is checked at ingest time instead, so a malformed-but-parseable name
    /// can be reported rather than silently dropped.
    public static func parseLOTName(_ lotName: String) -> TMTInfo? {
        guard lotName.hasSuffix(".png") else { return nil }

        let baseName = String(lotName.dropLast(4))
        let components = baseName.components(separatedBy: "_")
        guard components.count == 7 else { return nil }

        guard components[0] == "TMT" else { return nil }

        let provider = components[1]
        guard !provider.isEmpty else { return nil }

        guard let row = Int(components[2]) else { return nil }
        guard let column = Int(components[3]) else { return nil }

        let dateString = components[4]
        let timeString = components[5]
        guard dateString.count == 8, timeString.count == 4 else { return nil }

        var dateComponents = DateComponents(calendar: Calendar.utc)

        guard let year = Int(dateString.prefix(4)),
            let month = Int(dateString.dropFirst(4).prefix(2)),
            let day = Int(dateString.dropFirst(6).prefix(2)),
            let hour = Int(timeString.prefix(2)),
            let minute = Int(timeString.dropFirst(2).prefix(2))
        else {
            return nil
        }

        dateComponents.year = year
        dateComponents.month = month
        dateComponents.day = day
        dateComponents.hour = hour
        dateComponents.minute = minute

        guard let timestamp = dateComponents.date else { return nil }

        guard let hex = UInt16(components[6], radix: 16) else { return nil }

        return TMTInfo(provider: provider, row: row, column: column, timestamp: timestamp, hex: hex)
    }

    // MARK: - Filename parsing

    // MARK: - Ingest

    /// Parse and store a text config file.
    @discardableResult
    public mutating func processConfigFile(data: Data) -> TrafficMapIngestOutcome {
        guard let text = String(bytes: data, encoding: .utf8),
            let newConfig = try? TTNSTMTrafficConfigParser.parse(text)
        else {
            return .invalidConfig
        }

        let newProvider = newConfig.trafficMapID
        if let currentProvider = self.provider, currentProvider != newProvider {
            tiles = Array(repeating: nil, count: rowCount * columnCount)
        }
        self.provider = newProvider
        self.config = newConfig
        self.backgroundColor = newConfig.backgroundRGBColor
        // TODO: update rowCount/columnCount if changed, and recreate tiles array if needed
        return .storedConfig
    }

    /// Parse and store a single tile image.
    @discardableResult
    public mutating func processImageFile(name: String, data: Data) -> TrafficMapIngestOutcome {
        guard let info = Self.parseLOTName(name) else { return .notTrafficMapFile }
        guard (1...rowCount).contains(info.row),
            (1...columnCount).contains(info.column)
        else { return .outOfGrid }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return .undecodableImage }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return .undecodableImage }

        if let currentProvider = provider, currentProvider != info.provider {
            tiles = Array(repeating: nil, count: rowCount * columnCount)
        }
        provider = info.provider

        let index = (info.row - 1) * columnCount + (info.column - 1)
        if let existing = tiles[index], existing.info.timestamp > info.timestamp {
            return .ignoredStale(
                existingTimestamp: existing.info.timestamp,
                incomingTimestamp: info.timestamp)
        }

        tiles[index] = TrafficMapTile(info: info, image: image)
        return .stored
    }

    /// Parse and store a HERE traffic map image.
    @discardableResult
    public mutating func processHereImageFile(hereImage: HereImage) -> TrafficMapIngestOutcome {
        guard case .traffic = hereImage.type else { return .notTrafficMapFile }
        guard let source = CGImageSourceCreateWithData(hereImage.data as CFData, nil) else { return .undecodableImage }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return .undecodableImage }

        let size = Int(Double(hereImage.n2).squareRoot())

        // TODO: right now, we're synthesizing some of this to match LOT format.
        // TODO: use sqrt(n2) to determine rows/columns max
        let row = (hereImage.n1 - 1) / size
        let column = (hereImage.n1 - 1) % size
        let info = TMTInfo(
            provider: "HERE", row: row, column: column, timestamp: hereImage.time ?? Date(),
            hex: UInt16(hereImage.sequence))

        if let currentProvider = provider, currentProvider != info.provider {
            config = nil
            rowCount = size
            columnCount = size
            tiles = Array(repeating: nil, count: rowCount * columnCount)
        }
        provider = info.provider

        tiles[hereImage.n1 - 1] = TrafficMapTile(info: info, image: image)
        backgroundColor = Self.defaultHereBackgroundColor
        return .stored
    }

    // MARK: - Timestamps

    /// The earliest timestamp among the collected tiles, or nil if no
    /// tiles have been ingested.
    public func minimumTimestamp() -> Date? {
        tiles.compactMap { $0?.info.timestamp }.min()
    }

    /// The latest timestamp among the collected tiles, or nil if no
    /// tiles have been ingested.
    public func maximumTimestamp() -> Date? {
        tiles.compactMap { $0?.info.timestamp }.max()
    }

    // MARK: - Composite

    /// Stitch the available tiles into a single image: a 3×3 grid at the
    /// first tile's resolution, with missing slots filled using the
    /// map background color (194, 187, 96).
    public var composite: CGImage? {
        guard let sample = tiles.compactMap({ $0 }).first else { return nil }

        let cellWidth = CGFloat(sample.image.width)
        let cellHeight = CGFloat(sample.image.height)
        let width = Int(cellWidth * CGFloat(columnCount))
        let height = Int(cellHeight * CGFloat(rowCount))

        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else {
            return nil
        }

        // Background fill for missing tiles.
        context.setFillColor(
            red: CGFloat(backgroundColor.red) / 255.0,
            green: CGFloat(backgroundColor.green) / 255.0,
            blue: CGFloat(backgroundColor.blue) / 255.0,
            alpha: 1.0)
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))

        // CGBitmapContext user space has its origin at the lower-left, so
        // map row 1 (the top row) to the highest y band. Tiles are scaled to
        // the cell size, so mismatched tile dimensions still tile cleanly.
        for row in 0..<rowCount {
            for column in 0..<columnCount {
                guard let tile = tiles[row * columnCount + column] else { continue }
                let rect = CGRect(
                    x: CGFloat(column) * cellWidth,
                    y: CGFloat(rowCount - 1 - row) * cellHeight,
                    width: cellWidth,
                    height: cellHeight)
                context.draw(tile.image, in: rect)
            }
        }

        return context.makeImage()
    }
}
