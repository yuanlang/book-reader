import Foundation
import AVFoundation

/// Manages audio playback for TTS using AVAudioEngine.
actor AudioPlayerService {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var continuation: CheckedContinuation<Void, Never>?

    init() {
        engine.attach(playerNode)
        // Connect player to main mixer with default format
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 24000,
            channels: 1,
            interleaved: false
        )!
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
    }

    /// Play Float32 samples directly and wait for completion.
    func playAndWait(samples: [Float], sampleRate: Int) async {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(sampleRate),
            channels: 1,
            interleaved: false
        )!

        let frameCount = AVAudioFrameCount(samples.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return
        }
        buffer.frameLength = frameCount

        // Copy float samples directly into the buffer
        samples.withUnsafeBufferPointer { src in
            guard let dst = buffer.floatChannelData?[0] else { return }
            dst.initialize(from: src.baseAddress!, count: samples.count)
        }

        if !engine.isRunning {
            try? engine.start()
        }

        await withCheckedContinuation { cont in
            self.continuation = cont
            playerNode.scheduleBuffer(buffer) { [weak self] in
                Task { await self?.resumeContinuation() }
            }
            playerNode.play()
        }
    }

    private func resumeContinuation() {
        guard let cont = continuation else { return }
        continuation = nil
        cont.resume()
    }

    func stop() {
        // Resume continuation first so playAndWait can return
        if let cont = continuation {
            continuation = nil
            cont.resume()
        }
        playerNode.stop()
        if engine.isRunning {
            engine.stop()
        }
    }
}

