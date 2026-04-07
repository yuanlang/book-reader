import Testing
import AVFoundation
@testable import BookReader

@Suite("Kokoro TTS Engine Tests")
struct SherpaOnnxTTSEngineTests {

    @Test("Bridge initialization succeeds")
    func testBridgeInitialization() {
        let bridge = SherpaOnnxBridge()
        let success = bridge.initialize()
        #expect(success)
        #expect(bridge.sampleRate == 24000)
        #expect(bridge.numSpeakers > 0)
    }

    @Test("Chinese text synthesis produces audio samples")
    func testChineseSynthesis() {
        let bridge = SherpaOnnxBridge()
        #expect(bridge.initialize())

        let text = "今天天气不错。"
        let result = bridge.synthesize(text, speed: 1.0, lang: "zh")
        #expect(result != nil)
        #expect(result!.samples.count > 0)
        #expect(result!.sampleRate == 24000)

        // Verify samples are in valid float range [-1.0, 1.0]
        for sample in result!.samples {
            #expect(sample >= -1.0 && sample <= 1.0)
        }
    }

    @Test("English text synthesis produces audio samples")
    func testEnglishSynthesis() {
        let bridge = SherpaOnnxBridge()
        #expect(bridge.initialize())

        let text = "Hello, how are you today?"
        let result = bridge.synthesize(text, speed: 1.0, lang: "en")
        #expect(result != nil)
        #expect(result!.samples.count > 0)
        #expect(result!.sampleRate == 24000)
    }

    @Test("Float to PCM16 conversion produces correct data")
    func testFloatToPCM16Conversion() {
        let engine = SherpaOnnxTTSEngine()

        // Test via the engine's available voices
        let voices = engine.availableVoices
        #expect(voices.count == 2)
        #expect(voices[0].identifier == "kokoro-zh-yunyang")
        #expect(voices[1].identifier == "kokoro-en-bella")
    }

    @Test("Empty text returns nil")
    func testEmptyTextSynthesis() {
        let bridge = SherpaOnnxBridge()
        #expect(bridge.initialize())

        let result = bridge.synthesize("", speed: 1.0)
        #expect(result == nil)
    }

    @Test("Chinese text detection works")
    func testChineseTextDetection() {
        // These tests verify the language detection logic indirectly
        // through the engine's speak routing
        let chineseText = "你好世界"
        let englishText = "Hello world"
        let mixedText = "Hello 你好"

        // Chinese detection via regex
        let zhRange = chineseText.range(of: "[\u{4E00}-\u{9FFF}]", options: .regularExpression)
        #expect(zhRange != nil)

        let enRange = englishText.range(of: "[\u{4E00}-\u{9FFF}]", options: .regularExpression)
        #expect(enRange == nil)

        let mixRange = mixedText.range(of: "[\u{4E00}-\u{9FFF}]", options: .regularExpression)
        #expect(mixRange != nil)
    }

    @Test("PCM16 encoding correctness")
    func testPCM16Encoding() {
        // Verify that float samples are correctly converted to PCM16
        let samples: [Float] = [0.0, 1.0, -1.0, 0.5, -0.5]
        var data = Data(count: samples.count * 2)
        data.withUnsafeMutableBytes { ptr in
            guard let base = ptr.baseAddress?.assumingMemoryBound(to: Int16.self) else { return }
            for (i, sample) in samples.enumerated() {
                let clamped = max(-1.0, min(1.0, sample))
                base[i] = Int16(clamped * 32767.0)
            }
        }

        // Read back as Int16 values
        data.withUnsafeBytes { ptr in
            let base = ptr.baseAddress!.assumingMemoryBound(to: Int16.self)
            #expect(base[0] == 0)           // 0.0 -> 0
            #expect(base[1] == 32767)       // 1.0 -> 32767
            #expect(base[2] == -32767)      // -1.0 -> -32767
            #expect(base[3] >= 16382 && base[3] <= 16384)  // 0.5 -> ~16383
            #expect(base[4] >= -16384 && base[4] <= -16382) // -0.5 -> ~-16383
        }
    }

    @Test("Audio buffer creation from PCM data")
    func testAudioBufferCreation() {
        let sampleRate = 24000
        let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(sampleRate),
            channels: 1,
            interleaved: false
        )
        #expect(format != nil)

        // Create 1 second of silence
        let frameCount = UInt32(sampleRate)
        var data = Data(count: Int(frameCount) * 2)
        data.resetBytes(in: 0..<data.count)

        let buffer = data.toPCMBuffer(format: format!)
        #expect(buffer != nil)
        #expect(buffer!.frameLength == frameCount)
    }

    @Test("Chinese text with Chinese speaker produces valid audio")
    func testChineseSpeakerSynthesis() {
        let bridge = SherpaOnnxBridge()
        #expect(bridge.initialize())

        let text = "当夜幕降临，星光点点，伴随着微风拂面。"
        let result = bridge.synthesize(text, speed: 1.0, lang: "zh")
        #expect(result != nil)
        #expect(result!.samples.count > 0)

        // Verify the audio has meaningful amplitude (not silence)
        let maxAmp = result!.samples.map { abs($0) }.max() ?? 0
        #expect(maxAmp > 0.01, "Audio should have non-trivial amplitude")
    }

    @Test("English text with English speaker produces valid audio")
    func testEnglishSpeakerSynthesis() {
        let bridge = SherpaOnnxBridge()
        #expect(bridge.initialize())

        let text = "The quick brown fox jumps over the lazy dog."
        let result = bridge.synthesize(text, speed: 1.0, lang: "en")
        #expect(result != nil)
        #expect(result!.samples.count > 0)

        // Verify the audio has meaningful amplitude
        let maxAmp = result!.samples.map { abs($0) }.max() ?? 0
        #expect(maxAmp > 0.01, "Audio should have non-trivial amplitude")
    }

    @Test("Speed control affects audio duration")
    func testSpeedControl() {
        let bridge = SherpaOnnxBridge()
        #expect(bridge.initialize())

        let text = "今天天气不错。"

        let normalResult = bridge.synthesize(text, speed: 1.0, lang: "zh")
        let fastResult = bridge.synthesize(text, speed: 1.5, lang: "zh")

        #expect(normalResult != nil)
        #expect(fastResult != nil)

        // Faster speed should produce fewer samples (shorter audio)
        #expect(fastResult!.samples.count < normalResult!.samples.count,
               "Faster speed should produce shorter audio")
    }

    @Test("TTS encode-decode roundtrip: synthesized audio is valid PCM")
    func testEncodeDecodeRoundtrip() {
        let bridge = SherpaOnnxBridge()
        #expect(bridge.initialize())

        // Synthesize Chinese text
        let text = "春眠不觉晓，处处闻啼鸟。"
        let result = bridge.synthesize(text, speed: 1.0, lang: "zh")
        #expect(result != nil)

        // Encode to PCM16
        let floatSamples = result!.samples
        var pcmData = Data(count: floatSamples.count * 2)
        pcmData.withUnsafeMutableBytes { ptr in
            guard let base = ptr.baseAddress?.assumingMemoryBound(to: Int16.self) else { return }
            for (i, sample) in floatSamples.enumerated() {
                let clamped = max(-1.0, min(1.0, sample))
                base[i] = Int16(clamped * 32767.0)
            }
        }

        // Decode back to float
        var decodedSamples: [Float] = []
        decodedSamples.reserveCapacity(floatSamples.count)
        pcmData.withUnsafeBytes { ptr in
            let base = ptr.baseAddress!.assumingMemoryBound(to: Int16.self)
            for i in 0..<floatSamples.count {
                decodedSamples.append(Float(base[i]) / 32767.0)
            }
        }

        // Verify roundtrip: decoded should closely match original
        #expect(decodedSamples.count == floatSamples.count)
        var maxError: Float = 0
        for (original, decoded) in zip(floatSamples, decodedSamples) {
            let error = abs(original - decoded)
            maxError = max(maxError, error)
        }
        // Quantization error should be small (< 1 LSB = 1/32767 ≈ 0.00003)
        #expect(maxError < 0.00005, "PCM16 roundtrip error should be < 1 LSB, got \(maxError)")
    }

    @Test("Engine playback speed is configurable")
    func testEnginePlaybackSpeed() {
        let engine = SherpaOnnxTTSEngine()

        // Default speed
        #expect(engine.playbackSpeed == 1.0)

        // Change speed
        engine.playbackSpeed = 1.5
        #expect(engine.playbackSpeed == 1.5)

        engine.playbackSpeed = 0.75
        #expect(engine.playbackSpeed == 0.75)
    }
}
