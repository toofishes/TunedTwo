//
//  TunerSession.swift
//  TunedTwo
//
//  Wraps libnrsc5 behind a Swift actor.
//
//  Concurrency model:
//  - All libnrsc5 API calls are confined to this actor. The UI layer only
//    reaches it through async calls with Sendable values.
//  - The nrsc5 C callback runs on the library's worker thread. Its only job
//    is to copy each C event into a Sendable `TunerEvent` value (while the
//    C pointers are still valid) and yield it into an `AsyncStream`; it
//    never touches mutable Swift state.
//  - A single long-lived consumer task drains the stream into the actor.
//    It holds the session weakly so the session can deinit while it runs:
//    the context tears the C session down, finishes the stream, the loop
//    ends, and every resource (worker thread, C session, audio) is
//    reclaimed — no leaks, no retain cycles.
//  - UI state is only ever touched via the awaited `TunerEventSink`
//    (MainActor), held weakly.
//

import Foundation
import AVFoundation
import os

/// Configuration snapshot taken on the MainActor when playback starts, so
/// the session never reads UI-owned state directly.
struct TunerConfiguration: Sendable {
    enum Source: Sendable {
        case rtlSDR(deviceIndex: Int)
        case sampleFile
    }

    let source: Source
    let frequencyHz: Float?
    let program: Int
}

// MARK: - C bridge

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
private final class Nrsc5Context {
    /// The raw C session. The IQ file (if any) is owned by libnrsc5 once
    /// passed to `nrsc5_open_file` — `nrsc5_close` fcloses it.
    private var st: OpaquePointer?

    private let continuation: AsyncStream<TunerEvent>.Continuation
    let events: AsyncStream<TunerEvent>

    init() {
        (events, continuation) = AsyncStream.makeStream(of: TunerEvent.self)
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
    func emit(_ raw: nrsc5_event_t) {
        let event: TunerEvent?
        switch Int(raw.event) {
        case NRSC5_EVENT_LOST_DEVICE: event = .lostDevice
        case NRSC5_EVENT_SYNC: event = .syncAchieved
        case NRSC5_EVENT_LOST_SYNC: event = .lostSync
        case NRSC5_EVENT_MER: event = .mer(lower: raw.mer.lower, upper: raw.mer.upper)
        case NRSC5_EVENT_BER: event = .ber(cber: raw.ber.cber)
        case NRSC5_EVENT_AUDIO:
            guard let data = raw.audio.data else { event = nil; return }
            let count = Int(raw.audio.count)
            event = .audio(program: Int(raw.audio.program),
                           samples: Array(UnsafeBufferPointer(start: data, count: count)))
        case NRSC5_EVENT_ID3:
            event = .id3(program: Int(raw.id3.program),
                         title: raw.id3.title.map { String(cString: $0) } ?? "",
                         artist: raw.id3.artist.map { String(cString: $0) } ?? "",
                         album: raw.id3.album.map { String(cString: $0) } ?? "")
        case NRSC5_EVENT_STATION_NAME:
            event = .stationName(raw.station_name.name.map { String(cString: $0) } ?? "")
        case NRSC5_EVENT_STATION_SLOGAN:
            event = .stationSlogan(raw.station_slogan.slogan.map { String(cString: $0) } ?? "")
        default: event = nil
        }
        guard let event else { return }
        continuation.yield(event)
    }

    /// Installs a freshly opened C session, registers the callback, and
    /// starts demodulation.
    func activate(st: OpaquePointer) {
        self.st = st
        // The context outlives the C session: close() unregisters the
        // callback and joins the worker thread before the context can be
        // released.
        nrsc5_set_callback(st, nrsc5EventCallback, Unmanaged.passUnretained(self).toOpaque())
        nrsc5_start(st)
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
}

/// C function pointers cannot capture Swift context; this trampoline forwards
/// to the context object passed as `opaque`.
private func nrsc5EventCallback(event: UnsafePointer<nrsc5_event_t>?, opaque: UnsafeMutableRawPointer?) {
    guard let event, let opaque else { return }
    Unmanaged<Nrsc5Context>.fromOpaque(opaque).takeUnretainedValue().emit(event.pointee)
}

// MARK: - Session

actor TunerSession {
    private static let logger = Logger(subsystem: "io.tunedtwo.TunedTwo", category: "tuner")

    private weak var sink: TunerEventSink?
    private let audioPlayer: AudioPlayer
    private let context = Nrsc5Context()

    /// Client-side program filter. nrsc5 emits all programs; we only render
    /// the selected one. Plain actor state — no lock needed.
    private var currentProgram: Int
    private var isRunning = false

    init(sink: TunerEventSink) throws {
        self.sink = sink
        self.audioPlayer = try AudioPlayer()
        self.currentProgram = 0

        // Drain C callback events into the actor. The task holds the session
        // weakly so a released session can deinit while it runs; the context's
        // deinit finishes the stream, which ends this loop and lets every
        // resource be reclaimed.
        let events = context.events
        Task { [weak self, events] in
            for await event in events {
                await self?.handle(event)
            }
        }
    }

    deinit {
        // No C access here: releasing `context` performs the teardown
        // (its deinit unregisters the callback, joins the worker thread,
        // and closes the session), so even a running session that is
        // dropped without stop() cannot leak the worker or the device.
        // The audio player is an actor (Sendable), so its reference can be
        // captured here; the task keeps it alive long enough to stop the
        // engine, which must not happen on an arbitrary deinit thread.
        let player = audioPlayer
        Task { await player.stop() }
    }

    // MARK: - Public control (called from the UI, asynchronous by design)

    func start(_ configuration: TunerConfiguration) async {
        currentProgram = configuration.program
        context.close() // idempotent; every start gets a fresh C session

        do {
            let st = try Self.openRawSession(configuration)
            context.activate(st: st)
            try await audioPlayer.start()
            isRunning = true
            Self.logger.debug("Session started")
            await sink?.tunerSessionDidEmit(.started)
        } catch {
            context.close()
            await audioPlayer.stop()
            await sink?.tunerSessionDidEmit(.failed(message: error.localizedDescription))
        }
    }

    func stop() async {
        isRunning = false
        context.close()
        await audioPlayer.stop()
        await sink?.tunerSessionDidEmit(.stopped)
    }

    /// Switches the decoded program (HD1–HD8) and flushes queued audio so the
    /// old program does not bleed into the new one.
    func setProgram(_ program: Int) async {
        currentProgram = program
        await audioPlayer.flush()
    }

    /// Live retune while playing (RTL-SDR only).
    func retune(frequencyHz: Float) async {
        guard context.retune(frequencyHz: frequencyHz) else {
            await sink?.tunerSessionDidEmit(.failed(message: "Could not tune to the requested frequency."))
            return
        }
        await audioPlayer.flush()
    }

    // MARK: - Event handling (actor-isolated, fed by the event stream)

    private func handle(_ event: TunerEvent) async {
        switch event {
        case .audio(let program, let samples):
            guard isRunning, program == currentProgram else { return }
            await audioPlayer.feed(samples)

        case .id3(let program, let title, let artist, let album):
            guard program == currentProgram else { return }
            await sink?.tunerSessionDidEmit(event)

        default:
            // Station-level events (sync, metrics, station name/slogan,
            // device loss) pass straight through to the UI.
            await sink?.tunerSessionDidEmit(event)
        }
    }

    // MARK: - C session lifecycle

    /// Opens a new libnrsc5 session for the given configuration. Pure C
    /// calls on a not-yet-shared handle, so this is safe off-actor.
    private static func openRawSession(_ configuration: TunerConfiguration) throws -> OpaquePointer {
        var st: OpaquePointer?

        switch configuration.source {
        case .sampleFile:
            let path = try SampleFileProvider.sampleFilePath()
            Self.logger.debug("Opening sample file: \(path, privacy: .public)")
            guard let fp = fopen(path, "rb") else {
                throw TunerError.cannotOpenSample
            }
            // On success the file is owned by libnrsc5 (nrsc5_close fcloses it).
            guard nrsc5_open_file(&st, fp) == 0 else {
                fclose(fp)
                throw TunerError.nrsc5OpenFailed
            }
            return st!

        case .rtlSDR(let deviceIndex):
            guard nrsc5_open(&st, Int32(deviceIndex)) == 0 else {
                throw TunerError.noSDR
            }
            let handle = st!
            guard nrsc5_set_mode(handle, Int32(NRSC5_MODE_FM)) == 0 else {
                nrsc5_close(handle)
                throw TunerError.modeSetFailed
            }
            guard let frequencyHz = configuration.frequencyHz else {
                nrsc5_close(handle)
                throw TunerError.invalidFrequency
            }
            guard nrsc5_set_frequency(handle, frequencyHz) == 0 else {
                nrsc5_close(handle)
                throw TunerError.tuneFailed
            }
            nrsc5_set_auto_gain(handle, 1)
            return handle
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
