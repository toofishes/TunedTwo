//
//  ListenSink.swift
//  TunedTwo
//

import Foundation
import TunedTwoCore

actor ListenSink: TunerEventSink {
    private var startupFailure: String?
    private var lastStationName: String?
    private var lastNowPlaying: String?

    func tunerSessionDidEmit(_ event: TunerEvent) async {
        switch event {
        case .failed(let message):
            startupFailure = message
        case .stationName(let name) where !name.isEmpty && name != lastStationName:
            lastStationName = name
            print("Station: \(name)")
        case .id3(_, let id3):
            let description = [id3.artist, id3.title]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " — ")
            if !description.isEmpty, description != lastNowPlaying {
                lastNowPlaying = description
                print("Now playing: \(description)")
            }
        default:
            break
        }
    }

    func failureMessage() -> String? {
        startupFailure
    }
}
