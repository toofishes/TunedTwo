//
//  AudioPlayer.swift
//  TunedTwo
//
//  macOS-native audio output using AVAudioEngine.
//

import AVFoundation
import Foundation

final class AudioPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private let queue = DispatchQueue(label: "io.tunedtwo.audio")

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
        do {
            try engine.start()
            player.play()
        } catch {
            fputs("[AudioPlayer] start error: \(error.localizedDescription)\n", stderr)
            throw error
        }
    }

    func stop() {
        player.stop()
        engine.stop()
    }

    func reset() {
        player.stop()
        engine.stop()
    }

    /// Accepts interleaved 16-bit signed PCM from nrsc5.
    func feed(_ samples: [Int16]) {
        guard samples.count >= 2 else { return }
        queue.async { [weak self] in
            guard let self = self else { return }
            self.schedule(samples)
        }
    }

    private func schedule(_ samples: [Int16]) {
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
