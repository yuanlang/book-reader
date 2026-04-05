import Foundation
import ReadiumShared
import ReadiumNavigator

/// Creates a ContentTokenizer that uses Jieba for Chinese sentence splitting.
/// This is passed as the `tokenizerFactory` to `PublicationSpeechSynthesizer`.
func makeJiebaContentTokenizer(
    defaultLanguage: Language? = nil,
    contextSnippetLength: Int = 50
) -> ContentTokenizer {
    let segmenter = JiebaSegmenter()
    _ = segmenter.initialize()

    return makeTextContentTokenizer(
        defaultLanguage: defaultLanguage,
        contextSnippetLength: contextSnippetLength,
        textTokenizerFactory: { language in
            // Use Jieba for Chinese text, default tokenizer for other languages
            if let lang = language, lang.code.bcp47.hasPrefix("zh") {
                return makeJiebaTextTokenizer(segmenter: segmenter)
            }
            return makeDefaultTextTokenizer(unit: .sentence, language: language)
        }
    )
}

/// Creates a TextTokenizer using Jieba for Chinese sentence splitting.
/// Returns ranges of sentences in the original text.
private func makeJiebaTextTokenizer(segmenter: JiebaSegmenter) -> TextTokenizer {
    func tokenize(_ text: String) throws -> [Range<String.Index>] {
        let sentences = segmenter.sentenceSplit(text)
        var ranges: [Range<String.Index>] = []
        var searchStart = text.startIndex

        for sentence in sentences {
            guard let range = text.range(of: sentence, range: searchStart..<text.endIndex) else {
                continue
            }
            ranges.append(range)
            searchStart = range.upperBound
        }

        return ranges
    }

    return tokenize
}
