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

@testable import TunedTwoCore

/// Stub sink that drops audio samples. Used so the test does not need a
/// real audio output device.
private final class NullAudioSampleSink: AudioSampleSink, Sendable {
    func feed(_ program: Int, _ samples: UnsafeBufferPointer<Int16>) {}
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

    func release() {
        context = nil
    }

    var events: AsyncStream<TunerEvent>? {
        context?.events
    }
}

@Suite("Nrsc5Context sample-file decoding")
struct Nrsc5ContextTests {
    /// Runs the bundled `sample.bin` through a real libnrsc5 session and
    /// verifies that the bridge converts C callbacks into `TunerEvent`
    /// values. Audio is dropped by a stub sink so no output hardware is
    /// needed. This is a coarse integration test: it only requires that
    /// the file decodes far enough to achieve sync.
    @Test("decodes events from the bundled sample file")
    func decodesSampleFileEvents() async throws {
        let sink = NullAudioSampleSink()
        let holder = Nrsc5ContextHolder(Nrsc5Context(audioEventSink: sink))

        try await holder.activate(
            TunerConfiguration(source: .sampleFile, frequencyHz: nil, program: 0))

        guard let events = await holder.events else {
            Issue.record("Context was released before events could be read")
            return
        }

        let foundSync = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await event in events {
                    if case .syncAchieved = event {
                        return true
                    }
                }
                return false
            }

            group.addTask {
                try? await Task.sleep(for: .seconds(5))
                await holder.release()
                return false
            }

            let result = await group.next()!
            await holder.release()
            group.cancelAll()
            return result
        }

        #expect(foundSync, "Expected the sample file to achieve sync within the deadline")
    }
}
