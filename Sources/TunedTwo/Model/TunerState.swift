//
//  TunerState.swift
//  TunedTwo
//
//  Observable application state that drives the SwiftUI views.
//
//  MainActor-isolated: the tuner session (a background actor) feeds updates
//  into this class exclusively through the awaited ``TunerEventSink``
//  methods, so UI-owned state is only ever mutated on the main thread.
//

import Foundation
import Combine

@MainActor
@Observable
final class TunerState {
    enum Source: String, CaseIterable, Identifiable {
        case rtlSDR = "RTL-SDR"
        case sampleFile = "Sample File"

        var id: String { rawValue }
    }

    var source: Source = .rtlSDR

    /// Frequency in MHz when using an RTL-SDR.
    var frequencyMHz: String = "103.5"

    /// Selected HD Radio program (0 = HD1, 7 = HD8).
    var program: Int = 0

    var isPlaying: Bool = false

    var status: String = "Ready"

    var stationName: String = ""
    var stationSlogan: String = ""
    var title: String = ""
    var artist: String = ""
    var album: String = ""

    var merLower: Float = 0
    var merUpper: Float = 0
    var ber: Float = 0

    var frequencyHz: Float? {
        let trimmed = frequencyMHz.trimmingCharacters(in: .whitespaces)
        guard let mhz = Double(trimmed), mhz > 0 else { return nil }
        return Float(mhz * 1_000_000)
    }
}

// MARK: - TunerEventSink

extension TunerState: TunerEventSink {
    func tunerSessionDidEmit(_ event: TunerEvent) async {
        switch event {
        case .started:
            isPlaying = true
            status = "Playing"
        case .stopped:
            isPlaying = false
            status = "Stopped"
        case .failed(let message):
            isPlaying = false
            status = "Error: \(message)"
        case .lostDevice:
            status = "Device lost"
            isPlaying = false
        case .syncAchieved:
            status = "Synchronized"
        case .lostSync:
            status = "Lost sync"
        case .mer(let lower, let upper):
            merLower = lower
            merUpper = upper
        case .ber(let cber):
            ber = cber
        case .stationName(let name):
            stationName = name
        case .stationSlogan(let slogan):
            stationSlogan = slogan
        case .id3(_, let newTitle, let newArtist, let newAlbum):
            title = newTitle
            artist = newArtist
            album = newAlbum
        case .audio:
            break // Consumed inside TunerSession; never reaches the UI.
        }
    }
}
