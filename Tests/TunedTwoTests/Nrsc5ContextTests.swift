//
//  Nrsc5ContextTests.swift
//  TunedTwoTests
//
//  Integration smoke test for the libnrsc5 bridge using the bundled
//  sample I/Q file. No real audio device is required because audio
//  samples are discarded by a stub sink.
//

import Foundation
import Testing
import os

@testable import TunedTwoCore

/// Stub sink that counts audio feeds. Used so the test does not need a
/// real audio output device, while still verifying that the audio callback
/// is routed through the `AudioSampleSink` interface.
private final class CountingAudioSink: AudioSampleSink, Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: 0)

    func feed(_ program: Int, _ samples: UnsafeBufferPointer<Int16>) {
        lock.withLock { $0 += 1 }
    }

    var feedCount: Int {
        lock.withLock { $0 }
    }
}

/// Holds the non-Sendable `Nrsc5Context` so a timeout task can release it
/// and finish the event stream without capturing the context in a
/// `@Sendable` closure.
private actor Nrsc5ContextHolder {
    private var context: Nrsc5Context?

    init(_ context: Nrsc5Context) {
        self.context = context
    }

    func activate(_ configuration: TunerConfiguration) throws {
        try context?.activate(configuration)
    }

    func pushPipeSamples(_ samples: Data) -> Bool {
        context?.pushPipeSamples(samples) ?? false
    }

    func release() {
        context = nil
    }

    var events: AsyncStream<TunerEvent>? {
        context?.events
    }
}

@Suite("Nrsc5Context sample decoding")
struct Nrsc5ContextTests {
    /// Runs the bundled `sample.bin` through a real libnrsc5 session and
    /// verifies that the bridge converts C callbacks into `TunerEvent`
    /// values and routes audio samples to the injected `AudioSampleSink`.
    /// No output hardware is needed. This is a coarse integration test:
    /// it only requires that the file decodes far enough to achieve sync
    /// and emit at least one audio frame.
    @Test("decodes events and audio from the bundled sample file")
    func decodesSampleFileEvents() async throws {
        let sink = CountingAudioSink()
        let holder = Nrsc5ContextHolder(Nrsc5Context(audioEventSink: sink))

        let samplePath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // TunedTwoTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repository root
            .appendingPathComponent("Resources/sample.bin")
            .path

        try await holder.activate(
            TunerConfiguration(
                source: .sampleFile(path: samplePath), frequencyHz: nil, program: 0))

        guard let events = await holder.events else {
            Issue.record("Context was released before events could be read")
            return
        }

        // Drain events until we've verified both sync and at least one
        // audio feed. Audio frames are routed directly to the sink, not
        // sent through the event stream, so we poll the sink count as
        // events arrive. A separate timeout task releases the context to
        // finish the stream if the consumer is still awaiting.
        let consumer = Task {
            var sawSync = false
            let deadline = ContinuousClock().now + .seconds(2)
            for await event in events {
                if case .syncAchieved = event {
                    sawSync = true
                }
                if sawSync, sink.feedCount > 0 {
                    break
                }
                if ContinuousClock().now >= deadline {
                    break
                }
            }
            return sawSync
        }

        let timeout = Task {
            try? await Task.sleep(for: .seconds(2))
            await holder.release()
        }

        let foundSync = await consumer.value
        timeout.cancel()

        #expect(foundSync, "Expected the sample file to achieve sync within the deadline")
        #expect(sink.feedCount > 0, "Expected audio samples to be routed to the sink")
    }

    @Test("decodes events and audio through an nrsc5 pipe")
    func decodesPipeSampleFileEvents() async throws {
        let sink = CountingAudioSink()
        let holder = Nrsc5ContextHolder(Nrsc5Context(audioEventSink: sink))
        let samplePath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/sample.bin")
            .path

        try await holder.activate(
            TunerConfiguration(
                source: .samplePipe(path: samplePath), frequencyHz: nil, program: 0))

        guard let events = await holder.events else {
            Issue.record("Context was released before events could be read")
            return
        }

        let samples = try Data(contentsOf: URL(fileURLWithPath: samplePath))
        #expect(await holder.pushPipeSamples(samples), "Expected nrsc5 to accept pipe samples")
        await holder.release()

        var foundSync = false
        for await event in events {
            if case .syncAchieved = event {
                foundSync = true
            }
        }

        #expect(foundSync, "Expected the pipe input to achieve sync")
        #expect(sink.feedCount > 0, "Expected pipe audio to be routed to the sink")
    }
}
