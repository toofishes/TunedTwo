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

import AVFoundation
import Foundation
import nrsc5
import os

/// Configuration snapshot taken on the MainActor when playback starts, so
/// the session never reads UI-owned state directly.
public struct TunerConfiguration: Sendable {
    public enum Source: Sendable {
        case rtlSDR(deviceIndex: Int)
        case sampleFile
    }

    public let source: Source
    public let frequencyHz: Float?
    public let program: Int

    public init(source: Source, frequencyHz: Float?, program: Int) {
        self.source = source
        self.frequencyHz = frequencyHz
        self.program = program
    }
}

// MARK: - Session

public actor TunerSession {
    private weak var sink: TunerEventSink?
    private let audioPlayer: AudioPlayer
    private let context: Nrsc5Context

    /// Client-side program filter. nrsc5 emits all programs; we only render
    /// the selected one. Plain actor state — no lock needed.
    private var isRunning = false

    public init(sink: TunerEventSink) throws {
        self.sink = sink
        self.audioPlayer = try AudioPlayer()
        self.context = Nrsc5Context(audioEventSink: audioPlayer)

        // Drain C callback events into the actor. The task holds the session
        // weakly so a released session can deinit while it runs; the context's
        // deinit finishes the stream, which ends this loop and lets every
        // resource be reclaimed.
        let events = context.events
        Task { [weak self, events] in
            for await event in events {
                switch event {
                // for now, we skip forwarding of packet and stream events,
                // becuase there are a lot and we don't do anything with them.
                case .packet:
                    continue
                case .stream:
                    continue
                default:
                    await self?.sink?.tunerSessionDidEmit(event)
                }
            }
        }

        // Forward audio-output lifecycle events into the session actor.
        let audioPlayerEvents = audioPlayer.events
        Task { [weak self, audioPlayerEvents] in
            for await event in audioPlayerEvents {
                await self?.handleAudioPlayerEvent(event)
            }
        }
    }

    // MARK: - Public control

    public func start(_ configuration: TunerConfiguration) async {
        context.close()  // idempotent; every start gets a fresh C session

        do {
            try context.activate(configuration)
            try audioPlayer.start(configuration.program)
            isRunning = true
            await sink?.tunerSessionDidEmit(.started)
        } catch {
            context.close()
            audioPlayer.stop()
            await sink?.tunerSessionDidEmit(.failed(message: error.localizedDescription))
        }
    }

    public func stop() async {
        isRunning = false
        context.close()
        audioPlayer.stop()
        await sink?.tunerSessionDidEmit(.stopped)
    }

    /// Switches the decoded program (HD1–HD8) and flushes queued audio so the
    /// old program does not bleed into the new one.
    public func setProgram(_ program: Int) async {
        audioPlayer.setProgram(program)
    }

    /// Live retune while playing (RTL-SDR only).
    public func retune(frequencyHz: Float) async {
        guard context.retune(frequencyHz: frequencyHz) else {
            await sink?.tunerSessionDidEmit(.failed(message: "Could not tune to the requested frequency."))
            return
        }
        audioPlayer.flush()
    }

    // MARK: - Event handling

    private func handleAudioPlayerEvent(_ event: AudioPlayerEvent) async {
        switch event {
        case .routeChanged:
            await sink?.tunerSessionDidEmit(.audioOutputRouteChanged)
        case .interrupted:
            await sink?.tunerSessionDidEmit(.audioOutputInterrupted)
        case .resumed:
            await sink?.tunerSessionDidEmit(.audioOutputResumed)
        case .resumeFailed(let message):
            await sink?.tunerSessionDidEmit(.audioOutputFailed(message: message))
        }
    }
}
