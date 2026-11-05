//
//  TrafficMapCommand.swift
//  tunedtwo-cli
//
//  `tunedtwo-cli traffic-map <directory>`: scans a directory for
//  traffic-map tiles — either TMT_*.png LOT files (optionally prefixed
//  with a numeric sequence number) or dumped HERE traffic tiles
//  (`*_trafficMap_*.png`) — ingests them through `TrafficMap`, and writes
//  the stitched composite as a PNG. Output goes to stdout by default, or
//  a file with --output. All reporting goes to stderr so stdout stays
//  pipeable.
//

import ArgumentParser
import CoreGraphics
import Foundation
import TunedTwoCore

struct TrafficMapCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "traffic-map",
        abstract: "Stitch traffic-map tiles (TMT or HERE PNGs) into one composite image."
    )

    @Argument(help: "Directory containing TMT_*.png or *_trafficMap_*.png tiles.")
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

        // Ingest TMI text config files first so provider and background
        // color are available before tiles are stitched.
        var ingester = Ingester(verbose: verbose)
        try ingestConfigFiles(files, into: &map, ingester: &ingester, verbose: verbose)

        let (tmtCandidates, hereCandidates) = collectCandidates(
            files, providerFilter: provider, verbose: verbose)

        guard !tmtCandidates.isEmpty || !hereCandidates.isEmpty else {
            throw RuntimeError("no traffic-map files found in '\(directoryURL.path)'")
        }

        // Ingest oldest-first so the newer-wins rule applies deterministically
        // regardless of directory order or filename prefixes.
        let orderedTMT = tmtCandidates.sorted { lhs, rhs in
            if lhs.info.timestamp != rhs.info.timestamp {
                return lhs.info.timestamp < rhs.info.timestamp
            }
            return lhs.info.hex < rhs.info.hex
        }
        let orderedHERE = hereCandidates.sorted { lhs, rhs in
            if let lhsTime = lhs.info.time, let rhsTime = rhs.info.time {
                if lhsTime != rhsTime { return lhsTime < rhsTime }
            }
            return lhs.info.n1 < rhs.info.n1
        }

        for candidate in orderedTMT {
            try ingester.ingest(&map, candidate: candidate)
        }
        for candidate in orderedHERE {
            try ingester.ingestHere(&map, candidate: candidate)
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

    private struct TMTCandidate {
        let url: URL
        let fileName: String
        /// Filename with any leading numeric sequence prefix stripped — the
        /// form the LOT stream delivers and `TrafficMap.parseLOTName` expects.
        let lotName: String
        let info: TMTInfo
    }

    private struct HereCandidate {
        let url: URL
        let fileName: String
        let info: HereTrafficFileInfo
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

    /// Ingest TMI text config files found in the directory.
    ///
    /// Only `TMI_*.txt` files are treated as traffic-map configs; other
    /// `.txt` files (such as capture logs) are ignored.
    private func ingestConfigFiles(
        _ files: [URL],
        into map: inout TrafficMap,
        ingester: inout Ingester,
        verbose: Bool
    ) throws {
        for url in files {
            let fileName = url.lastPathComponent
            let lotName = Self.stripNumericPrefix(fileName)
            guard lotName.hasSuffix(".txt"),
                lotName.hasPrefix("TMI_")
            else { continue }
            let data = try Data(contentsOf: url)
            let outcome = map.processConfigFile(data: data)
            ingester.recordConfig(outcome: outcome, fileName: fileName, verbose: verbose)
        }
    }

    /// Parse filenames and apply the provider filter. A leading numeric
    /// sequence prefix (as in `304_TMT_...` or `1793835363_trafficMap_...`)
    /// is stripped before parsing TMT files; HERE filenames are parsed with
    /// their leading timestamp intact because it carries the tile time.
    private func collectCandidates(
        _ files: [URL],
        providerFilter: String?,
        verbose: Bool
    ) -> (tmt: [TMTCandidate], here: [HereCandidate]) {
        var tmtCandidates: [TMTCandidate] = []
        var hereCandidates: [HereCandidate] = []
        var skipped = 0
        var tmtProviders: [String: Int] = [:]

        for url in files {
            let fileName = url.lastPathComponent

            // Config files are handled separately before tile collection.
            if fileName.hasSuffix(".txt") {
                continue
            }

            // Try TMT first; strip a leading LOT sequence number if present.
            let lotName = Self.stripNumericPrefix(fileName)
            if let info = TrafficMap.parseLOTName(lotName) {
                tmtProviders[info.provider, default: 0] += 1

                if let providerFilter, info.provider != providerFilter {
                    skipped += 1
                    if verbose {
                        fputs("  skipped: \(fileName) (provider \(info.provider) != \(providerFilter))\n", stderr)
                    }
                    continue
                }

                tmtCandidates.append(TMTCandidate(url: url, fileName: fileName, lotName: lotName, info: info))
                continue
            }

            // Try HERE traffic tiles; keep the leading timestamp for the tile time.
            if let info = TrafficMap.parseHereTrafficName(fileName) {
                // HERE tiles have a single synthetic provider; --provider has no effect.
                if providerFilter != nil {
                    skipped += 1
                    if verbose {
                        fputs("  skipped: \(fileName) (HERE tile cannot be filtered by provider)\n", stderr)
                    }
                    continue
                }

                hereCandidates.append(HereCandidate(url: url, fileName: fileName, info: info))
                continue
            }

            skipped += 1
            if verbose {
                fputs("  skipped: \(fileName) (not a traffic-map file)\n", stderr)
            }
        }

        // Without --provider, a mixed TMT directory silently produces the last
        // provider's map (a provider change resets the map). Make that loud.
        if providerFilter == nil, tmtProviders.count > 1, !tmtCandidates.isEmpty {
            let summary = tmtProviders.sorted { $0.value > $1.value }
                .map { "\($0.key) (\($0.value) files)" }
                .joined(separator: ", ")
            fputs(
                "traffic-map: warning: multiple providers found: \(summary). "
                    + "The last provider processed wins; use --provider <id> to pin one.\n", stderr)
        }

        return (tmtCandidates, hereCandidates)
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

        mutating func ingest(_ map: inout TrafficMap, candidate: TMTCandidate) throws {
            let data = try Data(contentsOf: candidate.url)
            let outcome = map.processImageFile(name: candidate.lotName, data: data)
            record(outcome: outcome, fileName: candidate.fileName)

            switch outcome {
            case .stored:
                if verbose {
                    report(
                        fileName: candidate.fileName,
                        "stored at row \(candidate.info.row), column \(candidate.info.column)")
                }
            case .ignoredStale(let existing, let incoming):
                if verbose {
                    report(
                        fileName: candidate.fileName,
                        "ignored stale (existing \(timestampFormatter.string(from: existing)) "
                            + "> incoming \(timestampFormatter.string(from: incoming)))")
                }
            case .undecodableImage:
                reportAlways(fileName: candidate.fileName, "image bytes could not be decoded")
            case .outOfGrid:
                reportAlways(
                    fileName: candidate.fileName,
                    "row/column outside the 3x3 grid "
                        + "(row \(candidate.info.row), column \(candidate.info.column))")
            case .notTrafficMapFile, .storedConfig, .invalidConfig:
                // Already filtered during collection; counted as skipped.
                break
            }
        }

        mutating func ingestHere(_ map: inout TrafficMap, candidate: HereCandidate) throws {
            let data = try Data(contentsOf: candidate.url)
            let outcome = map.processHereImageFile(info: candidate.info, data: data)
            record(outcome: outcome, fileName: candidate.fileName)

            switch outcome {
            case .stored:
                if verbose {
                    report(fileName: candidate.fileName, "stored at n1 \(candidate.info.n1)")
                }
            case .ignoredStale(let existing, let incoming):
                if verbose {
                    report(
                        fileName: candidate.fileName,
                        "ignored stale (existing \(timestampFormatter.string(from: existing)) "
                            + "> incoming \(timestampFormatter.string(from: incoming)))")
                }
            case .undecodableImage:
                reportAlways(fileName: candidate.fileName, "image bytes could not be decoded")
            case .outOfGrid:
                reportAlways(
                    fileName: candidate.fileName,
                    "tile outside the grid (n1 \(candidate.info.n1))")
            case .notTrafficMapFile, .storedConfig, .invalidConfig:
                break
            }
        }

        private mutating func record(outcome: TrafficMapIngestOutcome, fileName: String) {
            switch outcome {
            case .stored:
                stats.stored += 1
            case .ignoredStale:
                stats.stale += 1
            case .undecodableImage:
                stats.undecodable += 1
            case .outOfGrid:
                stats.outOfGrid += 1
            case .notTrafficMapFile, .storedConfig, .invalidConfig:
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

        private func report(fileName: String, _ detail: String) {
            fputs("  \(fileName): \(detail)\n", stderr)
        }

        /// Outcomes that indicate a real problem with the data are reported
        /// even without --verbose.
        private func reportAlways(fileName: String, _ detail: String) {
            fputs("traffic-map: warning: \(fileName): \(detail)\n", stderr)
        }
    }
}
