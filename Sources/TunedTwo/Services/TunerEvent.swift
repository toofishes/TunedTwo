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
enum TunerEvent: Sendable {
    // Lifecycle (emitted by the session itself, not by nrsc5)
    case started
    case stopped
    case failed(message: String)

    // Demodulator state
    case syncAchieved
    case lostSync
    case lostDevice

    // Signal metrics
    case mer(lower: Float, upper: Float)
    case ber(cber: Float)

    // Station metadata
    case stationName(String)
    case stationSlogan(String)
    case id3(program: Int, title: String, artist: String, album: String)

    // Decoded audio (consumed by the session, forwarded to the audio actor)
    case audio(program: Int, samples: [Int16])
}

/// Receives tuner events. Conformers run on the MainActor (typically
/// `TunerState`); the session only ever reaches them through `await`, so
/// the nrsc5 worker thread never touches UI-owned state.
protocol TunerEventSink: AnyObject, Sendable {
    func tunerSessionDidEmit(_ event: TunerEvent) async
}
