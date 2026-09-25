//
//  CLI.swift
//  tunedtwo-cli
//
//  Entry point and subcommand dispatch.
//

import ArgumentParser
import Foundation

@main
struct TunedTwoCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tunedtwo-cli",
        abstract: "Command-line access to TunedTwoCore functionality.",
        subcommands: [TrafficMapCommand.self, DBTestCommand.self, ScanCommand.self]
    )
}

/// A processing failure that is not the user's fault; exits with code 2.
struct RuntimeError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
