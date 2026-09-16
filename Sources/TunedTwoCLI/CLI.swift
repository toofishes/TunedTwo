//
//  CLI.swift
//  tunedtwo-cli
//
//  Entry point and subcommand dispatch.
//
//  Exit codes (shared by all subcommands):
//    0  success
//    1  usage error (bad arguments, unknown command, missing directory)
//    2  runtime failure (no tiles found, unreadable input, write error)
//

import Foundation

@main
enum CLI {
    /// Registered subcommands, in help order.
    static let commands: [any CLICommand.Type] = [
        TrafficMapCommand.self
    ]

    static let programName = "tunedtwo-cli"

    static func main() async {
        let arguments = Array(ProcessInfo.processInfo.arguments.dropFirst())
        exit(await run(arguments))
    }

    static func run(_ arguments: [String]) async -> Int32 {
        guard let name = arguments.first, !name.isEmpty else {
            printUsage()
            return 1
        }

        if name == "--help" || name == "-h" || name == "help" {
            printUsage()
            return 0
        }

        guard let commandType = Self.commands.first(where: { $0.name == name }) else {
            fputs("\(programName): unknown command '\(name)'\n\n", stderr)
            printUsage()
            return 1
        }

        let command = commandType.init()
        do {
            return try await command.run(arguments: Array(arguments.dropFirst()))
        } catch let error as UsageError {
            fputs("\(programName): \(error.message)\n", stderr)
            fputs("\(commandType.usageLine)\n", stderr)
            return 1
        } catch {
            fputs("\(programName): error: \(error.localizedDescription)\n", stderr)
            return 2
        }
    }

    static func printUsage() {
        var text = "usage: \(programName) <command> [<args>]\n\nCommands:\n"
        for command in commands {
            text += "  \(command.name.padding(toLength: 16, withPad: " ", startingAt: 0)) \(command.abstract)\n"
        }
        text += "\nRun '\(programName) <command> --help' for details.\n"
        fputs(text, stderr)
    }
}

/// A subcommand of the CLI. Kept small so it (and ``ArgumentParser``) can
/// be swapped for swift-argument-parser later without touching the command
/// implementations' core logic.
protocol CLICommand: Sendable {
    static var name: String { get }
    static var abstract: String { get }
    static var usageLine: String { get }

    init()

    /// Run with the arguments *after* the subcommand name.
    /// Returns the process exit code.
    func run(arguments: [String]) async throws -> Int32
}

/// Thrown for argument problems; rendered with the command's usage line and
/// exits with code 1.
struct UsageError: Error {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}
