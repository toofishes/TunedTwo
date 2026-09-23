//
//  AudioPlayer.swift
//  TunedTwo
//
//  macOS-native audio output using AVAudioEngine.
//

import AVFoundation
import AppKit
import Foundation
import nrsc5
import os

/// Events raised by the audio player when macOS changes the audio hardware
/// configuration (headphones in/out, default output device change) or when
/// the system sleeps/wakes.
public enum AudioPlayerEvent: Sendable {
    /// The audio engine's hardware configuration changed (e.g. headphones
    /// were connected or disconnected). The player attempted to restart.
    case routeChanged
    /// The system is going to sleep; playback has been paused.
    case interrupted
    /// Playback was resumed after a route change or wake notification.
    case resumed
    /// The engine could not be restarted after a route change or wake.
    case resumeFailed(message: String)
}

/// The AVFoundation engine/player/format objects are non-`Sendable`, so the
/// specific stored properties that hold them are marked `nonisolated(unsafe)`.
/// All access to that state (and to `isRunning`) is serialized by `lock`, and
/// notification callbacks dispatch recovery work asynchronously to avoid
/// deadlocks inside `AVAudioEngine`.
public final class AudioPlayer: AudioEventSink, Sendable {
    nonisolated(unsafe) private let engine = AVAudioEngine()
    nonisolated(unsafe) private let player = AVAudioPlayerNode()

    private let inputFormatInt16: AVAudioFormat
    private let outputFormatFloat: AVAudioFormat
    private let converter: AVAudioConverter

    private let continuation: AsyncStream<AudioPlayerEvent>.Continuation
    let events: AsyncStream<AudioPlayerEvent>

    private struct State: Sendable {
        var isRunning = false
        var currentProgram: Int = 0
    }

    /// Mutable player state is kept inside the lock so the class can be
    /// `Sendable` without an unchecked conformance.
    private let lock = OSAllocatedUnfairLock(initialState: State())

    init() throws {
        let sr = Double(NRSC5_SAMPLE_RATE_AUDIO)
        guard
            let inFmt = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: sr,
                channels: 2,
                interleaved: true),
            let outFmt = AVAudioFormat(
                standardFormatWithSampleRate: sr,
                channels: 2),
            let conv = AVAudioConverter(from: inFmt, to: outFmt)
        else {
            throw AudioError.formatUnsupported
        }

        self.inputFormatInt16 = inFmt
        self.outputFormatFloat = outFmt
        self.converter = conv

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: outFmt)

        (events, continuation) = AsyncStream.makeStream(of: AudioPlayerEvent.self)

        registerNotifications()
    }

    deinit {
        unregisterNotifications()
        continuation.finish()
        stop()
    }

    func start(_ program: Int) throws {
        try lock.withLock { state in
            try engine.start()
            state.currentProgram = program
            player.play()
            state.isRunning = true
        }
    }

    func stop() {
        lock.withLock { state in
            state.isRunning = false
            player.stop()
            engine.stop()
        }
    }

    func setProgram(_ program: Int) {
        lock.withLock { state in
            guard state.isRunning else { return }
            player.stop()
            state.currentProgram = program
            player.play()
        }
    }

    /// Drops any queued audio (e.g. after a program switch or retune) and
    /// resumes accepting buffers, keeping the engine running.
    func flush() {
        lock.withLock { state in
            guard state.isRunning else { return }
            player.stop()
            player.play()
        }
    }

    private func createSourceBuffer(
        from bufferPointer: UnsafeBufferPointer<Int16>,
        pcmFormat: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let audioBuffer = AudioBuffer(
            mNumberChannels: pcmFormat.channelCount,
            mDataByteSize: UInt32(bufferPointer.count * MemoryLayout<Int16>.size),
            mData: UnsafeMutableRawPointer(mutating: bufferPointer.baseAddress)
        )

        var bufferList = AudioBufferList(mNumberBuffers: 1, mBuffers: (audioBuffer))
        let pcmBuffer = AVAudioPCMBuffer(pcmFormat: pcmFormat, bufferListNoCopy: &bufferList)
        return pcmBuffer
    }

    /// Accepts interleaved 16-bit signed PCM from nrsc5, converts it to
    /// float, and schedules it on the system audio graph.
    public func feed(_ program: Int, _ samples: UnsafeBufferPointer<Int16>) {
        guard lock.withLock({ $0.isRunning && $0.currentProgram == program }) else { return }
        guard samples.count >= 2 && samples.count <= (Int(NRSC5_AUDIO_FRAME_SAMPLES) * 2) else { return }
        let frames = AVAudioFrameCount(samples.count / 2)

        // createSourceBuffer avoids copying the source data, but don't let this buffer
        // escape this function, since it is directly pointing at the nrsc5 library callback data.
        guard let sourceBuffer = createSourceBuffer(from: samples, pcmFormat: inputFormatInt16) else { return }
        sourceBuffer.frameLength = frames

        // destBuffer is allocated each time, since it can't be freed until it is played.
        guard let destBuffer = AVAudioPCMBuffer(pcmFormat: outputFormatFloat, frameCapacity: frames) else { return }
        destBuffer.frameLength = frames

        do {
            try converter.convert(to: destBuffer, from: sourceBuffer)
        } catch {
            return
        }

        player.scheduleBuffer(destBuffer)
    }

    enum AudioError: Error {
        case formatUnsupported
    }
}

// MARK: - System notifications

extension AudioPlayer {
    private func registerNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEngineConfigurationChange(_:)),
            name: .AVAudioEngineConfigurationChange,
            object: engine
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWillSleep(_:)),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleDidWake(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    private func unregisterNotifications() {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func handleEngineConfigurationChange(_ notification: Notification) {
        // The engine stops and uninitializes itself when the hardware
        // configuration changes (e.g. headphones unplugged). Do not touch
        // the engine synchronously from this handler to avoid deadlocks.
        recover(reporting: .routeChanged)
    }

    @objc private func handleWillSleep(_ notification: Notification) {
        lock.withLock { state in
            state.isRunning = false
            player.stop()
            engine.stop()
        }
        continuation.yield(.interrupted)
    }

    @objc private func handleDidWake(_ notification: Notification) {
        recover(reporting: .resumed)
    }

    private func recover(reporting successEvent: AudioPlayerEvent) {
        enum RecoveryResult {
            case restarted
            case notRunning
            case failed(Error)
        }

        let result = self.lock.withLock { state -> RecoveryResult in
            // Only restart if we were actively playing when the change
            // happened. If the user already pressed stop, leave it off.
            guard state.isRunning else { return .notRunning }

            state.isRunning = false
            self.player.stop()
            self.engine.stop()

            do {
                try self.engine.start()
                self.player.play()
                state.isRunning = true
                return .restarted
            } catch {
                return .failed(error)
            }
        }

        switch result {
        case .restarted:
            continuation.yield(successEvent)
        case .notRunning:
            break
        case .failed(let error):
            continuation.yield(.resumeFailed(message: error.localizedDescription))
        }
    }

}
