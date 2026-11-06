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
//  - For audio, we optimize by avoiding buffer copies. The audio player gets
//    an unsafe pointer directly (via the `AudioSampleSink` protocol) and
//    does any processing necessary to get it queued up for the audio system,
//    avoiding a hop through an AsyncStream.
//  - A single long-lived consumer task drains the stream into the actor.
//    It holds the session weakly so the session can deinit while it runs:
//    the context tears the C session down, finishes the stream, the loop
//    ends, and every resource (worker thread, C session, audio) is reclaimed.
//  - UI state is only ever touched via the awaited `TunerEventSink`
//    (MainActor), held weakly.
//

import AVFoundation
import CNrsc5
import Foundation
import os

/// Configuration snapshot taken on the MainActor when playback starts, so
/// the session never reads UI-owned state directly.
public struct TunerConfiguration: Sendable {
    public enum Source: Sendable {
        case rtlSDR(deviceIndex: Int)
        case samplePipe(path: String)
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
    private var sink: TunerEventSink?
    private let audioPlayer: AudioPlayer
    private let context: Nrsc5Context

    private var isRunning = false
    private var sampleFeederTask: Task<Void, Never>?

    public init(sink: TunerEventSink) {
        self.sink = sink
        self.audioPlayer = AudioPlayer()
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
        await cancelSampleFeeder()
        context.close()  // idempotent; every start gets a fresh C session

        do {
            try context.activate(configuration)
            try audioPlayer.start(configuration.program)
            isRunning = true
            await sink?.tunerSessionDidEmit(.started)

            if case .samplePipe(let path) = configuration.source {
                sampleFeederTask = Task { [weak self] in
                    await self?.feedSampleFile(path: path)
                }
            }
        } catch {
            context.close()
            audioPlayer.stop()
            await sink?.tunerSessionDidEmit(.failed(message: error.localizedDescription))
        }
    }

    /// Wait until a paced sample source reaches EOF and its queued audio drains.
    public func waitUntilSamplePlaybackFinishes() async {
        await sampleFeederTask?.value
    }

    public func stop() async {
        await cancelSampleFeeder()
        isRunning = false
        context.close()
        audioPlayer.stop()
        await sink?.tunerSessionDidEmit(.stopped)
    }

    private func cancelSampleFeeder() async {
        guard let sampleFeederTask else { return }
        sampleFeederTask.cancel()
        await sampleFeederTask.value
        self.sampleFeederTask = nil
    }

    /// Feed uncompressed CU8 I/Q into libnrsc5 at the capture's sample rate.
    /// Pacing this stream keeps ID3 and other metadata aligned with playback.
    private func feedSampleFile(path: String) async {
        guard let file = fopen(path, "rb") else {
            let message = String(cString: strerror(errno))
            await sink?.tunerSessionDidEmit(.failed(message: "Could not open sample file: \(message)"))
            return
        }
        defer { fclose(file) }

        let chunkSize = 64 * 1024
        var buffer = [UInt8](repeating: 0, count: chunkSize)
        let clock = ContinuousClock()
        var nextDeadline = clock.now
        let byteRate = Double(NRSC5_SAMPLE_RATE_CU8) * 2

        while !Task.isCancelled {
            let bytesRead = buffer.withUnsafeMutableBytes { bytes in
                fread(bytes.baseAddress, 1, bytes.count, file)
            }
            if bytesRead == 0 {
                if ferror(file) != 0 {
                    await sink?.tunerSessionDidEmit(.failed(message: "Error reading sample file."))
                }
                await audioPlayer.waitUntilDrained()
                return
            }

            let data = Data(buffer.prefix(bytesRead))
            guard context.pushPipeSamples(data) else {
                await sink?.tunerSessionDidEmit(.failed(message: "nrsc5 rejected sample input."))
                return
            }

            let chunkDuration = Duration.seconds(Double(bytesRead) / byteRate)
            nextDeadline = nextDeadline.advanced(by: chunkDuration)
            do {
                try await clock.sleep(until: nextDeadline, tolerance: .milliseconds(2))
            } catch is CancellationError {
                return
            } catch {
                await sink?.tunerSessionDidEmit(
                    .failed(message: "Could not pace sample input: \(error.localizedDescription)"))
                return
            }
        }
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
