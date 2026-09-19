//
//  TunerEvent.swift
//  TunedTwo
//
//  The Sendable message vocabulary shared by the tuner session (background)
//  and the UI layer (MainActor).
//

import Foundation

/// A single message flowing out of the tuner pipeline.
///
/// Events originating from the nrsc5 callback are converted into values of
/// this enum (copying every byte while the C pointers are still valid) before
/// they cross any isolation boundary. `audio` events are consumed inside
/// `TunerSession` and never reach the UI; everything else is forwarded to
/// the ``TunerEventSink``.
public enum TunerEvent: Sendable {
    // Lifecycle (emitted by the session itself, not by nrsc5)
    case started
    case stopped
    case failed(message: String)

    // Demodulator state
    case syncAchieved(freqOffset: Float, psmi: Int, pli: Int, hppi: Int, aabi: Int, rdbi: Int)
    case lostSync
    case lostDevice

    // Signal metrics
    case mer(lower: Float, upper: Float)
    case ber(cber: Float)
    case agc(gainDB: Float, peakDBFS: Float, isFinal: Bool)

    // Station metadata
    case stationName(String)
    case stationSlogan(String)
    case stationMessage(String)
    case stationID(countryCode: String, fccFacilityID: Int)
    case stationLocation(location: Location)

    // Audio / program metadata
    case id3(program: Int, id3: TunerID3)
    case audioService(
        program: Int, access: Int, type: Int, codecMode: Int, blendControl: Int, digitalAudioGain: Int,
        commonDelay: Int, latency: Int)

    // Service Information Guide and descriptors
    case sig(services: [TunerSigService])
    case audioServiceDescriptor(TunerAudioServiceDescriptor)
    case dataServiceDescriptor(TunerDataServiceDescriptor)

    // Data / file delivery
    case hdc(program: Int, size: Int, flags: UInt)
    case stream(seq: Int, size: Int, service: TunerSigService?, component: TunerSigComponent?)
    case packet(seq: Int, size: Int, service: TunerSigService?, component: TunerSigComponent?)
    case lot(file: TunerLotFile, service: TunerSigService?, component: TunerSigComponent?)
    case lotHeader(
        lotID: Int, mime: UInt32, name: String, size: Int, expiry: Date?, service: TunerSigService?,
        component: TunerSigComponent?)
    case hereImage(image: TunerHereImage)

    // Alerts and infrastructure info
    case emergencyAlert(
        message: String, controlData: Data, category1: Int, category2: Int, locationFormat: Int, locations: [Int])
    case exciterInfo(
        manufacturerID: String, coreVersion: [Int], coreStatus: Int, manufacturerVersion: [Int],
        manufacturerStatus: Int, importerConnected: Bool)
    case importerInfo(
        manufacturerID: String, coreVersion: [Int], coreStatus: Int, manufacturerVersion: [Int],
        manufacturerStatus: Int)
    case leapSecondOffset(pendingOffset: Int, currentOffset: Int, pendingALFN: UInt)
    case localTime(utcOffsetMinutes: Int, dstRegional: Bool, dstLocal: Bool, dstSchedule: Int)

    // Decoded audio (consumed by the session, forwarded to the audio actor)
    case audio(program: Int, samples: [Int16], flags: UInt)
}

extension TunerEvent {
    /// The enum case name without associated values, suitable for counters and logging.
    public var caseName: String {
        switch self {
        case .started: return "started"
        case .stopped: return "stopped"
        case .failed: return "failed"
        case .syncAchieved: return "syncAchieved"
        case .lostSync: return "lostSync"
        case .lostDevice: return "lostDevice"
        case .mer: return "mer"
        case .ber: return "ber"
        case .agc: return "agc"
        case .stationName: return "stationName"
        case .stationSlogan: return "stationSlogan"
        case .stationMessage: return "stationMessage"
        case .stationID: return "stationID"
        case .stationLocation: return "stationLocation"
        case .id3: return "id3"
        case .audioService: return "audioService"
        case .sig: return "sig"
        case .audioServiceDescriptor: return "audioServiceDescriptor"
        case .dataServiceDescriptor: return "dataServiceDescriptor"
        case .hdc: return "hdc"
        case .stream: return "stream"
        case .packet: return "packet"
        case .lot: return "lot"
        case .lotHeader: return "lotHeader"
        case .hereImage: return "hereImage"
        case .emergencyAlert: return "emergencyAlert"
        case .exciterInfo: return "exciterInfo"
        case .importerInfo: return "importerInfo"
        case .leapSecondOffset: return "leapSecondOffset"
        case .localTime: return "localTime"
        case .audio: return "audio"
        }
    }
}

public struct TunerID3: Sendable {
    public let program: Int
    public let title: String
    public let artist: String
    public let album: String
    public let genre: String
    public let showCover: Bool
    public let lotID: Int
}

public struct TunerLotFile: Sendable {
    public let lotID: Int
    public let mime: UInt32
    public let name: String
    public let data: Data
    public let expiry: Date?
}

public struct TunerHereImage: Sendable {
    enum ImageType {
        case traffic
        case weather
        case unknown
    }

    var type: ImageType
    var name: String
    var sequence: Int
    var n1: Int
    var n2: Int
    var time: Date?
    var boundingBox: (Location, Location)
    var data: Data
}

/// A service entry from an NRSC5 SIG (Service Information Guide) table.
public struct TunerSigService: Sendable {
    public let type: Int
    public let number: Int
    public let name: String
    public let components: [TunerSigComponent]
    public let audioComponent: TunerSigComponent?
}

/// A component belonging to a SIG service.
public enum TunerSigComponent: Sendable {
    case data(id: Int, port: UInt16, serviceDataType: UInt16, aasType: Int, mime: UInt32)
    case audio(id: Int, port: UInt8, programType: Int, mime: UInt32)
    case unknown(id: Int)
}

/// SIS audio service descriptor (ASD).
public struct TunerAudioServiceDescriptor: Sendable {
    public let program: Int
    public let access: Int
    public let type: Int
    public let soundExp: Int
}

/// SIS data service descriptor (DSD).
public struct TunerDataServiceDescriptor: Sendable {
    public let access: Int
    public let type: Int
    public let mimeType: UInt32
}

/// Receives tuner events. Conformers run on the MainActor (typically
/// `TunerState`); the session only ever reaches them through `await`, so
/// the nrsc5 worker thread never touches UI-owned state.
public protocol TunerEventSink: AnyObject, Sendable {
    func tunerSessionDidEmit(_ event: TunerEvent) async
}
