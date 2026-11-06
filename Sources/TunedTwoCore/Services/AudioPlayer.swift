//
//  AudioPlayer.swift
//  TunedTwo
//
//  macOS-native audio output using AVAudioEngine.
//

import AVFoundation
import AppKit
import CNrsc5
import Foundation
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
public final class AudioPlayer: AudioSampleSink, Sendable {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()

    private let nrsc5Format: AVAudioFormat
    private let outputFormat: AVAudioFormat
    private let converter: AVAudioConverter?

    private let continuation: AsyncStream<AudioPlayerEvent>.Continuation
    let events: AsyncStream<AudioPlayerEvent>

    private struct State: Sendable {
        var currentProgram: Int = 0
        var wasPlayingBeforeSleep: Bool = false
        var playbackGeneration: UInt64 = 0
        var pendingBufferCount = 0
    }

    /// Mutable player state is kept inside the lock so the class can be
    /// `Sendable` without an unchecked conformance.
    private let lock = OSAllocatedUnfairLock(initialState: State())

    init() {
        let sr = Double(NRSC5_SAMPLE_RATE_AUDIO)
        nrsc5Format = AVAudioFormat(
            commonFormat: .pcmFormatInt16, sampleRate: sr, channels: 2, interleaved: true)!
        outputFormat = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2)!
        converter = AVAudioConverter(from: nrsc5Format, to: outputFormat)

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: outputFormat)

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
            state.playbackGeneration &+= 1
            state.pendingBufferCount = 0
            try engine.start()
            state.currentProgram = program
            player.play()
        }
    }

    func stop() {
        lock.withLock { state in
            state.playbackGeneration &+= 1
            state.pendingBufferCount = 0
            player.stop()
            engine.stop()
        }
    }

    /// Wait until all scheduled audio has actually played through the output.
    /// Used at EOF for paced sample playback so the CLI does not exit early.
    func waitUntilDrained() async {
        while !Task.isCancelled {
            if lock.withLock({ $0.pendingBufferCount == 0 }) {
                return
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    func setProgram(_ program: Int) {
        lock.withLock { state in
            let isPlaying = player.isPlaying
            if isPlaying {
                state.playbackGeneration &+= 1
                state.pendingBufferCount = 0
                player.stop()
            }
            state.currentProgram = program
            if isPlaying {
                player.play()
            }
        }
    }

    /// Drops any queued audio (e.g. after a program switch or retune) and
    /// resumes accepting buffers, keeping the engine running.
    func flush() {
        lock.withLock { state in
            guard player.isPlaying else { return }
            state.playbackGeneration &+= 1
            state.pendingBufferCount = 0
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
        guard lock.withLock({ player.isPlaying && $0.currentProgram == program }) else { return }
        guard samples.count >= 2 && samples.count <= (Int(NRSC5_AUDIO_FRAME_SAMPLES) * 2) else { return }
        let frames = AVAudioFrameCount(samples.count / 2)

        // createSourceBuffer avoids copying the source data, but don't let this buffer
        // escape this function, since it is directly pointing at the nrsc5 library callback data.
        guard let sourceBuffer = createSourceBuffer(from: samples, pcmFormat: nrsc5Format) else { return }
        sourceBuffer.frameLength = frames

        // destBuffer is allocated each time, since it can't be freed until it is played.
        guard let destBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frames) else { return }
        destBuffer.frameLength = frames

        do {
            try converter?.convert(to: destBuffer, from: sourceBuffer)
        } catch {
            return
        }

        guard
            let generation = lock.withLock({ state -> UInt64? in
                guard player.isPlaying, state.currentProgram == program else { return nil }
                state.pendingBufferCount += 1
                return state.playbackGeneration
            })
        else { return }

        player.scheduleBuffer(destBuffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            self?.didPlayBuffer(generation: generation)
        }
    }

    private func didPlayBuffer(generation: UInt64) {
        lock.withLock { state in
            guard state.playbackGeneration == generation else { return }
            state.pendingBufferCount = max(0, state.pendingBufferCount - 1)
        }
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
        let wasPlaying = lock.withLock { state in
            state.wasPlayingBeforeSleep = player.isPlaying
            if player.isPlaying {
                player.stop()
            }
            if engine.isRunning {
                engine.stop()
            }
            return state.wasPlayingBeforeSleep
        }
        if wasPlaying {
            continuation.yield(.interrupted)
        }
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

        let result = lock.withLock { state -> RecoveryResult in
            guard state.wasPlayingBeforeSleep || player.isPlaying else {
                return .notRunning
            }
            player.stop()
            engine.stop()

            do {
                try engine.start()
                player.play()
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
