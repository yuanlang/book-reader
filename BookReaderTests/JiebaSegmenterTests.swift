import Testing
@testable import BookReader

@Suite("Jieba 分词测试")
struct JiebaSegmenterTests {

    @Test("初始化 Jieba 分词器")
    func testInitialization() {
        let segmenter = JiebaSegmenter()
        #expect(segmenter.initialize())
    }

    @Test("基本中文分词")
    func testBasicSegmentation() {
        let segmenter = JiebaSegmenter()
        #expect(segmenter.initialize())

        let words = segmenter.segment("我来到北京清华大学")
        #expect(!words.isEmpty)
        // Should contain "北京", "清华大学" etc.
        #expect(words.contains(where: { $0.contains("北京") || $0.contains("清华") }))
    }

    @Test("句子分割")
    func testSentenceSplit() {
        let segmenter = JiebaSegmenter()
        #expect(segmenter.initialize())

        let text = "今天天气不错。我们一起去公园玩吧！你喜欢吗？"
        let sentences = segmenter.sentenceSplit(text)

        #expect(sentences.count >= 3)
    }

    @Test("空文本处理")
    func testEmptyText() {
        let segmenter = JiebaSegmenter()
        #expect(segmenter.initialize())

        let words = segmenter.segment("")
        #expect(words.isEmpty)

        let sentences = segmenter.sentenceSplit("")
        #expect(sentences.isEmpty)
    }
}
