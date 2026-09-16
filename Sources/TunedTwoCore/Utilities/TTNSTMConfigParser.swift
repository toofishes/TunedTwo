//
//  TTNSTMConfigParser.swift
//  TunedTwo
//
//  Generic parser for TTN/STM-style text configuration files.
//
//  Supports lines of the form:
//      Key="value"
//      Key="value1";"value2";"value3"
//
//  Blank lines are ignored. Keys are case-sensitive and whitespace around
//  the key is trimmed. Quoted values may contain standard \ and \"
//  escapes.
//

import Foundation

/// A raw, successfully parsed TTN/STM configuration.
///
/// Every key maps to one or more string values, preserving the order in
/// which they appeared in the file.
public struct TTNSTMConfig: Equatable, Sendable {
    public let entries: [String: [String]]

    public init(entries: [String: [String]]) {
        self.entries = entries
    }

    /// All values for a key, or `nil` if the key is absent.
    public func values(for key: String) -> [String]? {
        entries[key]
    }

    /// The first value for a key, or `nil` if the key is absent.
    ///
    /// Use this for keys that are expected to appear exactly once.
    public func singleValue(for key: String) -> String? {
        entries[key]?.first
    }
}

/// Errors raised while tokenizing a TTN/STM configuration file.
public enum TTNSTMConfigError: Error, Equatable {
    /// A non-empty, non-comment line did not contain `=`.
    case missingKeySeparator(line: String)

    /// The key portion of a line was empty after trimming whitespace.
    case emptyKey(line: String)

    /// The value portion could not be parsed as one or more quoted strings.
    case malformedValue(line: String)
}

/// Parses TTN/STM-style `Key="value"` text configurations.
public struct TTNSTMConfigParser: Sendable {
    public init() {}

    /// Parse the entire configuration string.
    ///
    /// - Throws: `TTNSTMConfigError` if any line is malformed.
    public func parse(_ input: String) throws -> TTNSTMConfig {
        var entries: [String: [String]] = [:]

        let lines = input.components(separatedBy: .newlines)
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            guard let equalsIndex = line.firstIndex(of: "=") else {
                throw TTNSTMConfigError.missingKeySeparator(line: rawLine)
            }

            let key = String(line[..<equalsIndex]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else {
                throw TTNSTMConfigError.emptyKey(line: rawLine)
            }

            let valuePartStart = line.index(after: equalsIndex)
            let valuePart = String(line[valuePartStart...])
            let values = try parseValues(valuePart, rawLine: rawLine)
            guard !values.isEmpty else {
                throw TTNSTMConfigError.malformedValue(line: rawLine)
            }

            entries[key] = values
        }

        return TTNSTMConfig(entries: entries)
    }

    // MARK: - Tokenizing

    /// Extract the quoted values from the right-hand side of a line.
    private func parseValues(_ valuePart: String, rawLine: String) throws -> [String] {
        var values: [String] = []
        var current = ""
        var index = valuePart.startIndex
        var insideQuotes = false

        while index < valuePart.endIndex {
            let char = valuePart[index]

            if insideQuotes {
                if char == "\\" {
                    let next = valuePart.index(after: index)
                    guard next < valuePart.endIndex else {
                        throw TTNSTMConfigError.malformedValue(line: rawLine)
                    }
                    current.append(char)
                    current.append(valuePart[next])
                    index = valuePart.index(after: next)
                } else if char == "\"" {
                    values.append(unescape(current))
                    current = ""
                    insideQuotes = false
                    index = valuePart.index(after: index)
                } else {
                    current.append(char)
                    index = valuePart.index(after: index)
                }
            } else {
                if char == "\"" {
                    insideQuotes = true
                    index = valuePart.index(after: index)
                } else if char == ";" || char.isWhitespace {
                    index = valuePart.index(after: index)
                } else {
                    throw TTNSTMConfigError.malformedValue(line: rawLine)
                }
            }
        }

        guard !insideQuotes else {
            throw TTNSTMConfigError.malformedValue(line: rawLine)
        }

        return values
    }

    /// Convert escaped sequences back to their literal characters.
    private func unescape(_ string: String) -> String {
        var result = ""
        var index = string.startIndex

        while index < string.endIndex {
            let char = string[index]
            if char == "\\" {
                let next = string.index(after: index)
                guard next < string.endIndex else {
                    result.append(char)
                    break
                }
                let nextChar = string[next]
                if nextChar == "\\" || nextChar == "\"" {
                    result.append(nextChar)
                    index = string.index(after: next)
                } else {
                    result.append(char)
                    index = next
                }
            } else {
                result.append(char)
                index = string.index(after: index)
            }
        }

        return result
    }
}
