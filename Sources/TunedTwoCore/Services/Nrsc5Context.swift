//
//  Nrsc5Context.swift
//  TunedTwo
//

import Foundation
import nrsc5

public protocol AudioSampleSink: AnyObject, Sendable {
    func feed(_ program: Int, _ samples: UnsafeBufferPointer<Int16>)
}

/// Bridge for the raw libnrsc5 session, handed to the library as the
/// callback's opaque pointer.
///
/// A plain (non-Sendable) class by design. The mutable C state below is
/// only ever touched from the session actor's methods and from this
/// class's own `deinit` (plain-class deinits have no Sendable
/// restrictions), which can never overlap: an in-flight actor method keeps
/// the session — and therefore this context — alive. The nrsc5 worker
/// thread only calls `emit`, which reads the immutable stream continuation.
/// This removes the need for locks or `@unchecked Sendable` entirely.
final class Nrsc5Context {
    /// The raw C session. The IQ file (if any) is owned by libnrsc5 once
    /// passed to `nrsc5_open_file` — `nrsc5_close` fcloses it.
    private var st: OpaquePointer?

    private let continuation: AsyncStream<TunerEvent>.Continuation
    let events: AsyncStream<TunerEvent>

    private let audioEventSink: AudioSampleSink

    init(audioEventSink: AudioSampleSink) {
        (events, continuation) = AsyncStream.makeStream(of: TunerEvent.self)
        self.audioEventSink = audioEventSink
    }

    /// RAII teardown: releasing the last reference to this context stops the
    /// callback, joins the library's worker thread, frees the C session, and
    /// finishes the event stream so the consumer task can wind down. So a
    /// dropped session can never leak the worker or the device.
    deinit {
        close()
        continuation.finish()
    }

    /// Called on the nrsc5 worker thread. Copies every byte out of the C
    /// event while its pointers are still valid, then yields a value.
    /// Reads no mutable state.
    func eventHandler(_ raw: nrsc5_event_t) {
        let event: TunerEvent?
        switch Int(raw.event) {
        case NRSC5_EVENT_LOST_DEVICE: event = .lostDevice
        case NRSC5_EVENT_SYNC:
            event = .syncAchieved(
                freqOffset: raw.sync.freq_offset, psmi: Int(raw.sync.psmi), pli: Int(raw.sync.pli),
                hppi: Int(raw.sync.hppi), aabi: Int(raw.sync.aabi), rdbi: Int(raw.sync.rdbi))
        case NRSC5_EVENT_LOST_SYNC: event = .lostSync
        case NRSC5_EVENT_MER: event = .mer(lower: raw.mer.lower, upper: raw.mer.upper)
        case NRSC5_EVENT_BER: event = .ber(cber: raw.ber.cber)
        case NRSC5_EVENT_HDC:
            // We have `data` available but don't copy it since we never use it.
            // Instead, just pass along the received byte count so bitrate can be calculated.
            event = .hdc(program: Int(raw.hdc.program), size: Int(raw.hdc.count), flags: UInt(raw.hdc.flags))
        case NRSC5_EVENT_IQ:
            // Omitting for now; this is a very low level raw data capture.
            event = nil
        case NRSC5_EVENT_AUDIO:
            // Directly route to the audio player, avoiding a hop through the AsyncStream.
            audioEventSink.feed(
                Int(raw.audio.program), UnsafeBufferPointer(start: raw.audio.data, count: raw.audio.count))
            event = nil
        case NRSC5_EVENT_ID3:
            event = .id3(
                program: Int(raw.id3.program),
                id3: TunerID3(
                    program: Int(raw.id3.program),
                    title: makeString(raw.id3.title),
                    artist: makeString(raw.id3.artist),
                    album: makeString(raw.id3.album),
                    genre: makeString(raw.id3.genre),
                    showCover: raw.id3.xhdr.param == 0,
                    lotID: Int(raw.id3.xhdr.lot)))
        case NRSC5_EVENT_SIG:
            event = .sig(services: copySigServices(raw.sig.services))
        case NRSC5_EVENT_LOT:
            event = .lot(
                file: TunerLotFile(
                    lotID: Int(raw.lot.lot),
                    mime: raw.lot.mime,
                    name: makeString(raw.lot.name),
                    data: copyBytes(raw.lot.data, count: Int(raw.lot.size)),
                    expiry: makeDate(raw.lot.expiry_utc)),
                service: raw.lot.service.map { copySigService($0.pointee) },
                component: raw.lot.component.map { copySigComponent($0.pointee) })
        case NRSC5_EVENT_LOT_HEADER:
            event = .lotHeader(
                lotID: Int(raw.lot.lot),
                mime: raw.lot.mime,
                name: makeString(raw.lot.name),
                size: Int(raw.lot.size),
                expiry: makeDate(raw.lot.expiry_utc),
                service: raw.lot.service.map { copySigService($0.pointee) },
                component: raw.lot.component.map { copySigComponent($0.pointee) })
        case NRSC5_EVENT_LOT_FRAGMENT:
            // Omitting for now; we don't currently need individual fragments.
            event = nil
        case NRSC5_EVENT_SIS:
            // Deprecated by nrsc5. The same information is delivered through
            // the NRSC5_EVENT_STATION_* and *_SERVICE_DESCRIPTOR events below,
            // so we intentionally do not emit a Swift event for this case.
            event = nil
        case NRSC5_EVENT_STREAM:
            // Omit `data` since we don't read it and can avoid unneeded allocations.
            event = .stream(
                seq: Int(raw.stream.seq),
                size: Int(raw.stream.size),
                service: raw.stream.service.map { copySigService($0.pointee) },
                component: raw.stream.component.map { copySigComponent($0.pointee) })
        case NRSC5_EVENT_PACKET:
            // Omit `data` since we don't read it and can avoid unneeded allocations.
            event = .packet(
                seq: Int(raw.packet.seq),
                size: Int(raw.packet.size),
                service: raw.packet.service.map { copySigService($0.pointee) },
                component: raw.packet.component.map { copySigComponent($0.pointee) })
        case NRSC5_EVENT_AUDIO_SERVICE:
            event = .audioService(
                program: Int(raw.audio_service.program),
                access: Int(raw.audio_service.access),
                type: Int(raw.audio_service.type),
                codecMode: Int(raw.audio_service.codec_mode),
                blendControl: Int(raw.audio_service.blend_control),
                digitalAudioGain: Int(raw.audio_service.digital_audio_gain),
                commonDelay: Int(raw.audio_service.common_delay),
                latency: Int(raw.audio_service.latency))
        case NRSC5_EVENT_STATION_ID:
            event = .stationID(
                countryCode: makeString(raw.station_id.country_code),
                fccFacilityID: Int(raw.station_id.fcc_facility_id))
        case NRSC5_EVENT_STATION_NAME:
            event = .stationName(makeString(raw.station_name.name))
        case NRSC5_EVENT_STATION_SLOGAN:
            event = .stationSlogan(makeString(raw.station_slogan.slogan))
        case NRSC5_EVENT_STATION_MESSAGE:
            event = .stationMessage(makeString(raw.station_message.message))
        case NRSC5_EVENT_STATION_LOCATION:
            event = .stationLocation(
                location: Location(
                    latitude: Double(raw.station_location.latitude),
                    longitude: Double(raw.station_location.longitude),
                    altitude: Double(raw.station_location.altitude)))
        case NRSC5_EVENT_AUDIO_SERVICE_DESCRIPTOR:
            event = .audioServiceDescriptor(
                TunerAudioServiceDescriptor(
                    program: Int(raw.asd.program),
                    access: Int(raw.asd.access),
                    type: Int(raw.asd.type),
                    soundExp: Int(raw.asd.sound_exp)
                )
            )
        case NRSC5_EVENT_DATA_SERVICE_DESCRIPTOR:
            event = .dataServiceDescriptor(
                TunerDataServiceDescriptor(
                    access: Int(raw.dsd.access),
                    type: Int(raw.dsd.type),
                    mimeType: raw.dsd.mime_type
                )
            )
        case NRSC5_EVENT_EMERGENCY_ALERT:
            event = .emergencyAlert(
                message: makeString(raw.emergency_alert.message),
                controlData: copyBytes(
                    raw.emergency_alert.control_data,
                    count: Int(raw.emergency_alert.control_data_length)),
                category1: Int(raw.emergency_alert.category1),
                category2: Int(raw.emergency_alert.category2),
                locationFormat: Int(raw.emergency_alert.location_format),
                locations: copyIntArray(
                    raw.emergency_alert.locations,
                    count: Int(raw.emergency_alert.num_locations)))
        case NRSC5_EVENT_HERE_IMAGE:
            let img = raw.here_image
            let imgType =
                img.image_type == NRSC5_HERE_IMAGE_TRAFFIC
                ? TunerHereImage.ImageType.traffic
                : img.image_type == NRSC5_HERE_IMAGE_WEATHER
                    ? TunerHereImage.ImageType.weather : TunerHereImage.ImageType.unknown
            event = .hereImage(
                image: TunerHereImage(
                    type: imgType,
                    name: makeString(img.name),
                    sequence: Int(img.seq),
                    n1: Int(img.n1),
                    n2: Int(img.n2),
                    time: makeDate(img.time_utc),
                    boundingBox: (
                        Location(latitude: img.latitude1, longitude: img.longitude1),
                        Location(latitude: img.latitude2, longitude: img.longitude2),
                    ),
                    data: copyBytes(img.data, count: Int(img.size)))
            )
        case NRSC5_EVENT_AGC:
            event = .agc(
                gainDB: raw.agc.gain_db,
                peakDBFS: raw.agc.peak_dbfs,
                isFinal: raw.agc.is_final != 0)
        case NRSC5_EVENT_EXCITER_INFO:
            event = .exciterInfo(
                manufacturerID: makeString(raw.exciter_info.manufacturer_id),
                coreVersion: copyCIntTuple(raw.exciter_info.core_version),
                coreStatus: Int(raw.exciter_info.core_status),
                manufacturerVersion: copyCIntTuple(raw.exciter_info.manufacturer_version),
                manufacturerStatus: Int(raw.exciter_info.manufacturer_status),
                importerConnected: raw.exciter_info.importer_connected != 0)
        case NRSC5_EVENT_IMPORTER_INFO:
            event = .importerInfo(
                manufacturerID: makeString(raw.importer_info.manufacturer_id),
                coreVersion: copyCIntTuple(raw.importer_info.core_version),
                coreStatus: Int(raw.importer_info.core_status),
                manufacturerVersion: copyCIntTuple(raw.importer_info.manufacturer_version),
                manufacturerStatus: Int(raw.importer_info.manufacturer_status))
        case NRSC5_EVENT_LEAP_SECOND_OFFSET:
            event = .leapSecondOffset(
                pendingOffset: Int(raw.leap_second_offset.pending_offset),
                currentOffset: Int(raw.leap_second_offset.current_offset),
                pendingALFN: UInt(raw.leap_second_offset.pending_alfn))
        case NRSC5_EVENT_LOCAL_TIME:
            event = .localTime(
                utcOffsetMinutes: Int(raw.local_time.utc_offset),
                dstRegional: raw.local_time.dst_regional != 0,
                dstLocal: raw.local_time.dst_local != 0,
                dstSchedule: Int(raw.local_time.dst_schedule))
        default: event = nil
        }
        guard let event else { return }
        continuation.yield(event)
    }

    /// Live retune. `nrsc5_set_frequency` may only be called while the
    /// worker is stopped, so stop demodulation, tune, and resume.
    func retune(frequencyHz: Float) -> Bool {
        guard let st else { return false }
        nrsc5_stop(st)
        let tuned = nrsc5_set_frequency(st, frequencyHz) == 0
        nrsc5_start(st)
        return tuned
    }

    /// Idempotent C teardown: unregisters the callback, joins the worker
    /// thread, and releases the C session (nrsc5_close fcloses the IQ file).
    /// Does *not* finish the event stream — that happens once, in `deinit`,
    /// so a session may stop and start again on the same stream.
    func close() {
        if let st {
            nrsc5_set_callback(st, nil, nil)
            nrsc5_stop(st)
            nrsc5_close(st)
        }
        st = nil
    }

    /// Installs a freshly opened C session, registers the callback, and
    /// starts demodulation. Context can outlive the C session.
    func activate(_ configuration: TunerConfiguration) throws {
        switch configuration.source {
        case .sampleFile:
            let path = try SampleFileProvider.sampleFilePath()
            guard let fp = fopen(path, "rb") else {
                throw TunerError.cannotOpenSample
            }
            // On success the file is owned by libnrsc5 (nrsc5_close fcloses it).
            guard nrsc5_open_file(&st, fp) == 0 else {
                fclose(fp)
                throw TunerError.nrsc5OpenFailed
            }

        case .rtlSDR(let deviceIndex):
            guard nrsc5_open(&st, Int32(deviceIndex)) == 0 else {
                throw TunerError.noSDR
            }
            guard nrsc5_set_mode(st, Int32(NRSC5_MODE_FM)) == 0 else {
                nrsc5_close(st)
                throw TunerError.modeSetFailed
            }
            guard let frequencyHz = configuration.frequencyHz else {
                nrsc5_close(st)
                throw TunerError.invalidFrequency
            }
            guard nrsc5_set_frequency(st, frequencyHz) == 0 else {
                nrsc5_close(st)
                throw TunerError.tuneFailed
            }
            nrsc5_set_auto_gain(st, 1)
        }

        nrsc5_set_callback(st, nrsc5EventCallback, Unmanaged.passUnretained(self).toOpaque())
        nrsc5_start(st)
    }

    public enum TunerError: LocalizedError {
        case cannotOpenSample
        case nrsc5OpenFailed
        case noSDR
        case modeSetFailed
        case invalidFrequency
        case tuneFailed

        public var errorDescription: String? {
            switch self {
            case .cannotOpenSample: return "Could not open the sample file."
            case .nrsc5OpenFailed: return "nrsc5 could not initialize the input."
            case .noSDR: return "No RTL-SDR found at index 0."
            case .modeSetFailed: return "Could not set FM/AM mode."
            case .invalidFrequency: return "The frequency is invalid."
            case .tuneFailed: return "Could not tune the SDR."
            }
        }
    }
}

// MARK: - C event copying helpers

extension Nrsc5Context {
    fileprivate func makeString(_ ptr: UnsafePointer<CChar>?) -> String {
        ptr.map { String(cString: $0) } ?? ""
    }

    fileprivate func makeDate(_ ptr: UnsafePointer<tm>?) -> Date? {
        guard let ptr else { return nil }
        let t = ptr.pointee
        var components = DateComponents()
        components.year = Int(t.tm_year) + 1900
        components.month = Int(t.tm_mon) + 1
        components.day = Int(t.tm_mday)
        components.hour = Int(t.tm_hour)
        components.minute = Int(t.tm_min)
        components.second = Int(t.tm_sec)
        return Calendar.utc.date(from: components)
    }

    fileprivate func copyBytes(_ ptr: UnsafePointer<UInt8>?, count: Int) -> Data {
        guard let ptr, count > 0 else { return Data() }
        return Data(buffer: UnsafeBufferPointer(start: ptr, count: count))
    }

    fileprivate func copyInt16(_ ptr: UnsafePointer<Int16>?, count: Int) -> [Int16] {
        guard let ptr, count > 0 else { return [] }
        return Array(UnsafeBufferPointer(start: ptr, count: count))
    }

    fileprivate func copyIntArray(_ ptr: UnsafePointer<Int32>?, count: Int) -> [Int] {
        guard let ptr, count > 0 else { return [] }
        return Array(UnsafeBufferPointer(start: ptr, count: count)).map(Int.init)
    }

    fileprivate func copyCIntTuple(_ tuple: some Any) -> [Int] {
        withUnsafeBytes(of: tuple) { ptr in
            ptr.bindMemory(to: Int32.self).map(Int.init)
        }
    }

    fileprivate func copySigService(_ s: nrsc5_sig_service_t) -> TunerSigService {
        TunerSigService(
            type: Int(s.type),
            number: Int(s.number),
            name: makeString(s.name),
            components: copySigComponents(s.components),
            audioComponent: s.audio_component.map { copySigComponent($0.pointee) }
        )
    }

    fileprivate func copySigServices(_ service: UnsafeMutablePointer<nrsc5_sig_service_t>?) -> [TunerSigService] {
        var result: [TunerSigService] = []
        var current = service
        while let s = current {
            result.append(copySigService(s.pointee))
            current = s.pointee.next
        }
        return result
    }

    fileprivate func copySigComponent(_ c: nrsc5_sig_component_t) -> TunerSigComponent {
        if Int(c.type) == NRSC5_SIG_SERVICE_DATA {
            return .data(
                id: Int(c.id),
                port: c.data.port,
                serviceDataType: c.data.service_data_type,
                aasType: Int(c.data.type),
                mime: c.data.mime)
        } else if Int(c.type) == NRSC5_SIG_SERVICE_AUDIO {
            return .audio(
                id: Int(c.id),
                port: c.audio.port,
                programType: Int(c.audio.type),
                mime: c.audio.mime)
        } else {
            return .unknown(id: Int(c.id))
        }
    }

    fileprivate func copySigComponents(_ component: UnsafeMutablePointer<nrsc5_sig_component_t>?)
        -> [TunerSigComponent]
    {
        var result: [TunerSigComponent] = []
        var current = component
        while let c = current {
            result.append(copySigComponent(c.pointee))
            current = c.pointee.next
        }
        return result
    }
}

/// C function pointers cannot capture Swift context; this trampoline forwards
/// to the context object passed as `opaque`.
private func nrsc5EventCallback(event: UnsafePointer<nrsc5_event_t>?, opaque: UnsafeMutableRawPointer?) {
    guard let event, let opaque else { return }
    Unmanaged<Nrsc5Context>.fromOpaque(opaque).takeUnretainedValue().eventHandler(event.pointee)
}
