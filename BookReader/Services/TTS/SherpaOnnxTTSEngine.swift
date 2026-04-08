import Foundation
import AVFoundation
import ReadiumNavigator
import ReadiumShared

/// TTS engine implementing Readium's TTSEngine protocol.
/// Uses iOS system TTS (AVSpeechSynthesizer) for high-quality Chinese/English speech.
final class SherpaOnnxTTSEngine: TTSEngine {

    private let systemSynthesizer = AVSpeechSynthesizer()

    /// Current playback speed, controlled by the UI.
    var playbackSpeed: Float = 1.0

    /// Selected voice identifier (e.g. "Lilian (Premium)", "Flo (中文（中国大陆）)").
    /// If nil or "default", uses the default voice for the language.
    var selectedVoiceIdentifier: String? {
        didSet { saveVoicePreference() }
    }

    init() {
        selectedVoiceIdentifier = UserDefaults.standard.string(forKey: "tts_voice_identifier")
    }

    /// Immediately stops any ongoing audio playback.
    func stopSpeaking() {
        systemSynthesizer.stopSpeaking(at: .immediate)
    }

    // MARK: - Voice Management

    /// A voice option for the picker UI.
    struct VoiceOption: Identifiable {
        let id: String          // AVSpeechSynthesisVoice identifier
        let name: String        // Display name
        let language: String    // e.g. "zh-CN", "en-US"
        let isPremium: Bool
    }

    /// All available Chinese and English voices, grouped by language.
    static var availableVoiceOptions: (chinese: [VoiceOption], english: [VoiceOption]) {
        let allVoices = AVSpeechSynthesisVoice.speechVoices()
        let targetLangs: Set<String> = [
            "zh-CN", "zh-TW",
            "en-US", "en-GB", "en-AU", "en-IE", "en-ZA", "en-IN"
        ]

        let filtered = allVoices.filter { targetLangs.contains($0.language) }

        var chinese: [VoiceOption] = []
        var english: [VoiceOption] = []

        for voice in filtered {
            let isPremium = voice.identifier.contains("Premium") || voice.quality == .enhanced
            let option = VoiceOption(
                id: voice.identifier,
                name: voice.name,
                language: voice.language,
                isPremium: isPremium
            )
            if voice.language.hasPrefix("zh") {
                chinese.append(option)
            } else {
                english.append(option)
            }
        }

        // Sort: Premium first, then by name
        let sort: (VoiceOption, VoiceOption) -> Bool = { a, b in
            if a.isPremium != b.isPremium { return a.isPremium }
            return a.name < b.name
        }
        chinese.sort(by: sort)
        english.sort(by: sort)

        return (chinese, english)
    }

    /// Resolve the AVSpeechSynthesisVoice to use for the given language.
    private func resolveVoice(for languageCode: String) -> AVSpeechSynthesisVoice? {
        // If user selected a specific voice, try to use it
        if let identifier = selectedVoiceIdentifier,
           let voice = AVSpeechSynthesisVoice(identifier: identifier) {
            return voice
        }
        // Fallback to language default
        return AVSpeechSynthesisVoice(language: languageCode)
    }

    private func saveVoicePreference() {
        if let id = selectedVoiceIdentifier, id != "default" {
            UserDefaults.standard.set(id, forKey: "tts_voice_identifier")
        } else {
            UserDefaults.standard.removeObject(forKey: "tts_voice_identifier")
        }
    }

    // MARK: - TTSEngine Protocol

    var availableVoices: [TTSVoice] {
        [
            TTSVoice(
                identifier: "system-zh",
                language: Language(code: .bcp47("zh-CN")),
                name: "系统中文语音",
                gender: .male,
                quality: .high
            ),
            TTSVoice(
                identifier: "system-en",
                language: Language(code: .bcp47("en-US")),
                name: "System English",
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
        let lang = containsChinese(text) ? "zh-CN" : "en-US"
        return await speakWithSystemTTS(text, languageCode: lang)
    }

    // MARK: - Private Methods

    private func containsChinese(_ text: String) -> Bool {
        text.range(of: "[\u{4E00}-\u{9FFF}]", options: .regularExpression) != nil
    }

    private func speakWithSystemTTS(_ text: String, languageCode: String) async -> Result<Void, TTSError> {
        return await withCheckedContinuation { continuation in
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = resolveVoice(for: languageCode)

            // Map playback speed (0.5x-2.0x) to AVSpeechUtterance rate
            let baseRate = AVSpeechUtteranceDefaultSpeechRate
            utterance.rate = baseRate * playbackSpeed

            NSLog("[TTSEngine] Using system TTS: voice=\(utterance.voice?.name ?? "default"), rate=\(utterance.rate)")

            let delegate = SystemTTSDelegate { result in
                continuation.resume(returning: result)
            }

            objc_setAssociatedObject(utterance, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            systemSynthesizer.delegate = delegate
            systemSynthesizer.speak(utterance)
        }
    }
}

// MARK: - System TTS Delegate

private class SystemTTSDelegate: NSObject, AVSpeechSynthesizerDelegate {
    private let completion: (Result<Void, TTSError>) -> Void

    init(completion: @escaping (Result<Void, TTSError>) -> Void) {
        self.completion = completion
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        completion(.success(()))
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        completion(.success(()))
    }
}
