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

import AVFoundation
import Foundation

actor AudioPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format: AVAudioFormat

    init() throws {
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: Double(NRSC5_SAMPLE_RATE_AUDIO),
                                      channels: 2) else {
            throw AudioError.formatUnsupported
        }
        self.format = fmt

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: fmt)
        engine.mainMixerNode.outputVolume = 1.0
    }

    func start() throws {
        try engine.start()
        player.play()
    }

    func stop() {
        player.stop()
        engine.stop()
    }

    /// Drops any queued audio (e.g. after a program switch or retune) and
    /// resumes accepting buffers, keeping the engine running.
    func flush() {
        player.stop()
        player.play()
    }

    /// Accepts interleaved 16-bit signed PCM from nrsc5, converts it to
    /// float, and schedules it on the system audio graph.
    func feed(_ samples: [Int16]) {
        guard samples.count >= 2 else { return }
        let frames = AVAudioFrameCount(samples.count / 2)
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            return
        }
        buffer.frameLength = frames

        guard let channelData = buffer.floatChannelData else { return }
        let left = channelData[0]
        let right = channelData[1]

        let scale: Float = 1.0 / 32768.0
        for i in 0..<Int(frames) {
            left[i] = Float(samples[i * 2]) * scale
            right[i] = Float(samples[i * 2 + 1]) * scale
        }

        player.scheduleBuffer(buffer)
    }

    enum AudioError: Error {
        case formatUnsupported
    }
}
