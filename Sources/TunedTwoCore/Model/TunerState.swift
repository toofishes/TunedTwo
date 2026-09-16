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
import Observation
import nrsc5

@MainActor
@Observable
public final class TunerState {
    public enum Source: String, CaseIterable, Identifiable {
        case rtlSDR = "RTL-SDR"
        case sampleFile = "Sample File"

        public var id: String { rawValue }
    }

    public var source: Source = .rtlSDR

    /// Frequency in MHz when using an RTL-SDR.
    public var frequencyMHz: String = "103.5"

    /// Selected HD Radio program (0 = HD1, 7 = HD8).
    public var program: Int = 0

    public var isPlaying: Bool = false

    public var status: String = "Ready"

    public var stationName: String = ""
    public var stationSlogan: String = ""
    public var stationMessage: String = ""

    public var title: String = ""
    public var artist: String = ""
    public var album: String = ""
    public var genre: String = ""

    private var byteCount: Int = 0
    private var receiveCount: Int = 0

    public var bitsPerSecond: Int = 0
    public var merLower: Float = 0
    public var merUpper: Float = 0
    public var ber: Float = 0

    public var frequencyHz: Float? {
        let trimmed = frequencyMHz.trimmingCharacters(in: .whitespaces)
        guard let mhz = Double(trimmed), mhz > 0 else { return nil }
        return Float(mhz * 1_000_000)
    }

    public var latestStationImage: [UInt8] = []
    public var latestCoverArt: [UInt8] = []
    public var latestImageData: [UInt8] = []
    public var traffic = TrafficMap()
    public var weather = WeatherMap()

    public var logEntries: [LogEvent] = []

    public init() {}
}

// MARK: - TunerEventSink

extension TunerState: TunerEventSink {
    public func tunerSessionDidEmit(_ event: TunerEvent) async {
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
            logEntries.append(LogEvent(timestamp: Date(), title: "Synchronized", description: "Synchronized", systemImage: "checkmark.icloud.fill", tintColor: .blue))
        case .lostSync:
            status = "Lost sync"
        case .mer(let lower, let upper):
            merLower = lower
            merUpper = upper
        case .ber(let cber):
            ber = cber
        case .hdc(_, let size, _):
            byteCount += size
            receiveCount += 1
            if receiveCount >= 32 || bitsPerSecond == 0 {
                bitsPerSecond = byteCount * 8 * Int(NRSC5_SAMPLE_RATE_AUDIO) / Int(NRSC5_AUDIO_FRAME_SAMPLES) / receiveCount;
                byteCount = 0
                receiveCount = 0
            }
        case .stationName(let name):
            stationName = name
            logEntries.append(LogEvent(timestamp: Date(), title: "Station Name", description: name, systemImage: "checkmark.icloud.fill", tintColor: .blue))
        case .stationSlogan(let slogan):
            stationSlogan = slogan
            logEntries.append(LogEvent(timestamp: Date(), title: "Station Slogan", description: slogan, systemImage: "checkmark.icloud.fill", tintColor: .blue))
        case .stationMessage(let message):
            stationMessage = message
            logEntries.append(LogEvent(timestamp: Date(), title: "Station Message", description: message, systemImage: "checkmark.icloud.fill", tintColor: .blue))
        case .stationID(let countryCode, let fccFacilityID):
            logEntries.append(LogEvent(timestamp: Date(), title: "Station ID", description: "Country \(countryCode) ID \(fccFacilityID)", systemImage: "checkmark.icloud.fill", tintColor: .blue))
        case .stationLocation(let latitude, let longitude, let altitude):
            logEntries.append(LogEvent(timestamp: Date(), title: "Station Location", description: "Lat \(latitude) Lon \(longitude) Alt \(altitude)", systemImage: "checkmark.icloud.fill", tintColor: .blue))
        case .id3(_, let newTitle, let newArtist, let newAlbum, let newGenre):
            title = newTitle
            artist = newArtist
            album = newAlbum
            genre = newGenre
        case .lot(let id, let mime, let name, let data, _, let service, let component):
            if mime == NRSC5_MIME_JPEG || mime == NRSC5_MIME_PNG {
                latestImageData = data
            }
            let mimeString = String(format: "%08X", mime)

            var compMime = "Unknown"
            if let component {
                switch component {
                case .data(_, _, _, _, let mime):
                    compMime = String(format: "%08X", mime)
                    if mime == NRSC5_MIME_PRIMARY_IMAGE {
                        latestCoverArt = data
                    } else if mime == NRSC5_MIME_STATION_LOGO {
                        latestStationImage = data
                    } else if mime == NRSC5_MIME_TTN_STM_TRAFFIC {
                        traffic.processLOTFile(name: name, data: data)
                    } else if mime == NRSC5_MIME_TTN_STM_WEATHER {
                        weather.processLOTFile(name: name, data: data)
                    }
                default:
                    break
                }
            }

            logEntries.append(LogEvent(timestamp: Date(), title: "LOT File", description: "ID: \(id), File: \(name), Size: \(data.count), Mime: \(mimeString), Service: \(String(describing: service)), Component: \(String(describing: component)), Component Mime: \(compMime)", systemImage: "checkmark.icloud.fill", tintColor: .blue))
        case .audio:
            break // Consumed inside TunerSession; never reaches the UI.
        default:
            // Newly-added nrsc5 events are forwarded to the sink but not
            // yet displayed in the UI.
            break
        }
    }
}
