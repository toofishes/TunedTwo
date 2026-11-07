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

/// Holds the non-Sendable `Nrsc5Context` so tests can release it and finish
/// the event stream without capturing the context in a `@Sendable` closure.
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
    @Test("decodes events and audio from the bundled sample through a pipe")
    func decodesSamplePipeEvents() async throws {
        let sink = CountingAudioSink()
        let holder = Nrsc5ContextHolder(Nrsc5Context(audioEventSink: sink))
        let sampleURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/sample.bin")

        try await holder.activate(
            TunerConfiguration(
                source: .samplePipe(path: sampleURL.path), frequencyHz: nil, program: 0))

        guard let events = await holder.events else {
            Issue.record("Context was released before events could be read")
            return
        }

        // Stream the capture in chunks instead of loading all 48 MB at once.
        let handle = try FileHandle(forReadingFrom: sampleURL)
        defer { try? handle.close() }
        var pushSucceeded = true
        for try await chunk in handle.dataChunks(ofSize: 64 * 1024) {
            guard await holder.pushPipeSamples(chunk) else {
                pushSucceeded = false
                break
            }
        }
        #expect(pushSucceeded, "Expected nrsc5 to accept pipe samples")
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
