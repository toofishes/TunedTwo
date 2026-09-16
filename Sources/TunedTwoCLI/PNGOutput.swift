//
//  PNGOutput.swift
//  tunedtwo-cli
//
//  Composite-image encoding (ImageIO) and output routing (stdout or file).
//

import Foundation
import CoreGraphics
import ImageIO

/// Where a produced file goes: stdout (the default, for piping) or a path.
enum OutputDestination: CustomStringConvertible {
    case stdout
    case file(URL)

    /// "-" means stdout. Expands a leading ~.
    init(path: String) {
        if path == "-" {
            self = .stdout
        } else {
            let expanded = NSString(string: path).expandingTildeInPath
            self = .file(URL(fileURLWithPath: expanded))
        }
    }

    var description: String {
        switch self {
        case .stdout: return "stdout"
        case .file(let url): return url.path
        }
    }
}

enum PNGEncoder {
    enum EncodeError: Error, CustomStringConvertible {
        case destinationCreationFailed
        case finalizeFailed

        var description: String {
            switch self {
            case .destinationCreationFailed: return "could not create a PNG encoder"
            case .finalizeFailed: return "PNG encoding failed"
            }
        }
    }

    /// Encode a CGImage to PNG data.
    static func encode(_ image: CGImage) throws -> Data {
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutableData, "public.png" as CFString, 1, nil) else {
            throw EncodeError.destinationCreationFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw EncodeError.finalizeFailed
        }
        return mutableData as Data
    }

    static func write(_ data: Data, to destination: OutputDestination) throws {
        switch destination {
        case .stdout:
            try FileHandle.standardOutput.write(contentsOf: data)
        case .file(let url):
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                throw RuntimeError("could not write '\(url.path)': \(error.localizedDescription)")
            }
        }
    }
}
