//
//  ListenCommand.swift
//  TunedTwo
//

import ArgumentParser
import Foundation
import TunedTwoCore

struct ListenCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "listen",
        abstract: "Listen to a live FM frequency using an RTL-SDR"
    )

    @Argument(help: "The FM frequency to listen on, in MHz.")
    var frequency: Double

    @Option(help: "Zero-indexed subprogram to listen to.")
    var subprogram = 0

    func validate() throws {
        guard (0..<8).contains(subprogram) else {
            throw ValidationError("subprogram must be between 0 and 7")
        }
    }

    mutating func run() async throws {
        let sink = ListenSink()
        let session = TunerSession(sink: sink)

        await session.start(
            TunerConfiguration(
                source: .rtlSDR(deviceIndex: 0),
                frequencyHz: Float(frequency) * 1_000_000,
                program: subprogram,
            ))

        if let message = await sink.failureMessage() {
            await session.stop()
            throw RuntimeError("could not start live listening: \(message)")
        }

        signal(SIGINT, SIG_IGN)
        let signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        signalSource.setEventHandler {
            Task {
                print("\nInterrupt signal (SIGINT) received. Shutting down...")
                await session.stop()
                Self.exit()
            }
        }
        signalSource.resume()

        print("Listening on \(frequency) MHz (HD\(subprogram + 1)). Press Ctrl+C to stop.")
        while true {
            try await Task.sleep(for: .seconds(10))
        }
    }
}
