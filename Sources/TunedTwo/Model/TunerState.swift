//
//  TunerState.swift
//  TunedTwo
//
//  Observable application state that drives the SwiftUI views.
//

import Foundation
import Combine

final class TunerState: ObservableObject {
    enum Source: String, CaseIterable, Identifiable {
        case rtlSDR = "RTL-SDR"
        case sampleFile = "Sample File"

        var id: String { rawValue }
    }

    @Published var source: Source = .rtlSDR

    /// Frequency in MHz when using an RTL-SDR.
    @Published var frequencyMHz: String = "103.5"

    /// Selected HD Radio program (0 = HD1, 7 = HD8).
    @Published var program: Int = 0

    @Published var isPlaying: Bool = false

    @Published var status: String = "Ready"

    @Published var stationName: String = ""
    @Published var stationSlogan: String = ""
    @Published var title: String = ""
    @Published var artist: String = ""
    @Published var album: String = ""

    @Published var merLower: Float = 0
    @Published var merUpper: Float = 0
    @Published var ber: Float = 0

    var frequencyHz: Float? {
        let trimmed = frequencyMHz.trimmingCharacters(in: .whitespaces)
        guard let mhz = Double(trimmed), mhz > 0 else { return nil }
        return Float(mhz * 1_000_000)
    }
}
