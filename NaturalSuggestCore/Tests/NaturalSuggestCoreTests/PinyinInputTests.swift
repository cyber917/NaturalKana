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

    @Test func bundledChatPhrasesAreVisibleWithoutPickingSingleCharacters() {
        for (input, text) in [
            ("shisha", "是啥"), ("gansha", "干啥"), ("weisha", "为啥"),
            ("zahuishi", "咋回事"), ("shayisi", "啥意思"),
            ("zhendejiade", "真的假的"),
            ("xiaosiwole", "笑死我了"), ("bengbuzhule", "绷不住了"),
            ("wozhenfule", "我真服了"), ("haojiahuo", "好家伙"),
            ("baozimen", "宝子们"), ("sheidonga", "谁懂啊"),
            ("juejuezi", "绝绝子"),
            ("pofang", "破防"), ("bailan", "摆烂")
        ] {
            #expect(Self.bundled.candidates(for: input).prefix(2).contains(PinyinCandidate(text: text, consumed: input.count)), "\(input) → \(text)")
        }
        #expect(Self.bundled.candidates(for: "shisha").first?.text == "是啥")
        #expect(Self.bundled.candidates(for: "nidemingzishisha").first?.text == "你的名字是啥")
    }

    @Test func chatPhrasesSupportInitialsTyposAndMemory() {
        #expect(Self.bundled.candidates(for: "zdjd").prefix(5).contains { $0.text == "真的假的" })
        #expect(Self.bundled.candidates(for: "shis").prefix(5).contains { $0.text == "是啥" })
        #expect(Self.bundled.candidates(for: "shishaa").prefix(5).contains { $0.text == "是啥" })
        #expect(Self.bundled.candidates(for: "shs", uses: { $0 == "是啥" ? 20 : 0 }).first?.text == "是啥")
    }

    @Test func supplementalRanksDoNotDuplicateWordsOrOverrideUserLearning() {
        let lexicon = PinyinLexicon(lines: ["试杀\tshi sha", "是啥\tshi sha\t1500", "是啥\tshi sha\t100"])
        #expect(lexicon.candidates(for: "shisha").filter { $0.text == "是啥" }.count == 1)
        #expect(lexicon.candidates(for: "shisha", uses: { $0 == "是啥" ? 10 : 0 }).first?.text == "是啥")
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

    @Test func fullAndAbbreviatedSyllablesMixAcrossWords() {
        let lexicon = Self.bundled
        for input in ["youdianwt", "ydwenti", "youdwt", "ydwt"] {
            #expect(lexicon.candidates(for: input).contains(PinyinCandidate(text: "有点问题", consumed: input.count)))
        }
        #expect(lexicon.candidates(for: "youdianwt").first?.text == "有点问题")
        #expect(lexicon.candidates(for: "nh").first?.text == "你好")
        #expect(lexicon.candidates(for: "zhg").contains { $0.text == "中国" })
    }

    @Test func correctsOneTypoWithoutChangingConsumedLetters() {
        let lexicon = PinyinLexicon(lines: ["有点\tyou dian", "问题\twen ti", "你好\tni hao"])
        for input in ["youdianwneti", "youdianwennti", "youdianwentj", "youdianwnti", "nihoa", "nihhao", "niho"] {
            let expected = input.hasPrefix("you") ? "有点问题" : "你好"
            #expect(lexicon.candidates(for: input).first == PinyinCandidate(text: expected, consumed: input.count))
        }
        #expect(lexicon.candidates(for: "youdainwneti").first?.text != "有点问题")
    }

    @Test func abbreviatedPrefixLeavesUnconvertedSuffix() {
        let lexicon = PinyinLexicon(lines: ["你好\tni hao"])
        #expect(lexicon.candidates(for: "nhx").contains(PinyinCandidate(text: "你好", consumed: 2)))
    }

    @Test func bundledDictionaryOffersTypoCorrections() {
        for input in ["youdianwneti", "youdianwnti", "youdianwennti", "youdianwentj"] {
            #expect(Self.bundled.candidates(for: input).prefix(3).contains(PinyinCandidate(text: "有点问题", consumed: input.count)))
        }
        #expect(Self.bundled.candidates(for: "nihoa").first?.text == "你好")
    }

    @Test func longFullPinyinStillConverts() {
        let lexicon = PinyinLexicon(lines: ["你好\tni hao"])
        let input = String(repeating: "nihao", count: 14)
        #expect(lexicon.candidates(for: input).first == PinyinCandidate(text: String(repeating: "你好", count: 14), consumed: input.count))
    }

    @Test func exactSpellingWinsAndMemoryRanksAbbreviations() {
        let lexicon = PinyinLexicon(lines: ["呢\tne", "你\tni", "你好\tni hao", "年后\tnian hou"])
        #expect(lexicon.candidates(for: "ni").first?.text == "你")
        #expect(lexicon.candidates(for: "nh", uses: { $0 == "年后" ? 10 : 0 }).first?.text == "年后")
        #expect(lexicon.candidates(for: "nh", limit: 1).count == 1)
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
