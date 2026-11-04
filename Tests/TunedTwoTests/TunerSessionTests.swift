//
//  TunerSessionTests.swift
//  TunedTwoTests
//
//  Smoke tests for the tuner session lifecycle.
//

import Foundation
import Testing

@testable import TunedTwoCore

private final class MockTunerEventSink: TunerEventSink, Sendable {
    func tunerSessionDidEmit(_ event: TunerEvent) async {}
}

@Suite("TunerSession lifecycle")
struct TunerSessionTests {
    /// Initializing and releasing a `TunerSession` exercises the wiring
    /// between the actor, the `AudioPlayer`, the `Nrsc5Context`, and the
    /// background event consumers. It does not require an RTL-SDR or an
    /// audio output device because playback is never started; the
    /// `AudioPlayer` is only constructed (not started), and the
    /// `Nrsc5Context` only creates its event stream.
    @Test("initializes and tears down without hardware")
    func initializesAndTearsDown() async {
        let sink = MockTunerEventSink()
        let session = TunerSession(sink: sink)
        await session.stop()
    }
}
