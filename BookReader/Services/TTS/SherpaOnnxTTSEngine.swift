import Foundation
import AVFoundation
import ReadiumNavigator
import ReadiumShared

/// TTS engine implementing Readium's TTSEngine protocol,
/// using sherpa-onnx with Kokoro-82M-v1.1-zh for Chinese+English speech synthesis,
/// and AVSpeechSynthesizer for other languages as fallback.
final class SherpaOnnxTTSEngine: TTSEngine {

    private let bridge = SherpaOnnxBridge()
    private let audioPlayer = AudioPlayerService()
    private let systemSynthesizer = AVSpeechSynthesizer()
    private let initLock = NSLock()
    private var _isModelReady = false
    private var isModelReady: Bool {
        initLock.lock()
        defer { initLock.unlock() }
        return _isModelReady
    }

    init() {
        NSLog("[TTSEngine] Initializing SherpaOnnxTTSEngine...")
        // Initialize synchronously to ensure model is ready before any speak() calls
        initLock.lock()
        _isModelReady = bridge.initialize()
        initLock.unlock()
        if !_isModelReady {
            NSLog("[TTSEngine] WARNING: TTS model not initialized.")
        } else {
            NSLog("[TTSEngine] TTS model ready.")
        }
    }

    /// Immediately stops any ongoing audio playback.
    func stopSpeaking() {
        Task {
            await audioPlayer.stop()
        }
        systemSynthesizer.stopSpeaking(at: .immediate)
    }

    // MARK: - TTSEngine Protocol

    var availableVoices: [TTSVoice] {
        [
            TTSVoice(
                identifier: "kokoro-zh-female",
                language: Language(code: .bcp47("zh-CN")),
                name: "中文女声 (Kokoro)",
                gender: .female,
                quality: .high
            )
        ]
    }

    func speak(
        _ utterance: TTSUtterance,
        onSpeakRange: @escaping (Range<String.Index>) -> Void
    ) async -> Result<Void, TTSError> {
        let text = utterance.text
        guard !text.isEmpty else {
            return .success(())
        }

        NSLog("[TTSEngine] speak() called for text: \(text.prefix(50))")

        // Check if text contains Chinese characters
        if containsChinese(text) {
            return await speakChinese(text)
        } else {
            NSLog("[TTSEngine] Non-Chinese text detected, using system TTS")
            return await speakWithSystemTTS(text, languageCode: utterance.language.code.bcp47)
        }
    }

    // MARK: - Private Methods

    private func containsChinese(_ text: String) -> Bool {
        // Check if text contains any Chinese characters
        let chineseRange = text.range(of: "[\u{4E00}-\u{9FFF}]", options: .regularExpression)
        return chineseRange != nil
    }

    private func speakChinese(_ text: String) async -> Result<Void, TTSError> {
        NSLog("[TTSEngine] Chinese text, using Kokoro TTS. isModelReady: \(isModelReady)")

        if isModelReady, let result = bridge.synthesize(text, speed: 1.0) {
            NSLog("[TTSEngine] Synthesis successful, playing audio...")
            let pcmData = floatSamplesToPCM16(result.samples)
            await audioPlayer.playAndWait(pcmData: pcmData, sampleRate: Int(result.sampleRate))
            return .success(())
        }

        // Check if cancelled during synthesis
        if Task.isCancelled {
            return .success(())
        }

        // Fallback to system TTS if Kokoro TTS fails
        NSLog("[TTSEngine] Kokoro TTS failed, falling back to system TTS")
        return await speakWithSystemTTS(text, languageCode: "zh-CN")
    }

    private func speakWithSystemTTS(_ text: String, languageCode: String?) async -> Result<Void, TTSError> {
        return await withCheckedContinuation { continuation in
            let utterance = AVSpeechUtterance(string: text)

            // Set language
            let lang = languageCode ?? (containsChinese(text) ? "zh-CN" : "en-US")
            utterance.voice = AVSpeechSynthesisVoice(language: lang)
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate

            NSLog("[TTSEngine] Using system TTS with language: \(lang)")

            let delegate = SystemTTSDelegate { result in
                continuation.resume(returning: result)
            }

            // Store delegate to keep it alive during synthesis
            objc_setAssociatedObject(utterance, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            systemSynthesizer.delegate = delegate
            systemSynthesizer.speak(utterance)
        }
    }

    // MARK: - Audio Conversion

    private func floatSamplesToPCM16(_ samples: [Float]) -> Data {
        var data = Data(count: samples.count * 2)
        data.withUnsafeMutableBytes { ptr in
            guard let base = ptr.baseAddress?.assumingMemoryBound(to: Int16.self) else { return }
            for (i, sample) in samples.enumerated() {
                let clamped = max(-1.0, min(1.0, sample))
                base[i] = Int16(clamped * 32767.0)
            }
        }
        return data
    }
}

// MARK: - System TTS Delegate

private class SystemTTSDelegate: NSObject, AVSpeechSynthesizerDelegate {
    private let completion: (Result<Void, TTSError>) -> Void

    init(completion: @escaping (Result<Void, TTSError>) -> Void) {
        self.completion = completion
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        NSLog("[TTSEngine] System TTS finished")
        completion(.success(()))
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        NSLog("[TTSEngine] System TTS cancelled")
        completion(.success(()))
    }
}
