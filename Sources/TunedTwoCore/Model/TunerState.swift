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

    /// Whether the Logs tab is currently on screen.
    /// Used to skip log-entry and event-count UI updates when the log view is hidden.
    public var isLogsVisible: Bool = false {
        didSet {
            if isLogsVisible {
                flushPendingLogs()
            }
        }
    }

    /// Counts accumulated since the last public `eventCounts` update.
    private var pendingEventCounts: [String: Int] = [:]
    /// Log entries accumulated since the last public `logEntries` update.
    private var pendingLogEntries: [LogEvent] = []
    /// Outstanding timer that will flush pending counts/logs to the observable properties.
    private var logFlushTask: Task<Void, Never>?

    public init() {}
}

// MARK: - TunerEventSink

extension TunerState: TunerEventSink {
    public func tunerSessionDidEmit(_ event: TunerEvent) async {
        recordEventCount(event.caseName)
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
        case let .syncAchieved(freqOffset, psmi, pli, hppi, aabi, rdbi):
            status = "Synchronized"
            appendLog(LogEvent(timestamp: Date(), title: "Synchronized", description: "Frequency Offset \(freqOffset.formatted(.number.precision(.fractionLength(0)))) Hz PSMI \(psmi) PLI \(pli) HPI \(hppi) AABI \(aabi) RDBI \(rdbi)", systemImage: "checkmark.icloud.fill", tintColor: .blue))
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
            appendLog(LogEvent(timestamp: Date(), title: "Station Name", description: name, systemImage: "checkmark.icloud.fill", tintColor: .blue))
        case let .stationSlogan(slogan):
            stationSlogan = slogan
            appendLog(LogEvent(timestamp: Date(), title: "Station Slogan", description: slogan, systemImage: "checkmark.icloud.fill", tintColor: .blue))
        case let .stationMessage(message):
            stationMessage = message
            appendLog(LogEvent(timestamp: Date(), title: "Station Message", description: message, systemImage: "checkmark.icloud.fill", tintColor: .blue))
        case let .stationID(countryCode, fccFacilityID):
            appendLog(LogEvent(timestamp: Date(), title: "Station ID", description: "Country \(countryCode) ID \(fccFacilityID)", systemImage: "checkmark.icloud.fill", tintColor: .blue))
        case let .stationLocation(_, _, _):
            break
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

            appendLog(LogEvent(timestamp: Date(), title: "LOT File", description: "ID: \(id), File: \(name), Size: \(data.count), MIME: \(mimeName), Service: \(serviceDesc), Component: \(componentDesc), Component MIME: \(compMimeName)", systemImage: "checkmark.icloud.fill", tintColor: .blue))
        case let .agc(gainDB, peakDBFS, isFinal):
            appendLog(LogEvent(timestamp: Date(), title: "AGC", description: "Gain \(String(format: "%.1f", gainDB)) dB, Peak \(String(format: "%.1f", peakDBFS)) dBFS, Final \(isFinal)", systemImage: "chart.line.uptrend.xyaxis", tintColor: .orange))
        case let .audioService(program, access, type, codecMode, blendControl, digitalAudioGain, commonDelay, latency):
            appendLog(LogEvent(timestamp: Date(), title: "Audio Service", description: "Program \(program), Access \(access), Type \(type), Codec \(codecMode), Blend \(blendControl), Gain \(digitalAudioGain), Delay \(commonDelay), Latency \(latency)", systemImage: "speaker.wave.2.fill", tintColor: .blue))
        case let .audioServiceDescriptor(descriptors):
            let list = descriptors.map { "Program \($0.program), Access \($0.access), Type \($0.type), SoundExp \($0.soundExp)" }.joined(separator: "; ")
            appendLog(LogEvent(timestamp: Date(), title: "Audio Service Descriptor", description: list, systemImage: "waveform", tintColor: .blue))
        case let .dataServiceDescriptor(descriptors):
            let list = descriptors.map { "Access \($0.access), Type \($0.type), MIME \(nameForNRSC5MIMEType($0.mimeType))" }.joined(separator: "; ")
            appendLog(LogEvent(timestamp: Date(), title: "Data Service Descriptor", description: list, systemImage: "waveform", tintColor: .purple))
        case let .exciterInfo(manufacturerID, coreVersion, coreStatus, manufacturerVersion, manufacturerStatus, importerConnected):
            appendLog(LogEvent(timestamp: Date(), title: "Exciter Info", description: "Manufacturer \(manufacturerID), Core \(coreVersion.map { String($0) }.joined(separator: ".")) (\(coreStatus)), Manufacturer \(manufacturerVersion.map { String($0) }.joined(separator: ".")) (\(manufacturerStatus)), Importer \(importerConnected)", systemImage: "antenna.radiowaves.left.and.right", tintColor: .green))
        case let .importerInfo(manufacturerID, coreVersion, coreStatus, manufacturerVersion, manufacturerStatus):
            appendLog(LogEvent(timestamp: Date(), title: "Importer Info", description: "Manufacturer \(manufacturerID), Core \(coreVersion.map { String($0) }.joined(separator: ".")) (\(coreStatus)), Manufacturer \(manufacturerVersion.map { String($0) }.joined(separator: ".")) (\(manufacturerStatus))", systemImage: "arrow.down.circle.fill", tintColor: .green))
        case let .leapSecondOffset(pendingOffset, currentOffset, pendingALFN):
            appendLog(LogEvent(timestamp: Date(), title: "Leap Second Offset", description: "Pending \(pendingOffset)s, Current \(currentOffset)s, ALFN \(pendingALFN)", systemImage: "clock", tintColor: .orange))
        case let .localTime(utcOffsetMinutes, dstRegional, dstLocal, dstSchedule):
            appendLog(LogEvent(timestamp: Date(), title: "Local Time", description: "UTC Offset \(utcOffsetMinutes) min, Regional DST \(dstRegional), Local DST \(dstLocal), Schedule \(dstSchedule)", systemImage: "clock.badge.checkmark", tintColor: .orange))
        case let .sig(services):
            let list = services.map { "#\($0.number) \($0.name) (\($0.components.count) components)" }.joined(separator: ", ")
            appendLog(LogEvent(timestamp: Date(), title: "SIG", description: "Services: \(list)", systemImage: "antenna.radiowaves.left.and.right", tintColor: .purple))
        case .audio:
            break // Consumed inside TunerSession; never reaches the UI.
        default:
            // Newly-added nrsc5 events are forwarded to the sink but not
            // yet displayed in the UI.
            break
        }
    }
}

// MARK: - Logging helpers

@MainActor
private extension TunerState {
    /// Accumulates an event count. Counts are batched and only flushed to the
    /// observable `eventCounts` while the log view is visible, to avoid SwiftUI
    /// redraws for every event.
    func recordEventCount(_ name: String) {
        pendingEventCounts[name, default: 0] += 1
        scheduleLogFlushIfVisible()
    }

    /// Buffers a log entry. Entries are always captured, but are only flushed to
    /// the observable `logEntries` while the log view is visible.
    func appendLog(_ event: LogEvent) {
        pendingLogEntries.append(event)
        scheduleLogFlushIfVisible()
    }

    func scheduleLogFlushIfVisible() {
        guard isLogsVisible, logFlushTask == nil else { return }
        logFlushTask = Task { @MainActor [self] in
            defer { logFlushTask = nil }
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            flushPendingLogs()
        }
    }

    func flushPendingLogs() {
        guard isLogsVisible else { return }

        if !pendingEventCounts.isEmpty {
            for (key, value) in pendingEventCounts {
                eventCounts[key, default: 0] += value
            }
            pendingEventCounts.removeAll()
        }

        if !pendingLogEntries.isEmpty {
            logEntries.append(contentsOf: pendingLogEntries)
            pendingLogEntries.removeAll()
        }
    }
}
