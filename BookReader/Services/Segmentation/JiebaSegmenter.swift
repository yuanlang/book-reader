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

    /// Pause punctuation for natural rhythm — split at these for TTS phrasing.
    private static let pausePunctuation: Set<Character> = [
        "\u{FF0C}",  // ，(fullwidth comma)
        "\u{3001}",  // 、(enumeration comma)
        "\u{FF1A}",  // ：(fullwidth colon)
        "\u{2014}",  // —(em dash)
        "\u{2026}",  // …(ellipsis)
        ","          // ASCII comma
    ]

    /// Maximum characters per sentence for TTS segmentation.
    /// Shorter segments allow Kokoro to produce better prosody.
    private static let maxSentenceLength = 50

    /// Hard limit — never exceed this many characters in one segment.
    private static let hardLimitLength = 80

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
    /// Uses Jieba segmentation + punctuation heuristics with natural phrasing.
    /// - Parameter text: The text to split.
    /// - Returns: Array of sentence strings.
    func sentenceSplit(_ text: String) -> [String] {
        let words = segment(text)
        var sentences: [String] = []
        var current = ""

        for word in words {
            current += word

            let shouldSplit: Bool
            if hasSentenceEndPunctuation(word) {
                // Always split at sentence-ending punctuation
                shouldSplit = true
            } else if current.count >= Self.hardLimitLength {
                // Hard limit — must split to avoid overly long segments
                shouldSplit = true
            } else if current.count >= Self.maxSentenceLength && hasPausePunctuation(word) {
                // Split at comma/pause punctuation if segment is already long enough
                shouldSplit = true
            } else {
                shouldSplit = false
            }

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

    private func hasPausePunctuation(_ word: String) -> Bool {
        word.contains { Self.pausePunctuation.contains($0) }
    }
}
