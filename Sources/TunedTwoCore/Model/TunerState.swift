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
    public var eventCounts: [String: Int] = .init()

    public init() {}
}

// MARK: - TunerEventSink

extension TunerState: TunerEventSink {
    public func tunerSessionDidEmit(_ event: TunerEvent) async {
        eventCounts[event.caseName, default: 0] += 1
        switch event {
        case .started:
            isPlaying = true
            status = "Playing"
        case .stopped:
            isPlaying = false
            status = "Stopped"
        case let .failed(message):
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
        case let .mer(lower, upper):
            merLower = lower
            merUpper = upper
        case let .ber(cber):
            ber = cber
        case let .hdc(_, size, _):
            byteCount += size
            receiveCount += 1
            if receiveCount >= 32 || bitsPerSecond == 0 {
                bitsPerSecond = byteCount * 8 * Int(NRSC5_SAMPLE_RATE_AUDIO) / Int(NRSC5_AUDIO_FRAME_SAMPLES) / receiveCount;
                byteCount = 0
                receiveCount = 0
            }
        case let .stationName(name):
            stationName = name
            logEntries.append(LogEvent(timestamp: Date(), title: "Station Name", description: name, systemImage: "checkmark.icloud.fill", tintColor: .blue))
        case let .stationSlogan(slogan):
            stationSlogan = slogan
            logEntries.append(LogEvent(timestamp: Date(), title: "Station Slogan", description: slogan, systemImage: "checkmark.icloud.fill", tintColor: .blue))
        case let .stationMessage(message):
            stationMessage = message
            logEntries.append(LogEvent(timestamp: Date(), title: "Station Message", description: message, systemImage: "checkmark.icloud.fill", tintColor: .blue))
        case let .stationID(countryCode, fccFacilityID):
            logEntries.append(LogEvent(timestamp: Date(), title: "Station ID", description: "Country \(countryCode) ID \(fccFacilityID)", systemImage: "checkmark.icloud.fill", tintColor: .blue))
        case let .stationLocation(latitude, longitude, altitude):
            logEntries.append(LogEvent(timestamp: Date(), title: "Station Location", description: "Lat \(latitude) Lon \(longitude) Alt \(altitude)", systemImage: "checkmark.icloud.fill", tintColor: .blue))
        case let .id3(_, newTitle, newArtist, newAlbum, newGenre):
            title = newTitle
            artist = newArtist
            album = newAlbum
            genre = newGenre
        case let .lot(id, mime, name, data, _, service, component):
            let isImage = mime == NRSC5_MIME_JPEG || mime == NRSC5_MIME_PNG
            if isImage {
                latestImageData = data
            }
            let mimeName = nameForNRSC5MIMEType(mime)

            var compMimeName = "None"
            if let component {
                switch component {
                case .data(_, _, _, _, let mime):
                    compMimeName = nameForNRSC5MIMEType(mime)
                    if mime == NRSC5_MIME_PRIMARY_IMAGE {
                        latestCoverArt = data
                    } else if mime == NRSC5_MIME_STATION_LOGO {
                        latestStationImage = data
                    } else if mime == NRSC5_MIME_TTN_STM_TRAFFIC {
                        if isImage {
                            traffic.processImageFile(name: name, data: data)
                        } else {
                            traffic.processConfigFile(data: data)
                        }
                    } else if mime == NRSC5_MIME_TTN_STM_WEATHER {
                        if isImage {
                            weather.processImageFile(name: name, data: data)
                        } else {
                            weather.processConfigFile(data: data)
                        }
                    }
                case .audio(_, _, _, let mime):
                    compMimeName = nameForNRSC5MIMEType(mime)
                case .unknown:
                    compMimeName = "Unknown"
                }
            }

            let serviceDesc = service.map { "type=\($0.type) #\($0.number) \($0.name) (\($0.components.count) components)" } ?? "None"

            let componentDesc: String
            if let component {
                switch component {
                case let .data(cid, port, serviceDataType, aasType, _):
                    componentDesc = "data id=\(cid) port=\(port) sdt=\(serviceDataType) aas=\(aasType)"
                case let .audio(cid, port, programType, _):
                    componentDesc = "audio id=\(cid) port=\(port) programType=\(programType)"
                case let .unknown(cid):
                    componentDesc = "unknown id=\(cid)"
                }
            } else {
                componentDesc = "None"
            }

            logEntries.append(LogEvent(timestamp: Date(), title: "LOT File", description: "ID: \(id), File: \(name), Size: \(data.count), MIME: \(mimeName), Service: \(serviceDesc), Component: \(componentDesc), Component MIME: \(compMimeName)", systemImage: "checkmark.icloud.fill", tintColor: .blue))
        case let .agc(gainDB, peakDBFS, isFinal):
            logEntries.append(LogEvent(timestamp: Date(), title: "AGC", description: "Gain \(String(format: "%.1f", gainDB)) dB, Peak \(String(format: "%.1f", peakDBFS)) dBFS, Final \(isFinal)", systemImage: "chart.line.uptrend.xyaxis", tintColor: .orange))
        case let .audioService(program, access, type, codecMode, blendControl, digitalAudioGain, commonDelay, latency):
            logEntries.append(LogEvent(timestamp: Date(), title: "Audio Service", description: "Program \(program), Access \(access), Type \(type), Codec \(codecMode), Blend \(blendControl), Gain \(digitalAudioGain), Delay \(commonDelay), Latency \(latency)", systemImage: "speaker.wave.2.fill", tintColor: .blue))
        case let .audioServiceDescriptor(descriptors):
            let list = descriptors.map { "Program \($0.program), Access \($0.access), Type \($0.type), SoundExp \($0.soundExp)" }.joined(separator: "; ")
            logEntries.append(LogEvent(timestamp: Date(), title: "Audio Service Descriptor", description: list, systemImage: "waveform", tintColor: .blue))
        case let .dataServiceDescriptor(descriptors):
            let list = descriptors.map { "Access \($0.access), Type \($0.type), MIME \(nameForNRSC5MIMEType($0.mimeType))" }.joined(separator: "; ")
            logEntries.append(LogEvent(timestamp: Date(), title: "Data Service Descriptor", description: list, systemImage: "waveform", tintColor: .purple))
        case let .exciterInfo(manufacturerID, coreVersion, coreStatus, manufacturerVersion, manufacturerStatus, importerConnected):
            logEntries.append(LogEvent(timestamp: Date(), title: "Exciter Info", description: "Manufacturer \(manufacturerID), Core \(coreVersion.map { String($0) }.joined(separator: ".")) (\(coreStatus)), Manufacturer \(manufacturerVersion.map { String($0) }.joined(separator: ".")) (\(manufacturerStatus)), Importer \(importerConnected)", systemImage: "antenna.radiowaves.left.and.right", tintColor: .green))
        case let .importerInfo(manufacturerID, coreVersion, coreStatus, manufacturerVersion, manufacturerStatus):
            logEntries.append(LogEvent(timestamp: Date(), title: "Importer Info", description: "Manufacturer \(manufacturerID), Core \(coreVersion.map { String($0) }.joined(separator: ".")) (\(coreStatus)), Manufacturer \(manufacturerVersion.map { String($0) }.joined(separator: ".")) (\(manufacturerStatus))", systemImage: "arrow.down.circle.fill", tintColor: .green))
        case let .leapSecondOffset(pendingOffset, currentOffset, pendingALFN):
            logEntries.append(LogEvent(timestamp: Date(), title: "Leap Second Offset", description: "Pending \(pendingOffset)s, Current \(currentOffset)s, ALFN \(pendingALFN)", systemImage: "clock", tintColor: .orange))
        case let .localTime(utcOffsetMinutes, dstRegional, dstLocal, dstSchedule):
            logEntries.append(LogEvent(timestamp: Date(), title: "Local Time", description: "UTC Offset \(utcOffsetMinutes) min, Regional DST \(dstRegional), Local DST \(dstLocal), Schedule \(dstSchedule)", systemImage: "clock.badge.checkmark", tintColor: .orange))
        case let .sig(services):
            let list = services.map { "#\($0.number) \($0.name) (\($0.components.count) components)" }.joined(separator: ", ")
            logEntries.append(LogEvent(timestamp: Date(), title: "SIG", description: "Services: \(list)", systemImage: "antenna.radiowaves.left.and.right", tintColor: .purple))
        case let .stream(seq, size, _, service, component):
            var description = "Seq \(seq), Size \(size)"
            if let service {
                description += ", Service #\(service.number) \(service.name)"
            }
            if let component {
                let componentMime: String
                switch component {
                case .data(_, _, _, _, let mime), .audio(_, _, _, let mime):
                    componentMime = nameForNRSC5MIMEType(mime)
                case .unknown:
                    componentMime = "Unknown"
                }
                description += ", Component \(componentMime)"
            }
            logEntries.append(LogEvent(timestamp: Date(), title: "Stream", description: description, systemImage: "arrow.left.arrow.right.circle.fill", tintColor: .blue))
        case .audio:
            break // Consumed inside TunerSession; never reaches the UI.
        default:
            // Newly-added nrsc5 events are forwarded to the sink but not
            // yet displayed in the UI.
            break
        }
    }
}
