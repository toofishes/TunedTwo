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
    case stationLocation(latitude: Float, longitude: Float, altitude: Int)

    // Audio / program metadata
    case id3(program: Int, title: String, artist: String, album: String, genre: String)
    case audioService(program: Int, access: Int, type: Int, codecMode: Int, blendControl: Int, digitalAudioGain: Int, commonDelay: Int, latency: Int)

    // Service Information Guide and descriptors
    case sig(services: [TunerSigService])
    case audioServiceDescriptor([TunerAudioServiceDescriptor])
    case dataServiceDescriptor([TunerDataServiceDescriptor])

    // Data / file delivery
    case hdc(program: Int, data: [UInt8], flags: Int)
    case stream(seq: Int, size: Int, data: [UInt8], service: TunerSigService?, component: TunerSigComponent?)
    case packet(seq: Int, size: Int, data: [UInt8], service: TunerSigService?, component: TunerSigComponent?)
    case lot(lotID: Int, size: Int, mime: UInt32, name: String, data: [UInt8], expiry: Date?, service: TunerSigService?, component: TunerSigComponent?)
    case lotHeader(lotID: Int, size: Int, mime: UInt32, name: String, expiry: Date?, service: TunerSigService?, component: TunerSigComponent?)
    case hereImage(type: Int, seq: Int, n1: Int, n2: Int, timeUTC: Date?, boundingBox: TunerBoundingBox, name: String, data: [UInt8])

    // Alerts and infrastructure info
    case emergencyAlert(message: String, controlData: [UInt8], category1: Int, category2: Int, locationFormat: Int, locations: [Int])
    case exciterInfo(manufacturerID: String, coreVersion: [Int], coreStatus: Int, manufacturerVersion: [Int], manufacturerStatus: Int, importerConnected: Bool)
    case importerInfo(manufacturerID: String, coreVersion: [Int], coreStatus: Int, manufacturerVersion: [Int], manufacturerStatus: Int)
    case leapSecondOffset(pendingOffset: Int, currentOffset: Int, pendingALFN: UInt)
    case localTime(utcOffsetMinutes: Int, dstRegional: Bool, dstLocal: Bool, dstSchedule: Int)

    // Decoded audio (consumed by the session, forwarded to the audio actor)
    case audio(program: Int, samples: [Int16])
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

/// Geographic bounding box for HERE traffic/weather images.
public struct TunerBoundingBox: Sendable {
    public let latitude1: Float
    public let longitude1: Float
    public let latitude2: Float
    public let longitude2: Float
}

/// Receives tuner events. Conformers run on the MainActor (typically
/// `TunerState`); the session only ever reaches them through `await`, so
/// the nrsc5 worker thread never touches UI-owned state.
public protocol TunerEventSink: AnyObject, Sendable {
    func tunerSessionDidEmit(_ event: TunerEvent) async
}
