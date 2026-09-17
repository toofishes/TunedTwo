//
//  AudioPlayer.swift
//  TunedTwo
//
//  macOS-native audio output using AVAudioEngine.
//
//  Confined to its own actor so all audio work — PCM conversion and buffer
//  scheduling — happens off the main thread, fed directly from the tuner
//  session's background context into the system audio graph.
//

@preconcurrency import AVFoundation
import Foundation
import nrsc5
import os

public final class AudioPlayer: Sendable {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()

    private let inputFormatInt16: AVAudioFormat
    private let outputFormatFloat: AVAudioFormat
    private let converter: AVAudioConverter

    private let lock = OSAllocatedUnfairLock()

    init() throws {
        let sr = Double(NRSC5_SAMPLE_RATE_AUDIO)
        guard let inFmt = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                        sampleRate: sr,
                                        channels: 2,
                                        interleaved: true),
              let outFmt = AVAudioFormat(standardFormatWithSampleRate: sr,
                                         channels: 2) else {
            throw AudioError.formatUnsupported
        }

        self.inputFormatInt16 = inFmt
        self.outputFormatFloat = outFmt

        guard let conv = AVAudioConverter(from: inFmt, to: outFmt) else {
            throw AudioError.formatUnsupported
        }
        self.converter = conv

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: outFmt)
    }

    func start() throws {
        try lock.withLock {
            try engine.start()
            player.play()
        }
    }

    func stop() {
        lock.withLock {
            player.stop()
            engine.stop()
        }
    }

    /// Drops any queued audio (e.g. after a program switch or retune) and
    /// resumes accepting buffers, keeping the engine running.
    func flush() {
        lock.withLock {
            player.stop()
            player.play()
        }
    }

    /// Accepts interleaved 16-bit signed PCM from nrsc5, converts it to
    /// float, and schedules it on the system audio graph.
    func feed(_ samples: [Int16]) {
        guard samples.count >= 2 else { return }
        let frames = AVAudioFrameCount(samples.count / 2)

        guard let sourceBuffer = AVAudioPCMBuffer(pcmFormat: inputFormatInt16, frameCapacity: frames) else { return }
                sourceBuffer.frameLength = frames
        sourceBuffer.frameLength = frames

        samples.withUnsafeBufferPointer { srcPtr in
            if let destPtr = sourceBuffer.int16ChannelData?[0] {
                destPtr.initialize(from: srcPtr.baseAddress!, count: samples.count)
            }
        }

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
