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

    /// Write diagnostic info to a temp file for debugging
    private func diag(_ msg: String) {
        ttsLog.info("\(msg)")
        let dir = NSTemporaryDirectory()
        let path = (dir as NSString).appendingPathComponent("tts_diag.txt")
        let data = (msg + "\n").data(using: .utf8) ?? Data()
        if FileManager.default.fileExists(atPath: path) {
            if let handle = FileHandle(forWritingAtPath: path) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    /// Initialize the TTS model from bundled model files.
    func initialize() -> Bool {
        let version = String(cString: SherpaOnnxGetVersionStr())
        diag("=== TTS Bridge initialize() START === sherpa-onnx version: \(version)")
        guard let resourcePath = Bundle.main.resourcePath else {
            diag("ERROR: No resource path found")
            return false
        }

        diag("Resource path: \(resourcePath)")

        // Files may be at bundle root or in tts-models subdirectory
        let ttsModelDir: String
        let fm = FileManager.default
        let subDir = (resourcePath as NSString).appendingPathComponent("tts-models")
        if fm.fileExists(atPath: (subDir as NSString).appendingPathComponent("tokens.txt")) {
            ttsModelDir = subDir
            diag("Using tts-models subdirectory: \(ttsModelDir)")
        } else {
            ttsModelDir = resourcePath
            diag("Using resource root: \(ttsModelDir)")
        }

        let modelPath = (ttsModelDir as NSString).appendingPathComponent("model.onnx")
        let tokensPath = (ttsModelDir as NSString).appendingPathComponent("tokens.txt")
        let voicesPath = (ttsModelDir as NSString).appendingPathComponent("voices.bin")
        let dataDirPath = (ttsModelDir as NSString).appendingPathComponent("espeak-ng-data")

        diag("Model path: \(modelPath) exists=\(fm.fileExists(atPath: modelPath))")
        diag("Tokens path: \(tokensPath) exists=\(fm.fileExists(atPath: tokensPath))")
        diag("Voices path: \(voicesPath) exists=\(fm.fileExists(atPath: voicesPath))")
        diag("Data dir: \(dataDirPath) exists=\(fm.fileExists(atPath: dataDirPath))")

        guard fm.fileExists(atPath: modelPath),
              fm.fileExists(atPath: tokensPath),
              fm.fileExists(atPath: voicesPath) else {
            diag("ERROR: TTS model files not found at: \(ttsModelDir)")
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
        diag("Lexicon paths: \(lexiconNS as String)")

        var config = SherpaOnnxOfflineTtsConfig()
        memset(&config, 0, MemoryLayout<SherpaOnnxOfflineTtsConfig>.size)

        // Use Kokoro model config instead of VITS
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

        // Set date/number/phone FSTs for Chinese text normalization
        var ruleFsts: [String] = []
        for name in ["date-zh.fst", "number-zh.fst", "phone-zh.fst"] {
            let path = (ttsModelDir as NSString).appendingPathComponent(name)
            if fm.fileExists(atPath: path) { ruleFsts.append(path) }
        }
        let ruleFstsNS = ruleFsts.joined(separator: ",") as NSString
        if ruleFstsNS.length > 0 {
            config.rule_fsts = ruleFstsNS.utf8String
        }
        diag("Rule FSTs: \(ruleFstsNS as String)")

        config.model.num_threads = 2
        config.model.debug = 1
        config.max_num_sentences = 1

        diag("Creating SherpaOnnx TTS engine (Kokoro model)...")
        guard let ttsEngine = SherpaOnnxCreateOfflineTts(&config) else {
            diag("ERROR: Failed to create sherpa-onnx TTS engine")
            return false
        }

        self.tts = ttsEngine
        self.sampleRate = SherpaOnnxOfflineTtsSampleRate(ttsEngine)
        self.isInitialized = true
        let numSpeakers = SherpaOnnxOfflineTtsNumSpeakers(ttsEngine)
        diag("SUCCESS: SherpaOnnx TTS initialized. Sample rate: \(self.sampleRate), numSpeakers: \(numSpeakers)")
        return true
    }

    /// Synthesize text to audio samples.
    func synthesize(_ text: String, speed: Float = 1.0) -> (samples: [Float], sampleRate: Int32)? {
        diag("synthesize called for: '\(text.prefix(50))' (length: \(text.count))")

        guard isInitialized, let tts = tts, !text.isEmpty else {
            diag("ERROR: Early return: isInitialized=\(self.isInitialized), tts=\(self.tts != nil), textEmpty=\(text.isEmpty)")
            return nil
        }

        diag("Calling SherpaOnnxOfflineTtsGenerateWithConfig...")
        var genConfig = SherpaOnnxGenerationConfig()
        memset(&genConfig, 0, MemoryLayout<SherpaOnnxGenerationConfig>.size)
        genConfig.speed = speed
        genConfig.sid = 3  // zf_001: 第一个中文女声 (0=af_maple英文, 1=af_sol英文, 2=bf_vale英文)
        genConfig.silence_scale = 0.2

        diag("genConfig size: \(MemoryLayout<SherpaOnnxGenerationConfig>.size), speed=\(genConfig.speed), sid=\(genConfig.sid)")

        guard let audio = SherpaOnnxOfflineTtsGenerateWithConfig(tts, text, &genConfig, nil, nil) else {
            diag("ERROR: SherpaOnnxOfflineTtsGenerateWithConfig returned nil for Chinese text")
            // Try English text as fallback test
            diag("Trying English text as test...")
            let testText = "Hello world."
            guard let testAudio = SherpaOnnxOfflineTtsGenerateWithConfig(tts, testText, &genConfig, nil, nil) else {
                diag("ERROR: English text also returned nil!")
                return nil
            }
            diag("English text works! n=\(testAudio.pointee.n), sr=\(testAudio.pointee.sample_rate)")
            SherpaOnnxDestroyOfflineTtsGeneratedAudio(testAudio)
            return nil
        }
        defer { SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio) }

        let audioStruct = audio.pointee
        let numSamples = Int(audioStruct.n)
        diag("Generated \(numSamples) samples at rate \(audioStruct.sample_rate)")

        guard numSamples > 0, let samplesPtr = audioStruct.samples else {
            diag("ERROR: No samples generated")
            return nil
        }

        let samples = Array(UnsafeBufferPointer(start: samplesPtr, count: numSamples))
        diag("Successfully created samples array (\(samples.count) floats)")
        return (samples, audioStruct.sample_rate)
    }
}
