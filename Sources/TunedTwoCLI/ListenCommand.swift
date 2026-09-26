//
//  ListenCommand.swift
//  TunedTwo
//

import ArgumentParser
import Foundation
import TunedTwoCore

private actor ListenSink: TunerEventSink {
    private var failed = false
    private var eventCount: Int = 0

    func tunerSessionDidEmit(_ event: TunerEvent) async {
        if case .failed = event {
            failed = true
        }
        eventCount += 1
    }

    func totalEventCount() -> Int {
        return eventCount
    }
}

struct ListenCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "listen",
        abstract: "Listen to a given frequency and program"
    )

    @Argument(help: "The frequency to listen on.")
    var frequency: Double

    @Argument(help: "The subprogram to listen to (zero-indexed).")
    var program: Int

    mutating func run() async throws {
        let sink = ListenSink()
        let session = TunerSession(sink: sink)

        await session.start(
            TunerConfiguration(
                source: .rtlSDR(deviceIndex: 0),
                frequencyHz: Float(frequency) * 1_000_000,
                program: program,
            ))

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

        print("Running... Press Ctrl+C to interrupt.")
        while true {
            try await Task.sleep(for: .seconds(10))
        }
    }
}
