//
//  CLI.swift
//  tunedtwo-cli
//
//  Entry point and subcommand dispatch.
//
//  Uses Apple's swift-argument-parser for parsing and help generation.
//  Exit codes:
//    0   success
//    64  usage error (bad arguments, unknown command, missing directory)
//    2   runtime failure (no tiles found, unreadable input, write error)
//

import ArgumentParser
import Foundation

@main
enum CLI {
    static func main() {
        do {
            var command = try TunedTwoCLI.parseAsRoot()
            try command.run()
        } catch let error as RuntimeError {
            fputs("tunedtwo-cli: error: \(error)\n", stderr)
            exit(2)
        } catch {
            TunedTwoCLI.exit(withError: error)
        }
    }
}

struct TunedTwoCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tunedtwo-cli",
        abstract: "Command-line access to TunedTwoCore functionality.",
        subcommands: [TrafficMapCommand.self]
    )
}

/// A processing failure that is not the user's fault; exits with code 2.
struct RuntimeError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
