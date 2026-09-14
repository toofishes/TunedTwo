//
//  TunerSession.swift
//  TunedTwo
//
//  Wraps libnrsc5 and feeds the native audio pipeline.
//

import Foundation
import AVFoundation

/// C function pointer cannot capture Swift state, so this top-level trampoline
/// forwards events into the active session.
private func nrsc5EventCallback(event: UnsafePointer<nrsc5_event_t>?, opaque: UnsafeMutableRawPointer?) {
    guard let event = event, let opaque = opaque else { return }
    let session = Unmanaged<TunerSession>.fromOpaque(opaque).takeUnretainedValue()
    session.handle(event.pointee)
}

final class TunerSession {
    private let state: TunerState
    private let audioPlayer: AudioPlayer
    private let sessionQueue = DispatchQueue(label: "io.tunedtwo.nrsc5", qos: .userInitiated)

    private var st: OpaquePointer?
    private var fileHandle: UnsafeMutablePointer<FILE>?

    /// Client-side program filter. nrsc5 emits all programs; we only render the selected one.
    private var currentProgram: UInt32 = 0

    init(state: TunerState) throws {
        self.state = state
        self.audioPlayer = try AudioPlayer()
        self.currentProgram = UInt32(state.program)
    }

    deinit {
        stop()
    }

    // MARK: - Public control

    func start() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.currentProgram = UInt32(self.state.program)
            do {
                try self.startSession()
                try self.audioPlayer.start()
                DispatchQueue.main.async {
                    self.state.isPlaying = true
                    self.state.status = "Playing"
                }
            } catch {
                fputs("[TunerSession] start error: \(error.localizedDescription)\n", stderr)
                DispatchQueue.main.async {
                    self.state.isPlaying = false
                    self.state.status = "Error: \(error.localizedDescription)"
                }
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.closeSession()
            DispatchQueue.main.async {
                self.state.isPlaying = false
                self.state.status = "Stopped"
            }
        }
    }

    func programChanged(to program: Int) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.currentProgram = UInt32(program)
            // Flush queued audio so the old program doesn't bleed into the new one.
            self.audioPlayer.reset()
        }
    }

    // MARK: - Session lifecycle

    private func startSession() throws {
        closeSession()

        var newSt: OpaquePointer?

        switch state.source {
        case .sampleFile:
            let path = try SampleFileProvider.shared.sampleFilePath()
            fputs("[TunerSession] opening sample file: \(path)\n", stderr)
            guard let fp = fopen(path, "rb") else {
                throw TunerError.cannotOpenSample
            }
            self.fileHandle = fp
            guard nrsc5_open_file(&newSt, fp) == 0 else {
                fclose(fp)
                self.fileHandle = nil
                throw TunerError.nrsc5OpenFailed
            }

        case .rtlSDR:
            guard nrsc5_open(&newSt, 0) == 0 else {
                throw TunerError.noSDR
            }
            guard nrsc5_set_mode(newSt, Int32(NRSC5_MODE_FM)) == 0 else {
                nrsc5_close(newSt)
                throw TunerError.modeSetFailed
            }
            guard let freqHz = state.frequencyHz else {
                nrsc5_close(newSt)
                throw TunerError.invalidFrequency
            }
            guard nrsc5_set_frequency(newSt, freqHz) == 0 else {
                nrsc5_close(newSt)
                throw TunerError.tuneFailed
            }
            nrsc5_set_auto_gain(newSt, 1)
        }

        self.st = newSt
        let opaque = Unmanaged.passUnretained(self).toOpaque()
        nrsc5_set_callback(newSt, nrsc5EventCallback, opaque)
        nrsc5_start(newSt)
    }

    private func closeSession() {
        if let st = st {
            nrsc5_stop(st)
            nrsc5_close(st)
        }
        st = nil
        fileHandle = nil
        audioPlayer.stop()
    }

    // MARK: - Event handling (called from nrsc5 worker thread)

    func handle(_ event: nrsc5_event_t) {
        switch Int(event.event) {
        case NRSC5_EVENT_SYNC:
            fputs("[TunerSession] sync achieved\n", stderr)
            DispatchQueue.main.async {
                self.state.status = "Synchronized"
            }

        case NRSC5_EVENT_LOST_SYNC:
            DispatchQueue.main.async {
                self.state.status = "Lost sync"
            }

        case NRSC5_EVENT_MER:
            DispatchQueue.main.async {
                self.state.merLower = event.mer.lower
                self.state.merUpper = event.mer.upper
            }

        case NRSC5_EVENT_BER:
            DispatchQueue.main.async {
                self.state.ber = event.ber.cber
            }

        case NRSC5_EVENT_AUDIO:
            guard event.audio.program == currentProgram,
                  let data = event.audio.data else { return }
            let count = Int(event.audio.count)
            let samples = Array(UnsafeBufferPointer(start: data, count: count))
            audioPlayer.feed(samples)

        case NRSC5_EVENT_ID3:
            // Copy C strings immediately; the event pointers are only valid during the callback.
            let title = event.id3.title.map { String(cString: $0) } ?? ""
            let artist = event.id3.artist.map { String(cString: $0) } ?? ""
            let album = event.id3.album.map { String(cString: $0) } ?? ""
            fputs("[TunerSession] ID3: \(title)\n", stderr)
            DispatchQueue.main.async {
                self.state.title = title
                self.state.artist = artist
                self.state.album = album
            }

        case NRSC5_EVENT_STATION_NAME:
            let name = event.station_name.name.map { String(cString: $0) } ?? ""
            fputs("[TunerSession] station name: \(name)\n", stderr)
            DispatchQueue.main.async {
                self.state.stationName = name
            }

        case NRSC5_EVENT_STATION_SLOGAN:
            let slogan = event.station_slogan.slogan.map { String(cString: $0) } ?? ""
            DispatchQueue.main.async {
                self.state.stationSlogan = slogan
            }

        case NRSC5_EVENT_LOST_DEVICE:
            DispatchQueue.main.async {
                self.state.status = "Device lost"
                self.state.isPlaying = false
            }

        default:
            break
        }
    }

    enum TunerError: LocalizedError {
        case cannotOpenSample
        case nrsc5OpenFailed
        case noSDR
        case modeSetFailed
        case invalidFrequency
        case tuneFailed

        var errorDescription: String? {
            switch self {
            case .cannotOpenSample: return "Could not open the sample file."
            case .nrsc5OpenFailed:  return "nrsc5 could not initialize the input."
            case .noSDR:            return "No RTL-SDR found at index 0."
            case .modeSetFailed:    return "Could not set FM/AM mode."
            case .invalidFrequency: return "The frequency is invalid."
            case .tuneFailed:       return "Could not tune the SDR."
            }
        }
    }
}
