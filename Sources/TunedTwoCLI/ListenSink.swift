//
//  ListenSink.swift
//  TunedTwo
//

import Foundation
import TunedTwoCore

func timestamped(_ message: String) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return "[\(formatter.string(from: Date()))] \(message)"
}

actor ListenSink: TunerEventSink {
    private let selectedSubprogram: Int
    private var startupFailure: String?
    private var lastStationName: String?
    private var lastNowPlaying: String?

    init(subprogram: Int) {
        self.selectedSubprogram = subprogram
    }

    func tunerSessionDidEmit(_ event: TunerEvent) async {
        switch event {
        case .failed(let message):
            startupFailure = message
        case .stationName(let name) where !name.isEmpty && name != lastStationName:
            lastStationName = name
            print(timestamped("Station: \(name)"))
        case .id3(let program, let id3) where program == selectedSubprogram:
            let description = [id3.artist, id3.title]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " — ")
            if !description.isEmpty, description != lastNowPlaying {
                lastNowPlaying = description
                print(timestamped("Now playing: \(description)"))
            }
        default:
            break
        }
    }

    func failureMessage() -> String? {
        startupFailure
    }
}
