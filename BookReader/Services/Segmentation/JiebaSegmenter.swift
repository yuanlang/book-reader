import Foundation

/// Swift interface for Jieba Chinese word segmentation.
final class JiebaSegmenter {
    private let wrapper = JiebaWrapper()
    private(set) var isInitialized = false

    /// Chinese sentence-ending punctuation marks.
    private static let sentenceEndPunctuation: Set<Character> = [
        "\u{3002}",  // 。
        "\u{FF01}",  // ！
        "\u{FF1F}",  // ？
        "\u{FF1B}",  // ；
        "\n"
    ]

    /// Maximum characters per sentence for TTS segmentation.
    private static let maxSentenceLength = 80

    /// Initialize Jieba with bundled dictionaries.
    func initialize() -> Bool {
        guard !isInitialized else { return true }
        isInitialized = wrapper.initJieba()
        return isInitialized
    }

    /// Segment Chinese text into words.
    /// - Parameter text: The text to segment.
    /// - Returns: Array of segmented word strings.
    func segment(_ text: String) -> [String] {
        guard isInitialized else { return [] }
        return wrapper.cut(text) as? [String] ?? []
    }

    /// Split text into sentences suitable for TTS reading.
    /// Uses Jieba segmentation + punctuation heuristics.
    /// - Parameter text: The text to split.
    /// - Returns: Array of sentence strings.
    func sentenceSplit(_ text: String) -> [String] {
        let words = segment(text)
        var sentences: [String] = []
        var current = ""

        for word in words {
            current += word

            let shouldSplit = hasSentenceEndPunctuation(word) ||
                              current.count >= Self.maxSentenceLength

            if shouldSplit {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    sentences.append(trimmed)
                }
                current = ""
            }
        }

        // Append remaining text
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            sentences.append(trimmed)
        }

        return sentences
    }

    private func hasSentenceEndPunctuation(_ word: String) -> Bool {
        word.contains { Self.sentenceEndPunctuation.contains($0) }
    }
}
