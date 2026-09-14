//
//  SampleFileProvider.swift
//  TunedTwo
//
//  Locates the uncompressed sample I/Q file bundled with the app.
//

import Foundation

final class SampleFileProvider {
    static let shared = SampleFileProvider()

    /// Returns a path to the bundled `sample.bin`.
    func sampleFilePath() throws -> String {
        let bundle = Bundle.main
        if let url = bundle.url(forResource: "sample", withExtension: "bin") {
            return url.path
        }

        // Fallback: development path next to the app bundle.
        let repoRoot = bundle.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        let devPath = repoRoot.appendingPathComponent("Resources/sample.bin")
        if FileManager.default.fileExists(atPath: devPath.path) {
            return devPath.path
        }

        throw SampleError.sampleNotFound
    }

    enum SampleError: LocalizedError {
        case sampleNotFound

        var errorDescription: String? {
            switch self {
            case .sampleNotFound: return "sample.bin could not be found in the bundle."
            }
        }
    }
}
