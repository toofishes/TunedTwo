//
//  TrafficMapCommand.swift
//  tunedtwo-cli
//
//  `tunedtwo-cli traffic-map <directory>`: scans a directory for
//  traffic-map tiles (TMT_*.png, optionally prefixed with a numeric
//  sequence number as exported from a capture), ingests them through
//  `TrafficMap`, and writes the stitched composite as a PNG — to stdout by
//  default, or a file with --output. All reporting goes to stderr so
//  stdout stays pipeable.
//

import ArgumentParser
import CoreGraphics
import Foundation
import TunedTwoCore

struct TrafficMapCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "traffic-map",
        abstract: "Stitch traffic-map tiles (TMT PNGs) into one composite image."
    )

    @Argument(help: "Directory containing TMT_*.png traffic-map tiles.")
    var directory: String

    @Option(name: [.short, .long], help: "Write the composite PNG to FILE ('-' for stdout).")
    var output: String = "-"

    @Option(help: "Only ingest tiles whose provider ID matches (e.g. 035apk).")
    var provider: String?

    @Flag(name: [.short, .long], help: "Report every file considered: stored, stale, skipped, or rejected.")
    var verbose = false

    func validate() throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            throw ValidationError("'\(directory)' is not a directory")
        }
    }

    mutating func run() throws {
        let outputDestination = OutputDestination(path: output)
        let directoryURL = URL(fileURLWithPath: directory, isDirectory: true)
        let files = try listFiles(in: directoryURL)

        var map = TrafficMap()

        // Ingest any TMI text config files first so provider and background
        // color are available before tiles are stitched.
        var ingester = Ingester(verbose: verbose)
        try ingestConfigFiles(files, into: &map, ingester: &ingester, verbose: verbose)

        let candidates = collectCandidates(files, providerFilter: provider, verbose: verbose)

        guard !candidates.isEmpty else {
            throw RuntimeError("no TMT traffic-map files found in '\(directoryURL.path)'")
        }

        // Ingest oldest-first so the newer-wins rule applies deterministically
        // regardless of directory order or filename prefixes.
        let ordered = candidates.sorted { lhs, rhs in
            if lhs.info.timestamp != rhs.info.timestamp {
                return lhs.info.timestamp < rhs.info.timestamp
            }
            return lhs.info.hex < rhs.info.hex
        }

        for candidate in ordered {
            try ingester.ingest(&map, candidate: candidate)
        }

        let stats = ingester.stats
        if stats.stored == 0 {
            throw RuntimeError(
                "no tiles could be stored (stored: 0, stale: \(stats.stale), "
                    + "undecodable: \(stats.undecodable), out of grid: \(stats.outOfGrid))")
        }

        guard let composite = map.composite else {
            throw RuntimeError("tiles were stored but the composite could not be rendered")
        }

        let png = try PNGEncoder.encode(composite)
        try PNGEncoder.write(png, to: outputDestination)

        // One-line summary on stderr: the smoke-test heartbeat.
        let target = outputDestination.description
        let provider = map.provider ?? "?"
        fputs(
            "traffic-map: \(stats.stored) tiles stored "
                + "(\(stats.stale) stale, \(stats.undecodable) undecodable, \(stats.outOfGrid) out of grid, "
                + "\(stats.skipped) skipped), provider=\(provider), "
                + "composite \(composite.width)x\(composite.height) -> \(target)\n", stderr)
    }

    // MARK: - Directory scan

    private struct Candidate {
        let url: URL
        let fileName: String
        /// Filename with any leading numeric sequence prefix stripped — the
        /// form the LOT stream delivers and `TrafficMap.parseLOTName` expects.
        let lotName: String
        let info: TMTInfo
    }

    /// Enumerate regular files in the directory.
    private func listFiles(in directory: URL) throws -> [URL] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil)
        return contents.filter { url in
            var isDirectory = ObjCBool(false)
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            return !isDirectory.boolValue
        }
    }

    /// Ingest any TMI text config files found in the directory.
    private func ingestConfigFiles(
        _ files: [URL],
        into map: inout TrafficMap,
        ingester: inout Ingester,
        verbose: Bool
    ) throws {
        for url in files {
            let fileName = url.lastPathComponent
            let lotName = Self.stripNumericPrefix(fileName)
            guard lotName.hasSuffix(".txt") else { continue }
            let data = try Data(contentsOf: url)
            let outcome = map.processConfigFile(data: [UInt8](data))
            ingester.recordConfig(outcome: outcome, fileName: fileName, verbose: verbose)
        }
    }

    /// Parse filenames and apply the provider filter. A leading numeric
    /// sequence prefix (as in `304_TMT_...`) is stripped before parsing.
    private func collectCandidates(
        _ files: [URL],
        providerFilter: String?,
        verbose: Bool
    ) -> [Candidate] {
        var candidates: [Candidate] = []
        var skipped = 0
        var providers: [String: Int] = [:]

        for url in files {
            let fileName = url.lastPathComponent
            let lotName = Self.stripNumericPrefix(fileName)

            // Config files are handled separately before tile collection.
            if lotName.hasSuffix(".txt") {
                continue
            }

            guard let info = TrafficMap.parseLOTName(lotName) else {
                skipped += 1
                if verbose {
                    fputs("  skipped: \(fileName) (not a TMT traffic-map file)\n", stderr)
                }
                continue
            }
            providers[info.provider, default: 0] += 1

            if let providerFilter, info.provider != providerFilter {
                skipped += 1
                if verbose {
                    fputs("  skipped: \(fileName) (provider \(info.provider) != \(providerFilter))\n", stderr)
                }
                continue
            }

            candidates.append(Candidate(url: url, fileName: fileName, lotName: lotName, info: info))
        }

        // Without --provider, a mixed directory silently produces the last
        // provider's map (a provider change resets the map). Make that loud.
        if providerFilter == nil, providers.count > 1, !candidates.isEmpty {
            let summary = providers.sorted { $0.value > $1.value }
                .map { "\($0.key) (\($0.value) files)" }
                .joined(separator: ", ")
            fputs(
                "traffic-map: warning: multiple providers found: \(summary). "
                    + "The last provider processed wins; use --provider <id> to pin one.\n", stderr)
        }

        return candidates
    }

    private static func stripNumericPrefix(_ fileName: String) -> String {
        guard let underscore = fileName.firstIndex(of: "_"),
            underscore > fileName.startIndex
        else { return fileName }
        let prefix = fileName[fileName.startIndex..<underscore]
        return prefix.allSatisfy(\.isNumber) ? String(fileName[fileName.index(after: underscore)...]) : fileName
    }

    // MARK: - Ingest with reporting

    private struct Stats {
        var stored = 0
        var stale = 0
        var undecodable = 0
        var outOfGrid = 0
        var skipped = 0
    }

    private struct Ingester {
        let verbose: Bool
        var stats = Stats()
        private let timestampFormatter: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            return formatter
        }()

        mutating func ingest(_ map: inout TrafficMap, candidate: Candidate) throws {
            let data = try Data(contentsOf: candidate.url)
            let outcome = map.processImageFile(name: candidate.lotName, data: [UInt8](data))

            switch outcome {
            case .stored:
                stats.stored += 1
                if verbose {
                    report(candidate, "stored at row \(candidate.info.row), column \(candidate.info.column)")
                }
            case .ignoredStale(let existing, let incoming):
                stats.stale += 1
                if verbose {
                    report(
                        candidate,
                        "ignored stale (existing \(timestampFormatter.string(from: existing)) "
                            + "> incoming \(timestampFormatter.string(from: incoming)))")
                }
            case .undecodableImage:
                stats.undecodable += 1
                reportAlways(candidate, "image bytes could not be decoded")
            case .outOfGrid:
                stats.outOfGrid += 1
                reportAlways(
                    candidate,
                    "row/column outside the 3x3 grid "
                        + "(row \(candidate.info.row), column \(candidate.info.column))")
            case .notTrafficMapFile, .storedConfig, .invalidConfig:
                // Already filtered during collection; counted as skipped.
                stats.skipped += 1
            }
        }

        mutating func recordConfig(outcome: TrafficMapIngestOutcome, fileName: String, verbose: Bool) {
            switch outcome {
            case .storedConfig:
                if verbose {
                    fputs("  \(fileName): config stored\n", stderr)
                }
            case .invalidConfig:
                stats.undecodable += 1
                fputs("traffic-map: warning: \(fileName): config could not be parsed\n", stderr)
            default:
                break
            }
        }

        private func report(_ candidate: Candidate, _ detail: String) {
            fputs("  \(candidate.fileName): \(detail)\n", stderr)
        }

        /// Outcomes that indicate a real problem with the data are reported
        /// even without --verbose.
        private func reportAlways(_ candidate: Candidate, _ detail: String) {
            fputs("traffic-map: warning: \(candidate.fileName): \(detail)\n", stderr)
        }
    }
}
