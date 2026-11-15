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

/// `AudioPlayer` is `Sendable` because its mutable state lives in `lock` and
/// every call into AVAudioEngine/AVAudioPlayerNode is serialized by
/// `playerLock`. The two locks are never held together
/// across an AVAudioPlayerNode call: `stop()` can synchronously invoke buffer
/// completion handlers, and those handlers need `lock`. `playerLock` uses the
/// unchecked closure form because `AVAudioPCMBuffer` is not Sendable; the lock
/// only serializes calls within this class, it does not send AVFoundation
/// objects across isolation boundaries.
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
        var isPlaying = false
        var wasPlayingBeforeSleep: Bool = false
        var playbackGeneration: UInt64 = 0
        var pendingBufferCount = 0
    }

    /// Mutable player state is kept inside the lock so the class can be
    /// `Sendable` without an unchecked conformance.
    private let lock = OSAllocatedUnfairLock(initialState: State())
    private let playerLock = OSAllocatedUnfairLock<Void>(initialState: ())

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
        let generation = lock.withLock { state -> UInt64 in
            state.playbackGeneration &+= 1
            state.pendingBufferCount = 0
            state.currentProgram = program
            state.isPlaying = false
            state.wasPlayingBeforeSleep = false
            return state.playbackGeneration
        }

        do {
            try playerLock.withLockUnchecked {
                try engine.start()
                player.play()
            }
        } catch {
            playerLock.withLockUnchecked {
                player.stop()
                engine.stop()
            }
            lock.withLock { state in
                state.isPlaying = false
            }
            throw error
        }

        lock.withLock { state in
            guard state.playbackGeneration == generation else { return }
            state.isPlaying = true
        }
    }

    func stop() {
        lock.withLock { state in
            state.playbackGeneration &+= 1
            state.pendingBufferCount = 0
            state.isPlaying = false
        }
        playerLock.withLockUnchecked {
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
        let generation = lock.withLock { state -> UInt64? in
            guard state.isPlaying else {
                state.currentProgram = program
                return nil
            }
            state.playbackGeneration &+= 1
            state.pendingBufferCount = 0
            state.currentProgram = program
            state.isPlaying = false
            return state.playbackGeneration
        }
        guard let generation else { return }

        playerLock.withLockUnchecked {
            player.stop()
            player.play()
        }
        lock.withLock { state in
            guard state.playbackGeneration == generation else { return }
            state.isPlaying = true
        }
    }

    /// Drops any queued audio (e.g. after a program switch or retune) and
    /// resumes accepting buffers, keeping the engine running.
    func flush() {
        let generation = lock.withLock { state -> UInt64? in
            guard state.isPlaying else { return nil }
            state.playbackGeneration &+= 1
            state.pendingBufferCount = 0
            state.isPlaying = false
            return state.playbackGeneration
        }
        guard let generation else { return }

        playerLock.withLockUnchecked {
            player.stop()
            player.play()
        }
        lock.withLock { state in
            guard state.playbackGeneration == generation else { return }
            state.isPlaying = true
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
        guard samples.count >= 2 && samples.count <= (Int(NRSC5_AUDIO_FRAME_SAMPLES) * 2) else { return }
        guard
            let generation = lock.withLock({ state -> UInt64? in
                guard state.isPlaying, state.currentProgram == program else { return nil }
                return state.playbackGeneration
            })
        else { return }

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

        playerLock.withLockUnchecked {
            let shouldSchedule = lock.withLock { state in
                state.isPlaying
                    && state.currentProgram == program
                    && state.playbackGeneration == generation
            }
            guard shouldSchedule else { return }

            lock.withLock { state in
                state.pendingBufferCount += 1
            }
            player.scheduleBuffer(destBuffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                self?.didPlayBuffer(generation: generation)
            }
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
        let wasPlaying = lock.withLock { state -> Bool in
            state.wasPlayingBeforeSleep = state.isPlaying
            state.isPlaying = false
            state.playbackGeneration &+= 1
            state.pendingBufferCount = 0
            return state.wasPlayingBeforeSleep
        }
        guard wasPlaying else { return }

        playerLock.withLockUnchecked {
            player.stop()
            engine.stop()
        }
        continuation.yield(.interrupted)
    }

    @objc private func handleDidWake(_ notification: Notification) {
        recover(reporting: .resumed)
    }

    private func recover(reporting successEvent: AudioPlayerEvent) {
        let generation = lock.withLock { state -> UInt64? in
            guard state.wasPlayingBeforeSleep || state.isPlaying else { return nil }
            state.playbackGeneration &+= 1
            state.pendingBufferCount = 0
            state.isPlaying = false
            return state.playbackGeneration
        }
        guard let generation else { return }

        do {
            try playerLock.withLockUnchecked {
                player.stop()
                engine.stop()
                try engine.start()
                player.play()
            }
            lock.withLock { state in
                guard state.playbackGeneration == generation else { return }
                state.isPlaying = true
                state.wasPlayingBeforeSleep = false
            }
            continuation.yield(successEvent)
        } catch {
            lock.withLock { state in
                state.isPlaying = false
            }
            continuation.yield(.resumeFailed(message: error.localizedDescription))
        }
    }
}
