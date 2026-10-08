import Foundation
import Testing
@testable import NaturalSuggestCore

struct LanguagePackTests {
    @Test func everyBundledPackIsComplete() throws {
        let packs = LanguagePack.bundled
        #expect(packs.map(\.id).prefix(3) == ["japanese", "english", "chinese"])
        #expect(Set(packs.map(\.order)).count == packs.count)
        for pack in packs {
            #expect(!pack.prompt.isEmpty && pack.prompt.contains("maximum_suggestions"), "prompt.txt of \(pack.id)")
            #expect(pack.registerTitles["casual"] != nil && pack.registerTitles["polite"] != nil, "registerTitles of \(pack.id)")
            #expect(["japanese", "english", "chinese", "generic"].contains(pack.rules), "rules of \(pack.id)")
            #expect(pack.rules != "generic" || pack.generic != nil, "generic rules of \(pack.id)")
            #expect(UIText.table[pack.title]?["en"] != nil && UIText.table[pack.title]?["ja"] != nil, "interface title of \(pack.id)")
            let language = try #require(SuggestionLanguage(rawValue: pack.id))
            #expect(language.draftProfile.accepts(pack.testDraft, composingLatin: false), "test draft of \(pack.id)")
            if let signal = pack.detect.signal { #expect((try? NSRegularExpression(pattern: signal)) != nil, "signal of \(pack.id)") }
        }
    }
    @Test func savedLanguagesStillDecode() throws {
        for raw in ["japanese", "english", "chinese"] {
            let decoded = try JSONDecoder().decode(SuggestionLanguage.self, from: Data("\"\(raw)\"".utf8))
            #expect(decoded.rawValue == raw)
        }
        #expect(String(data: try JSONEncoder().encode(SuggestionLanguage.chinese), encoding: .utf8) == "\"chinese\"")
        #expect(SuggestionLanguage(rawValue: "klingon") == nil)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(SuggestionLanguage.self, from: Data("\"klingon\"".utf8)) }
    }
    @Test func lexiconsComeFromTheirPacks() {
        #expect(!Lexicon.bundled().entries.isEmpty)
        #expect(Lexicon.bundled(.chinese).entries.allSatisfy { $0.gloss_zh != nil })
        #expect(Lexicon.bundled(.english).entries.isEmpty)
    }

    // Generic rules, as a Korean, Russian or French pack would declare them.
    private let hangul = GenericProfile(rules: .init(letters: "[\\uAC00-\\uD7A3\\u1100-\\u11FF\\u3130-\\u318F]", forbidden: "[\\u3040-\\u30FF\\u4E00-\\u9FFF]", latinAllowlist: ["OK"], denied: ["번역"]))
    private let cyrillic = GenericProfile(rules: .init(letters: "[\\u0400-\\u04FF]", latinAllowlist: ["OK"]))
    private let latin = GenericProfile(rules: .init(letters: "[A-Za-z\\u00C0-\\u024F]", forbidden: "[\\u0400-\\u04FF\\u3040-\\u30FF\\u4E00-\\u9FFF]"))

    @Test func genericDraftsAllowShortForeignWords() {
        #expect(hangul.accepts("내일 회의가 있어서 못 가요"))
        #expect(hangul.accepts("내일 meeting이 있어요"))
        #expect(!hangul.accepts("I have a meeting tomorrow"))
        #expect(!hangul.accepts("今日は天気がいいですね"))
        #expect(!hangul.accepts("이 문장을 번역해 주세요"))
        #expect(cyrillic.accepts("Я завтра работаю"))
        #expect(!cyrillic.accepts("Je travaille demain"))
        #expect(latin.accepts("Je suis très fatigué aujourd'hui"))
        #expect(!latin.accepts("Я завтра работаю"))
        #expect(!hangul.accepts("내일", composingLatin: true))
    }
    @Test func genericCandidatesStayInTheLanguage() {
        #expect(hangul.acceptsCandidate("내일 회의가 있어요.", original: "내일 meeting이 있어요"))
        #expect(!hangul.acceptsCandidate("내일 meeting이 있어요.", original: "내일 meeting이 있어요"))
        #expect(hangul.acceptsCandidate("제 iPhone이 고장 났어요.", original: "제 iPhone이 고장 났어"))
        #expect(hangul.acceptsCandidate("OK, 알겠어요.", original: "알겠어"))
        #expect(!hangul.acceptsCandidate("明日は会議があります。", original: "내일 회의"))
        #expect(!hangul.acceptsCandidate("내일 会議가 있어요", original: "내일 회의"))
        #expect(cyrillic.acceptsCandidate("Я завтра работаю.", original: "Я завтра работать"))
        #expect(latin.acceptsCandidate("Je suis très fatiguée aujourd'hui.", original: "Je suis tres fatigue"))
        #expect(!latin.acceptsCandidate("Я завтра работаю.", original: "Je travaille"))
    }
}
