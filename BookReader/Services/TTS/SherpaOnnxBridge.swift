import Foundation
import os.log

private let ttsLog = Logger(subsystem: "com.bookreader.app", category: "TTS")

/// Bridge to sherpa-onnx TTS engine using the C API.
/// Wraps Kokoro-82M-v1.1-zh Chinese+English speech synthesis via sherpa-onnx.
final class SherpaOnnxBridge {
    private var tts: OpaquePointer?
    private(set) var sampleRate: Int32 = 24000
    private var isInitialized = false

    deinit {
        if let tts = tts {
            SherpaOnnxDestroyOfflineTts(tts)
        }
    }

    /// Initialize the TTS model from bundled model files.
    func initialize() -> Bool {
        let version = String(cString: SherpaOnnxGetVersionStr())
        ttsLog.info("TTS Bridge init START, sherpa-onnx \(version)")

        guard let resourcePath = Bundle.main.resourcePath else {
            ttsLog.error("No resource path found")
            return false
        }

        // Files may be at bundle root or in tts-models subdirectory
        let ttsModelDir: String
        let fm = FileManager.default
        let subDir = (resourcePath as NSString).appendingPathComponent("tts-models")
        if fm.fileExists(atPath: (subDir as NSString).appendingPathComponent("tokens.txt")) {
            ttsModelDir = subDir
        } else {
            ttsModelDir = resourcePath
        }

        let modelPath = (ttsModelDir as NSString).appendingPathComponent("model.onnx")
        let tokensPath = (ttsModelDir as NSString).appendingPathComponent("tokens.txt")
        let voicesPath = (ttsModelDir as NSString).appendingPathComponent("voices.bin")
        let dataDirPath = (ttsModelDir as NSString).appendingPathComponent("espeak-ng-data")

        guard fm.fileExists(atPath: modelPath),
              fm.fileExists(atPath: tokensPath),
              fm.fileExists(atPath: voicesPath) else {
            ttsLog.error("TTS model files not found at: \(ttsModelDir)")
            return false
        }

        // Keep NSStrings alive for the duration of config setup
        let modelNS = modelPath as NSString
        let tokensNS = tokensPath as NSString
        let voicesNS = voicesPath as NSString
        let dataDirNS = dataDirPath as NSString

        // Build lexicon paths (comma-separated for en + zh)
        var lexiconPaths: [String] = []
        for name in ["lexicon-us-en.txt", "lexicon-zh.txt"] {
            let path = (ttsModelDir as NSString).appendingPathComponent(name)
            if fm.fileExists(atPath: path) { lexiconPaths.append(path) }
        }
        let lexiconNS = lexiconPaths.joined(separator: ",") as NSString

        var config = SherpaOnnxOfflineTtsConfig()
        memset(&config, 0, MemoryLayout<SherpaOnnxOfflineTtsConfig>.size)

        config.model.kokoro.model = modelNS.utf8String
        config.model.kokoro.voices = voicesNS.utf8String
        config.model.kokoro.tokens = tokensNS.utf8String
        config.model.kokoro.length_scale = 1.0

        if fm.fileExists(atPath: dataDirPath) {
            config.model.kokoro.data_dir = dataDirNS.utf8String
        }
        if lexiconNS.length > 0 {
            config.model.kokoro.lexicon = lexiconNS.utf8String
        }

        // Kokoro v1.1-zh is a multi-lang model, must set lang
        let langNS = "zh" as NSString
        config.model.kokoro.lang = langNS.utf8String

        // NOTE: NOT setting rule_fsts — the date-zh/number-zh/phone-zh FSTs
        // strip all Chinese text during sherpa-onnx normalization, causing
        // synthesis to always return nil.

        config.model.num_threads = 2
        config.model.debug = 0
        config.max_num_sentences = 1

        guard let ttsEngine = SherpaOnnxCreateOfflineTts(&config) else {
            ttsLog.error("Failed to create sherpa-onnx TTS engine")
            return false
        }

        self.tts = ttsEngine
        self.sampleRate = SherpaOnnxOfflineTtsSampleRate(ttsEngine)
        self.isInitialized = true
        let numSpeakers = SherpaOnnxOfflineTtsNumSpeakers(ttsEngine)
        ttsLog.info("TTS ready: \(self.sampleRate)Hz, \(numSpeakers) speakers")
        return true
    }

    /// Synthesize text to audio samples using Kokoro TTS.
    func synthesize(_ text: String, speed: Float = 1.0) -> (samples: [Float], sampleRate: Int32)? {
        guard isInitialized, let tts = tts, !text.isEmpty else { return nil }

        var genConfig = SherpaOnnxGenerationConfig()
        memset(&genConfig, 0, MemoryLayout<SherpaOnnxGenerationConfig>.size)
        genConfig.silence_scale = 0.2
        genConfig.speed = speed
        genConfig.sid = 3

        // Pass lang via extra JSON for multi-lang Kokoro models
        let extraStr = "{\"lang\":\"zh\"}" as NSString
        genConfig.extra = extraStr.utf8String

        guard let audio = SherpaOnnxOfflineTtsGenerateWithConfig(tts, text, &genConfig, nil, nil) else {
            ttsLog.error("TTS synthesis returned nil for: \(text.prefix(30))")
            return nil
        }
        defer { SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio) }

        let audioStruct = audio.pointee
        let numSamples = Int(audioStruct.n)
        guard numSamples > 0, let samplesPtr = audioStruct.samples else { return nil }

        let samples = Array(UnsafeBufferPointer(start: samplesPtr, count: numSamples))
        ttsLog.info("Generated \(numSamples) samples")
        return (samples, audioStruct.sample_rate)
    }
}
