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

import Combine
import Foundation
import nrsc5

public struct ProgramState {
    public var serviceName: String = ""

    public var title: String = ""
    public var artist: String = ""
    public var album: String = ""
    public var genre: String = ""

    public var showCover: Bool = false
    public var coverLotID: Int = -1
    public var programLotID: Int = -1

    public var bitsPerSecond: Int = 0
    public var crcErrors: Int = 0
}

private class BPSTracker {
    private var byteCount: Int = 0
    private var receiveCount: Int = 0
    public private(set) var bitsPerSecond: Int = 0

    func calculateBPS(size: Int) -> Bool {
        byteCount += size
        receiveCount += 1
        if receiveCount >= 64 || bitsPerSecond == 0 {
            bitsPerSecond =
                byteCount * 8 * Int(NRSC5_SAMPLE_RATE_AUDIO) / Int(NRSC5_AUDIO_FRAME_SAMPLES) / receiveCount
            byteCount = 0
            receiveCount = 0
            return true
        }
        return false
    }
}

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
    public var currentProgram: Int = 0

    public var isPlaying: Bool = false

    public var status: String = "Ready"

    public var stationName: String = ""
    public var stationSlogan: String = ""
    public var stationMessage: String = ""

    public var programStates: [ProgramState] = Array(repeating: .init(), count: 8)
    private var bpsTrackers: [BPSTracker] = Array(repeating: .init(), count: 8)

    public var merLower: Float = 0
    public var merUpper: Float = 0
    public var ber: Float = 0

    public var frequencyHz: Float? {
        let trimmed = frequencyMHz.trimmingCharacters(in: .whitespaces)
        guard let mhz = Double(trimmed), mhz > 0 else { return nil }
        return Float(mhz * 1_000_000)
    }

    public var traffic = TrafficMap()
    public var weather = WeatherMap()

    public var lotCache: [Int: LotFile] = [:]

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
        case .failed(let message):
            isPlaying = false
            status = "Error: \(message)"
        case .lostDevice:
            status = "Device lost"
            isPlaying = false
        case .syncAchieved(let freqOffset, let psmi, let pli, let hppi, let aabi, let rdbi):
            status = "Synchronized"
            appendLog(
                LogEvent(
                    title: "Synchronized",
                    description:
                        "Frequency Offset \(freqOffset.formatted(.number.precision(.fractionLength(0)))) Hz PSMI \(psmi) PLI \(pli) HPI \(hppi) AABI \(aabi) RDBI \(rdbi)",
                    systemImage: "checkmark.icloud.fill", tintColor: .blue))
        case .lostSync:
            status = "Lost sync"
        case .mer(let lower, let upper):
            merLower = lower
            merUpper = upper
        case .ber(let cber):
            ber = cber
        case .hdc(let program, let size, let flags):
            if flags & UInt(NRSC5_PKT_FLAGS_CRC_ERROR) != 0 {
                programStates[program].crcErrors += 1
            }
            if bpsTrackers[program].calculateBPS(size: size) {
                programStates[program].bitsPerSecond = bpsTrackers[program].bitsPerSecond
            }
        case .stationName(let name):
            stationName = name
            appendLog(
                LogEvent(
                    title: "Station Name", description: name, systemImage: "checkmark.icloud.fill",
                    tintColor: .blue))
        case .stationSlogan(let slogan):
            stationSlogan = slogan
            appendLog(
                LogEvent(
                    title: "Station Slogan", description: slogan,
                    systemImage: "checkmark.icloud.fill", tintColor: .blue))
        case .stationMessage(let message):
            stationMessage = message
            appendLog(
                LogEvent(
                    title: "Station Message", description: message,
                    systemImage: "checkmark.icloud.fill", tintColor: .blue))
        case .stationID(let countryCode, let fccFacilityID):
            appendLog(
                LogEvent(
                    title: "Station ID", description: "Country \(countryCode) ID \(fccFacilityID)",
                    systemImage: "checkmark.icloud.fill", tintColor: .blue))
        case .stationLocation(_, _, _):
            break
        case .id3(let program, let title, let artist, let album, let genre, let showCover, let lotID):
            programStates[program].title = title
            programStates[program].artist = artist
            programStates[program].album = album
            programStates[program].genre = genre
            programStates[program].showCover = showCover
            programStates[program].coverLotID = lotID
        case .lot(let file, let service, let component):
            let isImage = file.mime == NRSC5_MIME_JPEG || file.mime == NRSC5_MIME_PNG
            if isImage {
                lotCache[file.lotID] = file
            }
            let mimeName = nameForNRSC5MIMEType(file.mime)

            var compMimeName = "None"
            if let component {
                switch component {
                case .data(_, _, _, _, let mime):
                    compMimeName = nameForNRSC5MIMEType(mime)
                    if mime == NRSC5_MIME_PRIMARY_IMAGE && isImage {
                        lotCache[file.lotID] = file
                    } else if mime == NRSC5_MIME_STATION_LOGO && isImage {
                        lotCache[file.lotID] = file
                        if let ac = service?.audioComponent, case .audio(_, let port, _, _) = ac {
                            programStates[Int(port)].programLotID = file.lotID
                        }
                    } else if mime == NRSC5_MIME_TTN_STM_TRAFFIC {
                        if isImage {
                            traffic.processImageFile(name: file.name, data: file.data)
                        } else {
                            traffic.processConfigFile(data: file.data)
                        }
                    } else if mime == NRSC5_MIME_TTN_STM_WEATHER {
                        if isImage {
                            weather.processImageFile(name: file.name, data: file.data)
                        } else {
                            weather.processConfigFile(data: file.data)
                        }
                    }
                case .audio(_, _, _, let mime):
                    compMimeName = nameForNRSC5MIMEType(mime)
                case .unknown:
                    compMimeName = "Unknown"
                }
            }

            let serviceDesc =
                service.map { "type=\($0.type) #\($0.number) \($0.name) (\($0.components.count) components)" }
                ?? "None"

            let componentDesc: String
            if let component {
                switch component {
                case .data(let cid, let port, let serviceDataType, let aasType, _):
                    componentDesc = "data id=\(cid) port=\(port) sdt=\(serviceDataType) aas=\(aasType)"
                case .audio(let cid, let port, let programType, _):
                    componentDesc = "audio id=\(cid) port=\(port) programType=\(programType)"
                case .unknown(let cid):
                    componentDesc = "unknown id=\(cid)"
                }
            } else {
                componentDesc = "None"
            }

            appendLog(
                LogEvent(
                    title: "LOT File",
                    description:
                        "ID: \(file.lotID), File: \(file.name), Size: \(file.data.count), MIME: \(mimeName), Expires: \(file.expiry?.formatted(date: .numeric, time: .shortened) ?? "N/A"), Service: \(serviceDesc), Component: \(componentDesc), Component MIME: \(compMimeName)",
                    systemImage: "checkmark.icloud.fill", tintColor: .blue))
        case .hereImage(let image):
            let typeStr =
                switch image.type {
                case .traffic:
                    "Traffic"
                case .weather:
                    "Weather"
                case .unknown:
                    "Unknown"
                }
            appendLog(
                LogEvent(
                    title: "HERE Image",
                    description:
                        "File: \(image.name), Size: \(image.data.count), Type: \(typeStr), Sequence: \(image.sequence), N1: \(image.n1), N2: \(image.n2) Time: \(image.time?.formatted(date: .numeric, time: .shortened) ?? "N/A"), Bounds: \(image.boundingBox)",
                    systemImage: "photo", tintColor: .blue))
        case .agc(let gainDB, let peakDBFS, let isFinal):
            if isFinal {
                appendLog(
                    LogEvent(
                        title: "AGC",
                        description:
                            "Gain \(String(format: "%.1f", gainDB)) dB, Peak \(String(format: "%.1f", peakDBFS)) dBFS",
                        systemImage: "chart.line.uptrend.xyaxis", tintColor: .orange))
            }
        case .audioService(
            let program, let access, let type, let codecMode, let blendControl, let digitalAudioGain, let commonDelay,
            let latency):
            appendLog(
                LogEvent(
                    title: "Audio Service",
                    description:
                        "Program \(program), Access \(access), Type \(type), Codec \(codecMode), Blend \(blendControl), Gain \(digitalAudioGain), Delay \(commonDelay), Latency \(latency)",
                    systemImage: "speaker.wave.2.fill", tintColor: .blue))
        case .audioServiceDescriptor(let desc):
            appendLog(
                LogEvent(
                    title: "Audio Service Descriptor",
                    description:
                        "Program \(desc.program), Access \(desc.access), Type \(desc.type), SoundExp \(desc.soundExp)",
                    systemImage: "waveform",
                    tintColor: .blue))
        case .dataServiceDescriptor(let desc):
            appendLog(
                LogEvent(
                    title: "Data Service Descriptor",
                    description:
                        "Access \(desc.access), Type \(desc.type), MIME \(nameForNRSC5MIMEType(desc.mimeType))",
                    systemImage: "waveform",
                    tintColor: .purple))
        case .exciterInfo(
            let manufacturerID, let coreVersion, let coreStatus, let manufacturerVersion, let manufacturerStatus,
            let importerConnected):
            appendLog(
                LogEvent(
                    title: "Exciter Info",
                    description:
                        "Manufacturer \(manufacturerID), Core \(coreVersion.map { String($0) }.joined(separator: ".")) (\(coreStatus)), Manufacturer \(manufacturerVersion.map { String($0) }.joined(separator: ".")) (\(manufacturerStatus)), Importer \(importerConnected)",
                    systemImage: "antenna.radiowaves.left.and.right", tintColor: .green))
        case .importerInfo(
            let manufacturerID, let coreVersion, let coreStatus, let manufacturerVersion, let manufacturerStatus):
            appendLog(
                LogEvent(
                    title: "Importer Info",
                    description:
                        "Manufacturer \(manufacturerID), Core \(coreVersion.map { String($0) }.joined(separator: ".")) (\(coreStatus)), Manufacturer \(manufacturerVersion.map { String($0) }.joined(separator: ".")) (\(manufacturerStatus))",
                    systemImage: "arrow.down.circle.fill", tintColor: .green))
        case .leapSecondOffset(let pendingOffset, let currentOffset, let pendingALFN):
            appendLog(
                LogEvent(
                    title: "Leap Second Offset",
                    description: "Pending \(pendingOffset)s, Current \(currentOffset)s, ALFN \(pendingALFN)",
                    systemImage: "clock", tintColor: .orange))
        case .localTime(let utcOffsetMinutes, let dstRegional, let dstLocal, let dstSchedule):
            appendLog(
                LogEvent(
                    title: "Local Time",
                    description:
                        "UTC Offset \(utcOffsetMinutes) min, Regional DST \(dstRegional), Local DST \(dstLocal), Schedule \(dstSchedule)",
                    systemImage: "clock.badge.checkmark", tintColor: .orange))
        case .sig(let services):
            for service in services {
                if case .audio(_, let port, _, _) = service.audioComponent {
                    programStates[Int(port)].serviceName = service.name
                }
            }
            let list = services.map { "#\($0.number) \($0.name) (\($0.components.count) components)" }.joined(
                separator: ", ")
            appendLog(
                LogEvent(
                    title: "SIG", description: "Services: \(list)",
                    systemImage: "antenna.radiowaves.left.and.right", tintColor: .purple))
        case .audio:
            break  // Consumed inside TunerSession; never reaches the UI.
        default:
            // Newly-added nrsc5 events are forwarded to the sink but not
            // yet displayed in the UI.
            break
        }
    }
}

// MARK: - Logging helpers

@MainActor
extension TunerState {
    /// Accumulates an event count. Counts are batched and only flushed to the
    /// observable `eventCounts` while the log view is visible, to avoid SwiftUI
    /// redraws for every event.
    fileprivate func recordEventCount(_ name: String) {
        pendingEventCounts[name, default: 0] += 1
        scheduleLogFlushIfVisible()
    }

    /// Buffers a log entry. Entries are always captured, but are only flushed to
    /// the observable `logEntries` while the log view is visible.
    fileprivate func appendLog(_ event: LogEvent) {
        pendingLogEntries.append(event)
        scheduleLogFlushIfVisible()
    }

    fileprivate func scheduleLogFlushIfVisible() {
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

    fileprivate func flushPendingLogs() {
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
