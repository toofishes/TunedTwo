//
//  ArgumentParser.swift
//  tunedtwo-cli
//
//  A small hand-rolled argument parser: long options (--name value,
//  --name=value), short options (-n value, -nvalue), boolean flags, a `--`
//  terminator, and positional collection. Kept behind a tiny surface so it
//  can be swapped for swift-argument-parser without changes to the commands.
//

import Foundation

struct ArgumentParser {
    /// One accepted option or flag.
    struct OptionSpec {
        /// Long name as written after `--` (e.g. "output" for --output).
        let longName: String
        /// Short name character, if any (e.g. "o" for -o).
        let shortName: Character?
        /// Options take a value; flags do not.
        let takesValue: Bool
        /// Placeholder shown in help (e.g. "FILE"); nil for flags.
        let valuePlaceholder: String?
        /// One-line help text.
        let help: String

        static func option(
            _ longName: String,
            _ shortName: Character? = nil,
            _ valuePlaceholder: String,
            _ help: String
        ) -> OptionSpec {
            OptionSpec(
                longName: longName, shortName: shortName,
                takesValue: true, valuePlaceholder: valuePlaceholder, help: help)
        }

        static func flag(
            _ longName: String,
            _ shortName: Character? = nil,
            _ help: String
        ) -> OptionSpec {
            OptionSpec(
                longName: longName, shortName: shortName,
                takesValue: false, valuePlaceholder: nil, help: help)
        }
    }

    /// Parsed arguments.
    struct Result {
        /// Long name → value for options (and for flags, "true").
        private let valuesByLongName: [String: String]
        /// Positional arguments in order.
        let positional: [String]

        init(valuesByLongName: [String: String], positional: [String]) {
            self.valuesByLongName = valuesByLongName
            self.positional = positional
        }

        func value(_ longName: String) -> String? {
            valuesByLongName[longName]
        }

        func isSet(_ longName: String) -> Bool {
            valuesByLongName[longName] != nil
        }
    }

    let specs: [OptionSpec]

    init(specs: [OptionSpec]) {
        self.specs = specs
    }

    // MARK: - Parsing

    func parse(
        _ arguments: [String],
        positionalCount: ClosedRange<Int>,
        positionalHint: String
    ) throws -> Result {
        var values: [String: String] = [:]
        var positional: [String] = []
        var index = 0
        var onlyPositionalRemaining = false

        func spec(longName: String) -> OptionSpec? {
            specs.first { $0.longName == longName }
        }
        func spec(shortName: Character) -> OptionSpec? {
            specs.first { $0.shortName == shortName }
        }

        while index < arguments.count {
            let argument = arguments[index]
            index += 1

            if onlyPositionalRemaining {
                positional.append(argument)
                continue
            }

            if argument == "--" {
                onlyPositionalRemaining = true
                continue
            }

            if argument.hasPrefix("--") {
                let body = String(argument.dropFirst(2))
                let name: String
                let inlineValue: String?
                if let equals = body.firstIndex(of: "=") {
                    name = String(body[body.startIndex..<equals])
                    inlineValue = String(body[body.index(after: equals)...])
                } else {
                    name = body
                    inlineValue = nil
                }
                guard let spec = spec(longName: name) else {
                    throw UsageError("unknown option '--\(name)'")
                }
                if spec.takesValue {
                    let value: String
                    if let inlineValue {
                        value = inlineValue
                    } else if index < arguments.count {
                        value = arguments[index]
                        index += 1
                    } else {
                        throw UsageError("missing value for '--\(name) \(spec.valuePlaceholder ?? "VALUE")'")
                    }
                    values[spec.longName] = value
                } else {
                    if inlineValue != nil {
                        throw UsageError("option '--\(name)' does not take a value")
                    }
                    values[spec.longName] = "true"
                }
                continue
            }

            if argument.count > 1 && argument.hasPrefix("-") {
                // Short option cluster. Value-taking shorts must be alone
                // or last in the cluster; their value is the next argument.
                let characters = Array(argument.dropFirst())
                var position = 0
                while position < characters.count {
                    let character = characters[position]
                    guard let spec = spec(shortName: character) else {
                        throw UsageError("unknown option '-\(character)'")
                    }
                    if spec.takesValue {
                        let remaining = characters[(position + 1)...]
                        if !remaining.isEmpty {
                            values[spec.longName] = String(remaining)
                        } else if index < arguments.count {
                            values[spec.longName] = arguments[index]
                            index += 1
                        } else {
                            throw UsageError("missing value for '-\(character)'")
                        }
                        position = characters.count
                    } else {
                        values[spec.longName] = "true"
                        position += 1
                    }
                }
                continue
            }

            positional.append(argument)
        }

        guard positionalCount.contains(positional.count) else {
            let expected: String
            if positionalCount.lowerBound == positionalCount.upperBound {
                expected = "exactly \(positionalCount.lowerBound)"
            } else if positionalCount.upperBound == Int.max {
                expected = "at least \(positionalCount.lowerBound)"
            } else {
                expected = "\(positionalCount.lowerBound) to \(positionalCount.upperBound)"
            }
            let received = positional.count == 1 ? "1 argument" : "\(positional.count) arguments"
            throw UsageError("expected \(expected) positional argument(s) \(positionalHint), got \(received)")
        }

        return Result(valuesByLongName: values, positional: positional)
    }

    // MARK: - Help rendering

    /// Multi-line option help for `--help`, aligned in two columns.
    var helpLines: [String] {
        var lines: [String] = ["Options:"]
        var flags: [String] = []
        var options: [String] = []
        for spec in specs {
            var signature = "--\(spec.longName)"
            if let shortName = spec.shortName {
                signature = "-\(shortName), \(signature)"
            }
            if let placeholder = spec.valuePlaceholder {
                signature += " <\(placeholder)>"
            }
            let entry = "  \(signature.padding(toLength: 24, withPad: " ", startingAt: 0)) \(spec.help)"
            if spec.takesValue {
                options.append(entry)
            } else {
                flags.append(entry)
            }
        }
        lines += options + flags
        lines.append("  \(("-h, --help").padding(toLength: 24, withPad: " ", startingAt: 0)) Show this help.")
        return lines
    }
}
