import Foundation
import Testing
@testable import NaturalSuggestCore

struct PinyinInputTests {
    static let bundled = PinyinLexicon.bundled()

    @Test func bundledDictionaryConvertsEverydayPinyin() {
        let lexicon = Self.bundled
        #expect(lexicon.candidates(for: "nihao").first?.text == "你好")
        #expect(lexicon.candidates(for: "xiexie").first?.text == "谢谢")
        #expect(lexicon.candidates(for: "zhongguo").first?.text == "中国")
        #expect(lexicon.candidates(for: "yinhang").first?.text == "银行")
        #expect(lexicon.candidates(for: "nver").first?.text == "女儿")
        #expect(lexicon.candidates(for: "en").first?.text == "嗯")
        #expect(lexicon.candidates(for: "ni").first?.text == "你")
        #expect(lexicon.candidates(for: "le").contains { $0.text == "了" })
        #expect(lexicon.candidates(for: "liao").contains { $0.text == "了" })
    }

    @Test func sentencesSplitIntoWords() {
        let lexicon = Self.bundled
        #expect(lexicon.candidates(for: "woxiangquxuexiao").first == PinyinCandidate(text: "我想去学校", consumed: 16))
        #expect(lexicon.candidates(for: "jintiantianqihenhao").first?.text == "今天天气很好")
    }

    @Test func unfinishedSyllablesStillMatch() {
        let lexicon = Self.bundled
        #expect(lexicon.candidates(for: "zhon").prefix(3).contains { $0.text == "中" })
        #expect(lexicon.candidates(for: "zhongg").first?.text == "中国")
        #expect(lexicon.candidates(for: "w").contains { $0.text == "我" })
    }

    @Test func leadingWordsConvertPartOfTheInput() {
        let lexicon = PinyinLexicon(lines: ["我\two", "想\txiang", "西安\txi an", "先\txian"])
        let candidates = lexicon.candidates(for: "woxiang")
        #expect(candidates.first == PinyinCandidate(text: "我想", consumed: 7))
        #expect(candidates.contains(PinyinCandidate(text: "我", consumed: 2)))
        // Same letters, two spellings: the more frequent comes first.
        #expect(lexicon.candidates(for: "xian").map(\.text).prefix(2) == ["西安", "先"])
    }

    @Test func chosenWordsMoveUp() {
        let lexicon = PinyinLexicon(lines: ["是\tshi", "事\tshi", "时\tshi"])
        #expect(lexicon.candidates(for: "shi").first?.text == "是")
        #expect(lexicon.candidates(for: "shi", uses: { $0 == "事" ? 20 : 0 }).first?.text == "事")
    }

    @Test func rejectsAnythingButLowercaseLetters() {
        let lexicon = Self.bundled
        #expect(lexicon.candidates(for: "").isEmpty)
        #expect(lexicon.candidates(for: "ni hao").isEmpty)
        #expect(lexicon.candidates(for: "Nihao").isEmpty)
        #expect(lexicon.candidates(for: "nihao", limit: 3).count == 3)
    }

    @Test func memoryKeepsChineseWords() {
        var memory = WordCompletionMemory()
        memory.record("事情", after: nil, language: .chinese)
        memory.record("事情", after: nil, language: .chinese)
        #expect(memory.uses(of: "事情", language: .chinese) == 2)
        #expect(memory.uses(of: "事情", language: .korean) == 0)
        memory.record("abc", after: nil, language: .chinese)
        #expect(memory.uses(of: "abc", language: .chinese) == 0)
    }
}
