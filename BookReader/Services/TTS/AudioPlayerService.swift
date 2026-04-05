import Foundation
import AVFoundation

/// Manages audio playback for TTS using AVAudioEngine.
actor AudioPlayerService {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var isEngineStarted = false

    init() {
        engine.attach(playerNode)
        // Connect player to main mixer with default format
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 22050,
            channels: 1,
            interleaved: false
        )!
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
    }

    /// Play PCM data and wait for completion.
    func playAndWait(pcmData: Data, sampleRate: Int) async {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(sampleRate),
            channels: 1,
            interleaved: false
        )

        guard let pcmFormat = format,
              let buffer = pcmData.toPCMBuffer(format: pcmFormat) else {
            return
        }

        if !engine.isRunning {
            try? engine.start()
        }

        await withCheckedContinuation { continuation in
            playerNode.scheduleBuffer(buffer) {
                continuation.resume()
            }
            playerNode.play()
        }
    }

    func stop() {
        playerNode.stop()
        if engine.isRunning {
            engine.stop()
        }
    }
}

// MARK: - Data to PCM Buffer Conversion

extension Data {
    func toPCMBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frameCount = UInt32(count) / 2
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount

        withUnsafeBytes { rawBufferPointer in
            if let baseAddress = rawBufferPointer.baseAddress {
                memcpy(buffer.int16ChannelData![0], baseAddress, count)
            }
        }

        return buffer
    }
}
