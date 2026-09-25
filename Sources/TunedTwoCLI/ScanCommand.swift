//
//  ScanCommand.swift
//  TunedTwo
//

import ArgumentParser
import Foundation
import TunedTwoCore

actor ScanSink: TunerEventSink {
    private var events: [TunerEvent] = []

    func tunerSessionDidEmit(_ event: TunerEvent) async {
        events.append(event)
    }

    func dequeueEvents() -> [TunerEvent] {
        let result = events
        events.removeAll()
        return result
    }
}

struct ScanCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scan",
        abstract: "Scan the FM band for available stations"
    )

    mutating func run() async throws {
        let sink = ScanSink()
        let session = try TunerSession(sink: sink)

        await session.start(
            TunerConfiguration(
                source: .rtlSDR(deviceIndex: 0),
                frequencyHz: 87_700_000,
                program: 0,
            ))

        // Drain any startup events and abort if the session failed to start.
        for event in await sink.dequeueEvents() {
            if case .failed(let message) = event {
                print("Startup failed: \(message)")
                await session.stop()
                return
            }
        }

        for hz in stride(from: 87_900_000, to: 108_000_000, by: 200_000) {
            // Discard any events that were still in flight from the previous
            // frequency before retuning so we only act on post-retune state.
            _ = await sink.dequeueEvents()
            await session.retune(frequencyHz: Float(hz))

            // initial deadline is 800ms; we slightly extend it if a station was found
            var deadline = Date().addingTimeInterval(0.8)
            var psmi: Int = -1
            var stationID: (countryCode: String, fccFacilityID: Int)?
            var stationName: String?
            var audioPrograms = Set<Int>()
            var dsdMimes = Set<UInt32>()

            scanLoop: while Date() < deadline {
                for event in await sink.dequeueEvents() {
                    switch event {
                    case .agc, .lostSync:
                        continue
                    case .failed:
                        break scanLoop
                    case .syncAchieved(_, let foundPSMI, _, _, _, _):
                        psmi = foundPSMI
                        deadline = deadline.addingTimeInterval(0.4)
                    case .stationID(let countryCode, let fccFacilityID):
                        if stationID == nil {
                            stationID = (countryCode, fccFacilityID)
                        }
                    case .stationName(let name):
                        if stationName == nil {
                            stationName = name
                        }
                    case .audioService(let program, _, _, _, _, _, _, _):
                        audioPrograms.insert(program)
                    case .audioServiceDescriptor(let desc):
                        audioPrograms.insert(desc.program)
                    case .dataServiceDescriptor(let desc):
                        dsdMimes.insert(desc.mimeType)
                    default:
                        break
                    }
                }
                try? await Task.sleep(for: .milliseconds(50))
            }

            let mhz = Double(hz) / 1_000_000
            if psmi < 0 {
                print(String(format: "%.1f MHz: no HD Radio", mhz))
            } else {
                var parts: [String] = [String(format: "%.1f MHz, HD Radio (PMSI %d)", mhz, psmi)]
                var nameParts: [String] = []
                if let stationID {
                    nameParts.append("[\(stationID.countryCode) \(stationID.fccFacilityID)]")
                }
                if let name = stationName, !name.isEmpty {
                    nameParts.append(name)
                }
                parts.append(nameParts.joined(separator: " "))
                if !audioPrograms.isEmpty {
                    let programs = audioPrograms.sorted().map { "HD\($0 + 1)" }.joined(separator: ", ")
                    parts.append("Audio programs: \(programs)")
                }
                if !dsdMimes.isEmpty {
                    let services = dsdMimes.sorted().map { nameForDSDMIMEType($0) }.joined(separator: ", ")
                    parts.append("Data services: \(services)")
                }
                print(parts.joined(separator: "\n  "))
            }
        }
        await session.stop()
    }
}
