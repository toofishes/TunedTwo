//
//  ListenFileCommand.swift
//  TunedTwo
//

import ArgumentParser
import Foundation
import TunedTwoCore

struct ListenFileCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "listen-file",
        abstract: "Listen to an uncompressed NRSC5 I/Q sample file"
    )

    @Argument(help: "Path to an uncompressed NRSC5 I/Q sample file (for example, sample.bin or a .cu8 capture).")
    var file: String

    @Option(help: "Zero-indexed subprogram to listen to.")
    var subprogram = 0

    func validate() throws {
        guard (0..<8).contains(subprogram) else {
            throw ValidationError("subprogram must be between 0 and 7")
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: file, isDirectory: &isDirectory), !isDirectory.boolValue,
            FileManager.default.isReadableFile(atPath: file)
        else {
            throw ValidationError("'\(file)' is not a readable file")
        }
    }

    mutating func run() async throws {
        let sink = ListenSink(subprogram: subprogram)
        let session = TunerSession(sink: sink)

        await session.start(
            TunerConfiguration(
                source: .samplePipe(path: file),
                frequencyHz: nil,
                program: subprogram,
            ))

        if let message = await sink.failureMessage() {
            await session.stop()
            throw RuntimeError("could not start file playback: \(message)")
        }

        signal(SIGINT, SIG_IGN)
        let signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        signalSource.setEventHandler {
            Task {
                print(timestamped("Interrupt signal (SIGINT) received. Shutting down..."))
                await session.stop()
                Self.exit()
            }
        }
        signalSource.resume()

        print(
            timestamped(
                "Playing '\(URL(fileURLWithPath: file).lastPathComponent)' (HD\(subprogram + 1)). Press Ctrl+C to stop."
            ))
        while true {
            try await Task.sleep(for: .milliseconds(250))
            if let message = await sink.failureMessage() {
                await session.stop()
                throw RuntimeError("file playback failed: \(message)")
            }
        }
    }
}
