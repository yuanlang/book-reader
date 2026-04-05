import Foundation

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
        NSLog("[TTS] Starting TTS initialization...")
        guard let resourcePath = Bundle.main.resourcePath else {
            NSLog("[TTS] ERROR: No resource path found")
            return false
        }

        NSLog("[TTS] Resource path: \(resourcePath)")

        // Files may be at bundle root or in tts-models subdirectory
        let ttsModelDir: String
        let fm = FileManager.default
        let subDir = (resourcePath as NSString).appendingPathComponent("tts-models")
        if fm.fileExists(atPath: (subDir as NSString).appendingPathComponent("tokens.txt")) {
            ttsModelDir = subDir
            NSLog("[TTS] Using tts-models subdirectory: \(ttsModelDir)")
        } else {
            ttsModelDir = resourcePath
            NSLog("[TTS] Using resource root: \(ttsModelDir)")
        }

        let modelPath = (ttsModelDir as NSString).appendingPathComponent("model.onnx")
        let tokensPath = (ttsModelDir as NSString).appendingPathComponent("tokens.txt")
        let voicesPath = (ttsModelDir as NSString).appendingPathComponent("voices.bin")
        let dataDirPath = (ttsModelDir as NSString).appendingPathComponent("espeak-ng-data")

        NSLog("[TTS] Model path: \(modelPath)")
        NSLog("[TTS] Tokens path: \(tokensPath)")
        NSLog("[TTS] Voices path: \(voicesPath)")
        NSLog("[TTS] Data dir: \(dataDirPath)")
        NSLog("[TTS] Model exists: \(fm.fileExists(atPath: modelPath))")
        NSLog("[TTS] Tokens exists: \(fm.fileExists(atPath: tokensPath))")
        NSLog("[TTS] Voices exists: \(fm.fileExists(atPath: voicesPath))")

        guard fm.fileExists(atPath: modelPath),
              fm.fileExists(atPath: tokensPath),
              fm.fileExists(atPath: voicesPath) else {
            NSLog("[TTS] ERROR: TTS model files not found at: \(ttsModelDir)")
            return false
        }

        // Keep NSStrings alive for the duration of config setup
        let modelNS = modelPath as NSString
        let tokensNS = tokensPath as NSString
        let voicesNS = voicesPath as NSString
        let dataDirNS = dataDirPath as NSString

        // Build lexicon paths (comma-separated for zh + en)
        var lexiconPaths: [String] = []
        for name in ["lexicon-us-en.txt", "lexicon-zh.txt"] {
            let path = (ttsModelDir as NSString).appendingPathComponent(name)
            if fm.fileExists(atPath: path) { lexiconPaths.append(path) }
        }
        let lexiconNS = lexiconPaths.joined(separator: ",") as NSString

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

        config.model.num_threads = 2
        config.model.debug = 0
        config.max_num_sentences = 1

        NSLog("[TTS] Creating SherpaOnnx TTS engine...")
        guard let ttsEngine = SherpaOnnxCreateOfflineTts(&config) else {
            NSLog("[TTS] ERROR: Failed to create sherpa-onnx TTS engine")
            return false
        }

        self.tts = ttsEngine
        self.sampleRate = SherpaOnnxOfflineTtsSampleRate(ttsEngine)
        self.isInitialized = true
        NSLog("[TTS] SherpaOnnx TTS initialized successfully. Sample rate: \(self.sampleRate)")
        return true
    }

    /// Synthesize text to audio samples.
    func synthesize(_ text: String, speed: Float = 1.0) -> (samples: [Float], sampleRate: Int32)? {
        NSLog("[TTS Bridge] synthesize called for: '\(text)' (length: \(text.count))")
        NSLog("[TTS Bridge] isInitialized: \(isInitialized), tts: \(tts != nil ? "exists" : "nil")")

        guard isInitialized, let tts = tts, !text.isEmpty else {
            NSLog("[TTS Bridge] Early return: isInitialized=\(isInitialized), tts=\(tts != nil), textEmpty=\(text.isEmpty)")
            return nil
        }

        NSLog("[TTS Bridge] Calling SherpaOnnxOfflineTtsGenerate...")
        guard let audio = SherpaOnnxOfflineTtsGenerate(tts, text, 0, speed) else {
            NSLog("[TTS Bridge] ERROR: SherpaOnnxOfflineTtsGenerate returned nil for: \(text.prefix(50))")
            return nil
        }
        defer { SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio) }

        let audioStruct = audio.pointee
        let numSamples = Int(audioStruct.n)
        NSLog("[TTS Bridge] Generated \(numSamples) samples at rate \(audioStruct.sample_rate)")

        guard numSamples > 0, let samplesPtr = audioStruct.samples else {
            NSLog("[TTS Bridge] ERROR: No samples generated")
            return nil
        }

        let samples = Array(UnsafeBufferPointer(start: samplesPtr, count: numSamples))
        NSLog("[TTS Bridge] Successfully created samples array")
        return (samples, audioStruct.sample_rate)
    }
}
